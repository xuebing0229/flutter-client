import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'account_models.dart';
import 'offline_license.dart';

enum WebAccountStatus { loading, unactivated, locked, unlocked, revoked }

class WebLocalAccountSummary {
  const WebLocalAccountSummary({
    required this.accountId,
    required this.accountName,
  });

  final String accountId;
  final String accountName;
}

class _WebAccountRecord {
  const _WebAccountRecord({
    required this.syncState,
    required this.currentDeviceId,
    required this.stayLoggedIn,
    this.activationSerial,
  });

  final AccountSyncState syncState;
  final String currentDeviceId;
  final bool stayLoggedIn;
  final String? activationSerial;

  _WebAccountRecord copyWith({
    AccountSyncState? syncState,
    String? currentDeviceId,
    bool? stayLoggedIn,
    String? activationSerial,
  }) {
    return _WebAccountRecord(
      syncState: syncState ?? this.syncState,
      currentDeviceId: currentDeviceId ?? this.currentDeviceId,
      stayLoggedIn: stayLoggedIn ?? this.stayLoggedIn,
      activationSerial: activationSerial ?? this.activationSerial,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'syncState': syncState.toJson(),
        'currentDeviceId': currentDeviceId,
        'stayLoggedIn': stayLoggedIn,
        if (activationSerial != null) 'activationSerial': activationSerial,
      };

  factory _WebAccountRecord.fromJson(Map<String, dynamic> json) {
    final rawState = json['syncState'];
    final currentDeviceId = json['currentDeviceId'];
    final stayLoggedIn = json['stayLoggedIn'];
    final activationSerial = json['activationSerial'];
    if (rawState is! Map ||
        currentDeviceId is! String ||
        currentDeviceId.isEmpty ||
        stayLoggedIn is! bool ||
        (activationSerial != null && activationSerial is! String)) {
      throw const FormatException('网页账号记录格式无效。');
    }

    final state = AccountSyncState.fromCompatibleJson(
      rawState.map((key, value) => MapEntry(key.toString(), value)),
      allowMissingPassword: false,
    );
    if (!state.devices.containsKey(currentDeviceId)) {
      throw const FormatException('网页账号记录缺少当前设备。');
    }

    return _WebAccountRecord(
      syncState: state,
      currentDeviceId: currentDeviceId,
      stayLoggedIn: stayLoggedIn,
      activationSerial: activationSerial as String?,
    );
  }
}

class WebAccountStore extends ChangeNotifier {
  WebAccountStore({
    OfflineLicenseVerifier verifier = const OfflineLicenseVerifier(),
  }) : _verifier = verifier;

  static const String _storageKey = 'adventurers-guild.web.accounts.v1';

  final OfflineLicenseVerifier _verifier;
  final Map<String, _WebAccountRecord> _accounts =
      <String, _WebAccountRecord>{};
  final Random _random = Random.secure();

  WebAccountStatus status = WebAccountStatus.loading;
  String? _selectedAccountId;

  _WebAccountRecord? get _selectedRecord {
    final id = _selectedAccountId;
    return id == null ? null : _accounts[id];
  }

  String? get accountId => _selectedAccountId;
  String? get accountName => _selectedRecord?.syncState.accountName;
  String? get accountPassword =>
      status == WebAccountStatus.unlocked ? _selectedRecord?.syncState.password : null;
  String? get currentDeviceId => _selectedRecord?.currentDeviceId;
  AccountSyncState? get syncSnapshot => _selectedRecord?.syncState;
  bool get isUnlocked => status == WebAccountStatus.unlocked;

  List<WebLocalAccountSummary> get localAccounts {
    final result = <WebLocalAccountSummary>[
      for (final entry in _accounts.entries)
        WebLocalAccountSummary(
          accountId: entry.key,
          accountName: entry.value.syncState.accountName,
        ),
    ];
    result.sort(
      (a, b) =>
          a.accountName.toLowerCase().compareTo(b.accountName.toLowerCase()),
    );
    return result;
  }

  Future<void> load() async {
    try {
      final source = html.window.localStorage[_storageKey];
      if (source == null || source.trim().isEmpty) {
        status = WebAccountStatus.unactivated;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['schemaVersion'] != 1) {
        throw const FormatException('网页账号数据版本无效。');
      }

      _accounts.clear();
      final rawAccounts = decoded['accounts'];
      if (rawAccounts is! List) {
        throw const FormatException('网页账号列表格式无效。');
      }
      for (final item in rawAccounts) {
        if (item is! Map) {
          throw const FormatException('网页账号记录格式无效。');
        }
        final record = _WebAccountRecord.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
        _accounts[record.syncState.accountId] = record;
      }

      final selected = decoded['selectedAccountId'];
      if (selected != null && selected is! String) {
        throw const FormatException('网页当前账号格式无效。');
      }
      _selectedAccountId = selected as String?;
      if (_selectedAccountId != null &&
          !_accounts.containsKey(_selectedAccountId)) {
        _selectedAccountId = null;
      }
      _restoreStatus();
    } catch (_) {
      _accounts.clear();
      _selectedAccountId = null;
      status = WebAccountStatus.unactivated;
    }
    notifyListeners();
  }

  void _restoreStatus() {
    final record = _selectedRecord;
    if (record == null) {
      status = WebAccountStatus.unactivated;
      return;
    }
    if (record.syncState.isRevoked(record.currentDeviceId)) {
      status = WebAccountStatus.revoked;
      return;
    }
    status = record.stayLoggedIn
        ? WebAccountStatus.unlocked
        : WebAccountStatus.locked;
  }

