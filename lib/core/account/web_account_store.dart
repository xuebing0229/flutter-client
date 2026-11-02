import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'account_models.dart';
import 'account_local_state.dart';

export 'account_local_state.dart' show AccountStatus, LocalAccountSummary;
import 'account_activation_flow.dart';
import 'activation_api.dart';
import 'account_session_logic.dart';
import 'account_session_controller.dart';
import 'offline_license.dart';
import '../web/web_platform_bridge.dart';

class WebAccountStore extends ChangeNotifier {
  WebAccountStore({
    OfflineLicenseVerifier verifier = const OfflineLicenseVerifier(),
    ActivationApiClient activationApi = const ActivationApiClient(),
  })  : _verifier = verifier,
        _activationApi = activationApi;

  static const String _storageKey = 'adventurers-guild.web.accounts.v1';

  final OfflineLicenseVerifier _verifier;
  final ActivationApiClient _activationApi;
  final Map<String, LocalAccountRecord> _accounts =
      <String, LocalAccountRecord>{};
  final Random _random = Random.secure();

  AccountStatus status = AccountStatus.loading;
  String? _selectedAccountId;

  LocalAccountRecord? get _selectedRecord {
    final id = _selectedAccountId;
    return id == null ? null : _accounts[id];
  }

  String? get accountId => _selectedAccountId;
  String? get accountName => _selectedRecord?.syncState.accountName;
  String? get accountPassword =>
      status == AccountStatus.unlocked ? _selectedRecord?.syncState.password : null;
  String? get currentDeviceId => _selectedRecord?.currentDeviceId;
  AccountSyncState? get syncSnapshot => _selectedRecord?.syncState;
  bool get isUnlocked => status == AccountStatus.unlocked;

  List<AccountDevice> get activeDevices =>
      sortedActiveAccountDevices(syncSnapshot);

  List<LocalAccountSummary> get localAccounts =>
      sortedLocalAccountSummaries(_accounts);

