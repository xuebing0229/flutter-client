import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../core/storage/atomic_file.dart';
import 'license_issuer_api.dart';
import 'license_issuer_engine.dart';
import 'license_issuer_models.dart';

class LicenseIssuerStore extends ChangeNotifier {
  LicenseIssuerStore({
    LicenseIssuerEngine engine = const LicenseIssuerEngine(),
    LicenseIssuerApi api = const LicenseIssuerApi(),
  })  : _engine = engine,
        _api = api;

  static const String _fileName = 'license-issuer-history-v1.json';

  final LicenseIssuerEngine _engine;
  final LicenseIssuerApi _api;
  final Lock _serverLock = Lock();
  Future<void> _saveTail = Future<void>.value();

  final List<IssuedLicenseRecord> _records = <IssuedLicenseRecord>[];
  bool _loaded = false;
  bool _connected = false;
  bool _serverBackedCache = false;
  String _adminName = '';
  String? _adminToken;

  bool get loaded => _loaded;
  bool get serverConfigured => _api.isConfigured;
  bool get isConnected => _connected;
  String get adminName => _adminName;
  bool get hasAdminName => _adminName.isNotEmpty;
  List<IssuedLicenseRecord> get records =>
      List<IssuedLicenseRecord>.unmodifiable(_records);

  IssuedLicenseRecord? recordByAccountId(String accountId) {
    for (final record in _records) {
      if (record.accountId == accountId) return record;
    }
    return null;
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('发码历史格式无效。');
        }
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final schemaVersion = map['schemaVersion'];
        if (schemaVersion != 2 &&
            schemaVersion != 3 &&
            schemaVersion != 4) {
          throw const FormatException('发码历史版本不匹配。');
        }

        final adminName = map['adminName'];
        if (adminName != null && adminName is! String) {
          throw const FormatException('管理员昵称格式无效。');
        }
        _adminName = (adminName as String?)?.trim() ?? '';
        _serverBackedCache =
            schemaVersion == 4 && map['serverBackedCache'] == true;

        final rawRecords = map['records'];
        if (rawRecords is! List) {
          throw const FormatException('发码历史记录格式无效。');
        }