  Future<void> activate({
    required String activationCode,
    required String accountName,
    required String password,
  }) async {
    final trimmedName = accountName.trim();
    if (trimmedName.length < 2 || trimmedName.length > 32) {
      throw const FormatException('账号名长度需要在 2–32 个字符之间。');
    }
    if (password.length < 6) {
      throw const FormatException('密码至少需要 6 个字符。');
    }

    final license = await _verifier.verify(activationCode);
    if (_accounts.containsKey(license.accountId)) {
      throw const FormatException('这个账号已经保存在当前浏览器，请直接登录。');
    }

    final now = DateTime.now().toUtc();
    final deviceId = _randomDeviceId();
    final state = AccountSyncState(
      accountId: license.accountId,
      accountName: trimmedName,
      password: password,
      accountNameUpdatedAt: now,
      passwordUpdatedAt: now,
      devices: <String, AccountDevice>{
        deviceId: AccountDevice(
          id: deviceId,
          name: '网页设备',
          platform: 'web',
          firstSeenAt: now,
          lastSeenAt: now,
        ),
      },
      revocations: const <String, DeviceRevocation>{},
    );

    _accounts[license.accountId] = _WebAccountRecord(
      syncState: state,
      currentDeviceId: deviceId,
      stayLoggedIn: true,
      activationSerial: license.serial,
    );
    _selectedAccountId = license.accountId;
    status = WebAccountStatus.unlocked;
    await _persist();
    notifyListeners();
  }

  Future<void> importAccountState(
    AccountSyncState incoming, {
    bool select = true,
    bool stayLoggedIn = false,
  }) async {
    final existing = _accounts[incoming.accountId];
    if (existing != null) {
      final merged = existing.syncState.merge(incoming);
      _accounts[incoming.accountId] = existing.copyWith(
        syncState: _touchDevice(
          merged,
          existing.currentDeviceId,
          createIfMissing: true,
        ),
        stayLoggedIn: stayLoggedIn,
      );
    } else {
      final deviceId = _randomDeviceId();
      _accounts[incoming.accountId] = _WebAccountRecord(
        syncState: _touchDevice(incoming, deviceId, createIfMissing: true),
        currentDeviceId: deviceId,
        stayLoggedIn: stayLoggedIn,
      );
    }

    if (select) {
      _selectedAccountId = incoming.accountId;
      _restoreStatus();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> mergeCurrentAccountState(AccountSyncState incoming) async {
    final record = _selectedRecord;
    if (record == null || incoming.accountId != record.syncState.accountId) {
      throw const FormatException('备份账号与当前登录账号不一致。');
    }
    final merged = _touchDevice(
      record.syncState.merge(incoming),
      record.currentDeviceId,
      createIfMissing: true,
    );
    _accounts[record.syncState.accountId] = record.copyWith(syncState: merged);
    await _persist();
    notifyListeners();
  }

  Future<void> selectLocalAccount(String accountId) async {
    final record = _accounts[accountId];
    if (record == null) {
      throw const FormatException('这个本机账号已经不存在。');
    }
    _selectedAccountId = accountId;
    _accounts[accountId] = record.copyWith(stayLoggedIn: false);
    _restoreStatus();
    await _persist();
    notifyListeners();
  }

  Future<bool> unlock({
    required String accountName,
    required String password,
  }) async {
    final record = _selectedRecord;
    if (record == null ||
        record.syncState.isRevoked(record.currentDeviceId)) {
      _restoreStatus();
      notifyListeners();
      return false;
    }

    final ok = accountName.trim() == record.syncState.accountName &&
        _constantTimeEquals(password, record.syncState.password);
    if (!ok) return false;

    final touched = _touchDevice(
      record.syncState,
      record.currentDeviceId,
      createIfMissing: false,
    );
    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: touched,
      stayLoggedIn: true,
    );
    status = WebAccountStatus.unlocked;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> lock() async {
    final record = _selectedRecord;
    if (record == null) {
      status = WebAccountStatus.unactivated;
      notifyListeners();
      return;
    }
    _accounts[record.syncState.accountId] =
        record.copyWith(stayLoggedIn: false);
    _restoreStatus();
    await _persist();
    notifyListeners();
  }

  Future<void> returnToAccountChooser() async {
    final record = _selectedRecord;
    if (record != null) {
      _accounts[record.syncState.accountId] =
          record.copyWith(stayLoggedIn: false);
    }
    _selectedAccountId = null;
    status = WebAccountStatus.unactivated;
    await _persist();
    notifyListeners();
  }

  Future<void> removeSelectedLocalAccount() async {
    final id = _selectedAccountId;
    if (id == null) return;
    _accounts.remove(id);
    _selectedAccountId = null;
    status = WebAccountStatus.unactivated;
    await _persist();
    notifyListeners();
  }

  AccountSyncState _touchDevice(
    AccountSyncState state,
    String deviceId, {
    required bool createIfMissing,
  }) {
    final now = DateTime.now().toUtc();
    final current = state.devices[deviceId];
    if (current == null && !createIfMissing) return state;

    final devices = <String, AccountDevice>{...state.devices};
    devices[deviceId] = current == null
        ? AccountDevice(
            id: deviceId,
            name: '网页设备',
            platform: 'web',
            firstSeenAt: now,
            lastSeenAt: now,
          )
        : current.copyWith(
            platform: 'web',
            lastSeenAt: now,
          );
    return state.copyWith(devices: devices);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var index = 0; index < a.length; index++) {
      result |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return result == 0;
  }

  String _randomDeviceId() {
    return 'web-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${_random.nextInt(0x7fffffff).toRadixString(36)}';
  }

  Future<void> _persist() async {
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'selectedAccountId': _selectedAccountId,
      'accounts': <Map<String, dynamic>>[
        for (final record in _accounts.values) record.toJson(),
      ],
    };
    html.window.localStorage[_storageKey] = jsonEncode(payload);
  }
}
