import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<void> connectAdmin(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw const FormatException('管理员凭据为空。');
    }

    final session = await _api.me(normalized);
    _adminToken = normalized;
    _adminName = session.name;
    _connected = true;
    notifyListeners();

    try {
      if (!_serverBackedCache && _records.isNotEmpty) {
        await _migrateLegacyRecords();
      }
      await refresh();
      _serverBackedCache = true;
      await _save();
    } catch (_) {
      // Never allow generation against a ledger that failed to synchronize.
      // Keep the token in secure storage so the user can simply reconnect.
      _connected = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnectAdmin() async {
    _adminToken = null;
    _connected = false;
    notifyListeners();
  }

  Future<void> renameAdmin(String name) async {
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
    await _save();
    notifyListeners();
  }

  Future<void> refresh() async {
    final token = _requireToken();
    final remote = await _api.listLicenses(token);
    _records
      ..clear()
      ..addAll(remote);
    _sortRecords();
    _serverBackedCache = true;
    await _save();
    notifyListeners();
  }

  Future<void> _migrateLegacyRecords() async {
    final token = _requireToken();
    final legacy = List<IssuedLicenseRecord>.from(_records)
      ..sort((a, b) {
        final ai = int.tryParse(a.serial) ?? 0;
        final bi = int.tryParse(b.serial) ?? 0;
        return ai.compareTo(bi);
      });

    for (final record in legacy) {
      await _api.importLegacy(token: token, record: record);
    }
    _serverBackedCache = true;
  }

  Future<IssuedLicenseRecord> issueOne({
    required String privateKeySource,
    String note = '',
  }) async {
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
    await _save();
    notifyListeners();
    return record;
  }

  Future<List<IssuedLicenseRecord>> issueBatch({
    required String privateKeySource,
    required int count,
  }) async {
    if (count < 1 || count > 100) {
      throw const FormatException('单次批量生成数量需要在 1–100 之间。');
    }

    final created = <IssuedLicenseRecord>[];
    for (var i = 0; i < count; i++) {
      created.add(
        await issueOne(
          privateKeySource: privateKeySource,
        ),
      );
    }
    return created;
  }

  Future<void> updateNote(String accountId, String note) async {
    final token = _requireToken();
    final record = await _api.updateNote(
      token: token,
      accountId: accountId,
      note: note,
    );
    _upsert(record);
    await _save();
    notifyListeners();
  }

  Future<void> setSold(String accountId, bool sold) async {
    final token = _requireToken();
    final record = await _api.setSold(
      token: token,
      accountId: accountId,
      sold: sold,
    );
    _upsert(record);
    await _save();
    notifyListeners();
  }

  Future<void> delete(String accountId) async {
    final token = _requireToken();
    await _api.deleteLicense(token: token, accountId: accountId);
    _records.removeWhere((item) => item.accountId == accountId);
    await _save();
    notifyListeners();
  }

  Future<int> deleteMany(Iterable<String> accountIds) async {
    final ids = accountIds.toSet();
    if (ids.isEmpty) return 0;

    var deleted = 0;
    for (final accountId in ids) {
      await delete(accountId);
      deleted += 1;
    }
    return deleted;
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