        final records = <IssuedLicenseRecord>[];
        final serials = <String>{};
        for (final item in rawRecords) {
          if (item is! Map) {
            throw const FormatException('发码历史记录格式无效。');
          }
          final record = IssuedLicenseRecord.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (!serials.add(record.serial)) {
            throw const FormatException('发码历史包含重复编号。');
          }
          records.add(record);
        }
        _records
          ..clear()
          ..addAll(records);
      }
    } catch (_) {
      // A damaged cache must not block access to the online issuer.
    }

    _sortRecords();
    _loaded = true;
    notifyListeners();
  }

  Future<IssuerAdminSession> registerAdmin({
    required String setupKey,
    required String name,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 24) {
      throw const FormatException('管理昵称需要在 1–24 个字符之间。');
    }
    return _api.registerAdmin(setupKey: setupKey, name: trimmed);
  }

  Future<void> connectAdmin(String token) {
    return _serverLock.synchronized(() async {
      final normalized = token.trim();
      if (normalized.isEmpty) {
        throw const FormatException('管理员凭据为空。');
      }

      final session = await _api.me(normalized);
      _adminToken = normalized;
      _adminName = session.name;

      try {
        if (!_serverBackedCache && _records.isNotEmpty) {
          await _migrateLegacyRecords(normalized);
        }
        await _refreshWithToken(normalized);
        _serverBackedCache = true;
        await _save();

        // Do not expose a connected issuer while migration/refresh is still in
        // flight. Otherwise the UI can start generating codes against a ledger
        // that has not finished synchronizing yet.
        _connected = true;
        notifyListeners();
      } catch (_) {
        // Never allow generation against a ledger that failed to synchronize.
        // Keep the token in secure storage so the user can simply reconnect.
        _connected = false;
        notifyListeners();
        rethrow;
      }
    });
  }

  Future<void> disconnectAdmin() async {
    _adminToken = null;
    _connected = false;
    notifyListeners();
  }

  Future<void> renameAdmin(String name) {
    return _serverLock.synchronized(() async {
      final token = _requireToken();
      final trimmed = name.trim();
      if (trimmed.isEmpty || trimmed.length > 24) {
        throw const FormatException('管理昵称需要在 1–24 个字符之间。');
      }
      final session = await _api.renameAdmin(
        token: token,
        name: trimmed,
      );
      _adminName = session.name;
      await _refreshAfterMutation(token);
    });
  }

  Future<void> refresh() {
    return _serverLock.synchronized(() async {
      final token = _requireToken();
      await _refreshWithToken(token);
      await _save();
      notifyListeners();
    });
  }

  Future<void> _refreshWithToken(String token) async {
    final remote = await _api.listLicenses(token);
    _records
      ..clear()
      ..addAll(remote);
    _sortRecords();
    _serverBackedCache = true;
  }

  Future<void> _migrateLegacyRecords(String token) async {
    final legacy = List<IssuedLicenseRecord>.from(_records)
      ..sort((a, b) {
        final ai = int.tryParse(a.serial) ?? 0;
        final bi = int.tryParse(b.serial) ?? 0;
        return ai.compareTo(bi);
      });

    // The shared server ledger is authoritative for globally unique serials
    // and account identities. Old local AW1/AW2 caches can legitimately carry
    // records that were already imported or replaced on another administrator
    // device, so those duplicates must never block admin login.
    final remote = await _api.listLicenses(token);
    final occupiedSerials = <String>{
      for (final record in remote) record.serial,
    };
    final occupiedAccountIds = <String>{
      for (final record in remote) record.accountId,
    };
    final occupiedCodes = <String>{
      for (final record in remote)
        if (record.activationCode.trim().isNotEmpty)
          record.activationCode.trim(),
    };

    for (final record in legacy) {
      final activationCode = record.activationCode.trim();
      if (occupiedSerials.contains(record.serial) ||
          occupiedAccountIds.contains(record.accountId) ||
          (activationCode.isNotEmpty && occupiedCodes.contains(activationCode))) {
        continue;
      }

      try {
        final imported = await _api.importLegacy(
          token: token,
          record: record,
        );
        occupiedSerials.add(imported.serial);
        occupiedAccountIds.add(imported.accountId);
        if (imported.activationCode.trim().isNotEmpty) {
          occupiedCodes.add(imported.activationCode.trim());
        }
      } on IssuerApiException catch (error) {
        // A concurrent administrator may have imported the same historical
        // serial/account after the initial list call. Treat that the same as
        // an already-present server record instead of failing admin login.
        if (error.code == 'import_conflict') continue;
        rethrow;
      }
    }
    _serverBackedCache = true;
  }

  Future<void> _refreshAfterMutation(String token) async {
    try {
      await _refreshWithToken(token);
    } catch (_) {
      // The mutation itself already succeeded. Keep its returned state locally
      // and let the next foreground/action refresh reconcile the whole ledger.
    }
    await _save();
    notifyListeners();
  }

  Future<Never> _refreshAfterStale(
    String token,
    IssuerApiException error,
  ) async {
    try {
      await _refreshWithToken(token);
      await _save();
      notifyListeners();
    } catch (_) {
      // Preserve the concurrency error; a later automatic refresh can retry.
    }
    throw error;
  }

  Future<IssuedLicenseRecord> issueOne({
    required String privateKeySource,
    String note = '',
  }) {
    return _serverLock.synchronized(() async {
      final token = _requireToken();
      final reserved = await _api.reserve(token: token, note: note);
      final signed = await _engine.issue(
        privateKeySource: privateKeySource,
        serial: reserved.serial,
        accountId: reserved.accountId,
        note: note,
      );
      final record = await _api.commit(
        token: token,
        accountId: reserved.accountId,
        activationCode: signed.activationCode,
      );
      _upsert(record);
      await _refreshAfterMutation(token);
      return record;
    });
  }

  Future<List<IssuedLicenseRecord>> issueBatch({
    required String privateKeySource,
    required int count,
  }) {
    if (count < 1 || count > 100) {
      throw const FormatException('单次批量生成数量需要在 1–100 之间。');
    }

    return _serverLock.synchronized(() async {
      final token = _requireToken();
      final created = <IssuedLicenseRecord>[];
      for (var i = 0; i < count; i++) {
        final reserved = await _api.reserve(token: token);
        final signed = await _engine.issue(
          privateKeySource: privateKeySource,
          serial: reserved.serial,
          accountId: reserved.accountId,
        );
        final record = await _api.commit(
          token: token,
          accountId: reserved.accountId,
          activationCode: signed.activationCode,
        );
        created.add(record);
        _upsert(record);
        // Persist each successful item so a later network interruption cannot
        // make an already-issued code disappear from the local history.
        await _save();
      }
      await _refreshAfterMutation(token);
      return created;
    });
  }

  Future<void> updateNote(
    String accountId,
    String note, {
    int? expectedRevision,
  }) {
    return _serverLock.synchronized(() async {
      final token = _requireToken();
      try {
        final record = await _api.updateNote(
          token: token,
          accountId: accountId,
          note: note,
          expectedRevision: expectedRevision,
        );
        _upsert(record);
        await _refreshAfterMutation(token);
      } on IssuerApiException catch (error) {
        if (error.isStaleRecord) {
          await _refreshAfterStale(token, error);
        }
        rethrow;
      }
    });
  }

  Future<void> toggleSold(String accountId) {
    return _serverLock.synchronized(() async {
      final token = _requireToken();

      // A one-tap toggle should use the server's current state, not a stale
      // screen snapshot. A revision precondition still catches the tiny race
      // between this refresh and the write.
      await _refreshWithToken(token);
      final current = recordByAccountId(accountId);
      if (current == null) {
        await _save();
        notifyListeners();
        throw const IssuerApiException('这条发码记录已经不存在。');
      }

      try {
        final record = await _api.setSold(
          token: token,
          accountId: accountId,
          sold: !current.isSold,
          expectedRevision: current.revision,
        );
        _upsert(record);
        await _refreshAfterMutation(token);
      } on IssuerApiException catch (error) {
        if (error.isStaleRecord) {
          await _refreshAfterStale(token, error);
        }
        rethrow;
      }
    });
  }

  Future<void> delete(
    String accountId, {
    int? expectedRevision,
  }) {
    return _serverLock.synchronized(() async {
      final token = _requireToken();
      try {
        await _api.deleteLicense(
          token: token,
          accountId: accountId,
          expectedRevision: expectedRevision,
        );
        _records.removeWhere((item) => item.accountId == accountId);
        await _refreshAfterMutation(token);
      } on IssuerApiException catch (error) {
        if (error.isStaleRecord) {
          await _refreshAfterStale(token, error);
        }
        rethrow;
      }
    });
  }

  Future<int> deleteMany(
    Iterable<String> accountIds, {
    Map<String, int> expectedRevisions = const <String, int>{},
  }) {
    final ids = accountIds.toSet();
    if (ids.isEmpty) return Future<int>.value(0);

    return _serverLock.synchronized(() async {
      final token = _requireToken();

      var deleted = 0;
      try {
        for (final accountId in ids) {
          final current = recordByAccountId(accountId);
          if (current == null) continue;
          await _api.deleteLicense(
            token: token,
            accountId: accountId,
            expectedRevision:
                expectedRevisions[accountId] ?? current.revision,
          );
          _records.removeWhere((item) => item.accountId == accountId);
          deleted += 1;
        }
        await _refreshAfterMutation(token);
        return deleted;
      } on IssuerApiException catch (error) {
        if (error.isStaleRecord) {
          await _refreshAfterStale(token, error);
        }
        await _refreshAfterMutation(token);
        rethrow;
      }
    });
  }

  String exportCsv() {
    final rows = <List<String>>[
      <String>[
        'serial',
        'account_id',
        'activation_code',
        'status',
        'generated_by',
        'sold_by',
        'note',
        'created_at',
        'sold_at',
        'redeemed_at',
      ],
      for (final item in _records)
        <String>[
          item.serial,
          item.accountId,
          item.activationCode,
          item.isRedeemed
              ? 'redeemed'
              : item.isSold
                  ? 'sold'
                  : 'unused',
          item.generatedBy,
          item.soldBy ?? '',
          item.note,
          item.createdAt.toLocal().toIso8601String(),
          item.soldAt?.toLocal().toIso8601String() ?? '',
          item.redeemedAt?.toLocal().toIso8601String() ?? '',
        ],
    ];

    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  String _requireToken() {
    final token = _adminToken;
    if (!_connected || token == null || token.isEmpty) {
      throw const IssuerApiException(
        '发码器尚未连接激活服务器，请先恢复管理员连接。',
        code: 'not_connected',
      );
    }
    return token;
  }

  void _upsert(IssuedLicenseRecord record) {
    final index = _records.indexWhere(
      (item) => item.accountId == record.accountId,
    );
    if (index < 0) {
      _records.add(record);
    } else {
      _records[index] = record;
    }
    _sortRecords();
  }

  void _sortRecords() {
    _records.sort((a, b) {
      final ai = int.tryParse(a.serial) ?? 0;
      final bi = int.tryParse(b.serial) ?? 0;
      if (ai != bi) return bi.compareTo(ai);
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _save() {
    final operation = _saveTail.then<void>((_) => _writeState());
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _writeState() async {
    final file = await _file();
    await file.parent.create(recursive: true);

    final payload = jsonEncode(<String, dynamic>{
      'schemaVersion': 4,
      'serverBackedCache': _serverBackedCache,
      'adminName': _adminName,
      'records': [for (final item in _records) item.toJson()],
    });

    await atomicWriteString(file, payload);
  }
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