  Future<void> load() async {
    try {
      final source = webStorageGet(_storageKey);
      if (source == null || source.trim().isEmpty) {
        status = AccountStatus.unactivated;
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
        final record = LocalAccountRecord.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
        _accounts[record.syncState.accountId] = record;
        _rememberDeviceId(
          record.syncState.accountId,
          record.currentDeviceId,
        );
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
      status = AccountStatus.unactivated;
    }
    notifyListeners();
  }

  void _restoreStatus() {
    status = accountStatusForRecord(_selectedRecord);
  }

  Future<void> activate({
    required String activationCode,
    required String accountName,
    required String password,
  }) async {
    final trimmedName = accountName.trim();
    final license = await verifyAndRedeemAccountActivation(
      activationCode: activationCode,
      accountName: accountName,
      password: password,
      verifier: _verifier,
      activationApi: _activationApi,
      hasLocalAccount: _accounts.containsKey,
      claimFor: _activationClaimFor,
      clearClaim: _clearActivationClaim,
    );

    final deviceId = _randomDeviceId();
    _rememberDeviceId(license.accountId, deviceId);
    final state = createActivatedAccountState(
      accountId: license.accountId,
      accountName: trimmedName,
      password: password,
      deviceId: deviceId,
      deviceName: '网页设备',
      platform: 'web',
    );

    _accounts[license.accountId] = LocalAccountRecord(
      syncState: state,
      currentDeviceId: deviceId,
      stayLoggedIn: true,
      activationSerial: license.serial,
    );
    _selectedAccountId = license.accountId;
    status = AccountStatus.unlocked;
    await _persist();
    await _clearActivationClaim(license.accountId);
    notifyListeners();
  }

  Future<void> importAccountState(
    AccountSyncState incoming, {
    bool select = true,
    bool stayLoggedIn = false,
    String? preferredDeviceId,
  }) async {
    final existing = _accounts[incoming.accountId];
    if (existing != null) {
      final merged = existing.syncState.merge(incoming);
      _accounts[incoming.accountId] = existing.copyWith(
        syncState: touchAccountDeviceState(
          merged,
          deviceId: existing.currentDeviceId,
          createIfMissing: true,
          defaultName: '网页设备',
          platform: 'web',
        ),
        stayLoggedIn: stayLoggedIn,
      );
    } else {
      final preferred = preferredDeviceId?.trim();
      var deviceId =
          preferred != null &&
              preferred.length >= 16 &&
              !incoming.isRevoked(preferred)
          ? preferred
          : _deviceIdForAccount(incoming.accountId);
      if (incoming.isRevoked(deviceId)) {
        deviceId = _randomDeviceId();
      }
      _rememberDeviceId(incoming.accountId, deviceId);
      _accounts[incoming.accountId] = LocalAccountRecord(
        syncState: touchAccountDeviceState(
          incoming,
          deviceId: deviceId,
          createIfMissing: true,
          defaultName: '网页设备',
          platform: 'web',
        ),
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

    var merged = record.syncState.merge(incoming);
    // Receiving a peer snapshot is not local user activity. Updating this
    // browser's lastSeenAt on every remote retry made otherwise identical
    // snapshots look different and forced the whole app to rebuild forever.
    // Only create the current browser record when it is genuinely missing.
    if (!merged.devices.containsKey(record.currentDeviceId)) {
      merged = touchAccountDeviceState(
        merged,
        deviceId: record.currentDeviceId,
        createIfMissing: true,
        defaultName: '网页设备',
        platform: 'web',
      );
    }

    if (jsonEncode(merged.toJson()) ==
        jsonEncode(record.syncState.toJson())) {
      return;
    }

    _accounts[record.syncState.accountId] = record.copyWith(syncState: merged);
    await _persist();
    notifyListeners();
  }

  AccountSessionController _sessionController() {
    return AccountSessionController(
      accounts: _accounts,
      getSelectedAccountId: () => _selectedAccountId,
      setSelectedAccountId: (value) => _selectedAccountId = value,
      getStatus: () => status,
      setStatus: (value) => status = value,
      persist: _persist,
      notify: notifyListeners,
      touchForLogin: (record) async => touchAccountDeviceState(
        record.syncState,
        deviceId: record.currentDeviceId,
        createIfMissing: false,
        platform: 'web',
      ),
    );
  }

  Future<void> selectLocalAccount(String accountId) =>
      _sessionController().selectLocalAccount(accountId);

  Future<bool> unlock({
    required String accountName,
    required String password,
  }) =>
      _sessionController().unlock(
        accountName: accountName,
        password: password,
      );

  Future<void> renameDevice(String deviceId, String name) =>
      _sessionController().renameDevice(deviceId, name);

  Future<void> renameCurrentDevice(String name) =>
      _sessionController().renameCurrentDevice(name);

  Future<void> renameAccount(String name) =>
      _sessionController().renameAccount(name);

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _sessionController().changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  Future<void> revokeDevice(String deviceId) =>
      _sessionController().revokeDevice(deviceId);

  Future<void> lock() => _sessionController().lock();

  Future<void> returnToAccountChooser() =>
      _sessionController().returnToAccountChooser();

  Future<void> removeSelectedLocalAccount() async {
    final id = _selectedAccountId;
    if (id == null) return;
    final record = _accounts[id];
    if (record != null) {
      _rememberDeviceId(id, record.currentDeviceId);
    }
    try {
      webStorageRemove('adventurers-guild.web.workspace.v2.$id');
    } catch (_) {}
    _accounts.remove(id);
    _selectedAccountId = null;
    status = AccountStatus.unactivated;
    await _persist();
    notifyListeners();
  }

  Future<String> _activationClaimFor(ActivationLicense license) async {
    final key =
        'adventurers-guild.web.activation-claim.v1.${license.accountId}';
    try {
      final source = webStorageGet(key);
      if (source != null && source.trim().isNotEmpty) {
        final decoded = jsonDecode(source);
        if (decoded is Map &&
            decoded['serial'] == license.serial &&
            decoded['claimId'] is String &&
            (decoded['claimId'] as String).length >= 16) {
          return decoded['claimId'] as String;
        }
      }
    } catch (_) {}

    final claimId =
        'claim-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${_random.nextInt(0x7fffffff).toRadixString(36)}';
    webStorageSet(
      key,
      jsonEncode(<String, dynamic>{
        'accountId': license.accountId,
        'serial': license.serial,
        'claimId': claimId,
      }),
    );
    return claimId;
  }

  Future<void> _clearActivationClaim(String accountId) async {
    try {
      webStorageRemove(
        'adventurers-guild.web.activation-claim.v1.$accountId',
      );
    } catch (_) {}
  }

  String _deviceIdForAccount(String accountId) {
    final key = 'adventurers-guild.web.device.v1.$accountId';
    try {
      final existing = webStorageGet(key);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }
    } catch (_) {}
    final next = _randomDeviceId();
    _rememberDeviceId(accountId, next);
    return next;
  }

  void _rememberDeviceId(String accountId, String deviceId) {
    try {
      webStorageSet(
        'adventurers-guild.web.device.v1.$accountId',
        deviceId,
      );
    } catch (_) {}
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
    webStorageSet(_storageKey, jsonEncode(payload));
  }
}
