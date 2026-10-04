import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'account_models.dart';
import 'device_descriptor.dart';
import 'offline_license.dart';
import '../storage/atomic_file.dart';

enum AccountStatus { loading, unactivated, locked, unlocked, revoked }

class LocalAccountSummary {
  const LocalAccountSummary({
    required this.accountId,
    required this.accountName,
  });

  final String accountId;
  final String accountName;
}

class _LocalAccountRecord {
  const _LocalAccountRecord({
    required this.syncState,
    required this.currentDeviceId,
    required this.stayLoggedIn,
    this.activationSerial,
  });

  final AccountSyncState syncState;
  final String currentDeviceId;
  final String? activationSerial;
  final bool stayLoggedIn;

  _LocalAccountRecord copyWith({
    AccountSyncState? syncState,
    String? currentDeviceId,
    String? activationSerial,
    bool? stayLoggedIn,
  }) {
    return _LocalAccountRecord(
      syncState: syncState ?? this.syncState,
      currentDeviceId: currentDeviceId ?? this.currentDeviceId,
      activationSerial: activationSerial ?? this.activationSerial,
      stayLoggedIn: stayLoggedIn ?? this.stayLoggedIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'currentDeviceId': currentDeviceId,
    'activationSerial': activationSerial,
    'stayLoggedIn': stayLoggedIn,
    'syncState': syncState.toJson(),
  };

  factory _LocalAccountRecord.fromJson(
    Map<String, dynamic> json, {
    bool allowMissingPassword = false,
  }) {
    final rawSync = json['syncState'];
    if (rawSync is! Map) {
      throw const FormatException('本机账号记录缺少账号数据。');
    }
    final syncState = AccountSyncState.fromCompatibleJson(
      rawSync.map((key, value) => MapEntry(key.toString(), value)),
      allowMissingPassword: allowMissingPassword,
    );
    final currentDeviceId = json['currentDeviceId'];
    final activationSerial = json['activationSerial'];
    final stayLoggedIn = json['stayLoggedIn'];
    if (currentDeviceId is! String || currentDeviceId.isEmpty) {
      throw const FormatException('本机账号记录缺少当前设备 ID。');
    }
    if (activationSerial != null && activationSerial is! String) {
      throw const FormatException('本机账号激活编号格式无效。');
    }
    if (stayLoggedIn is! bool) {
      throw const FormatException('本机账号登录状态格式无效。');
    }
    if (!syncState.devices.containsKey(currentDeviceId)) {
      throw const FormatException('本机账号记录缺少当前设备。');
    }

    return _LocalAccountRecord(
      syncState: syncState,
      currentDeviceId: currentDeviceId,
      activationSerial: activationSerial as String?,
      stayLoggedIn: stayLoggedIn,
    );
  }
}

class AccountStore extends ChangeNotifier {
  AccountStore({
    OfflineLicenseVerifier verifier = const OfflineLicenseVerifier(),
  }) : _verifier = verifier;

  static const String _fileName = 'account-state-v1.json';
  static const String _accountsDirName = 'accounts';
  static const String _deviceIdentityFileName = 'local-device-id.txt';

  final OfflineLicenseVerifier _verifier;
  final Map<String, _LocalAccountRecord> _accounts =
      <String, _LocalAccountRecord>{};
  Future<void> _saveTail = Future<void>.value();

  AccountStatus status = AccountStatus.loading;
  String? _selectedAccountId;

  _LocalAccountRecord? get _selectedRecord {
    final id = _selectedAccountId;
    return id == null ? null : _accounts[id];
  }

  AccountSyncState? get _syncState => _selectedRecord?.syncState;
  String? get accountId => _selectedAccountId;
  String? get accountName => _syncState?.accountName;
  String? get accountPassword => isUnlocked ? _syncState?.password : null;
  Uint8List? get accountAvatarBytes {
    final encoded = _syncState?.avatarBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  String? get currentDeviceId => _selectedRecord?.currentDeviceId;
  String? get activationSerial => _selectedRecord?.activationSerial;
  AccountSyncState? get syncSnapshot => _syncState;
  bool get isActivated => _syncState?.hasCredentials == true;
  bool get isUnlocked => status == AccountStatus.unlocked;

  List<LocalAccountSummary> get localAccounts {
    final items = <LocalAccountSummary>[
      for (final entry in _accounts.entries)
        LocalAccountSummary(
          accountId: entry.key,
          accountName: entry.value.syncState.accountName,
        ),
    ];
    items.sort(
      (a, b) =>
          a.accountName.toLowerCase().compareTo(b.accountName.toLowerCase()),
    );
    return items;
  }

  bool hasActiveLocalAccount(String accountId) {
    final record = _accounts[accountId];
    return record != null &&
        !record.syncState.isRevoked(record.currentDeviceId);
  }

  List<String> get revokedLocalAccountIds => <String>[
    for (final entry in _accounts.entries)
      if (entry.value.syncState.isRevoked(entry.value.currentDeviceId))
        entry.key,
  ];

  List<AccountDevice> get activeDevices {
    final state = _syncState;
    if (state == null) return const <AccountDevice>[];
    final devices = state.activeDevices.toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return devices;
  }

  int get revokedDeviceCount => _syncState?.revocations.length ?? 0;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<File> _deviceIdentityFile(String accountId) async {
    final directory = await getApplicationSupportDirectory();
    final safeAccountId = requireValidAccountId(accountId);
    return File(
      '${directory.path}/$_accountsDirName/'
      '$safeAccountId/$_deviceIdentityFileName',
    );
  }

  Future<String?> _readDeviceIdentity(AccountSyncState state) async {
    try {
      final file = await _deviceIdentityFile(state.accountId);
      if (!await file.exists()) return null;
      final deviceId = (await file.readAsString()).trim();
      if (deviceId.isEmpty || !state.devices.containsKey(deviceId)) {
        return null;
      }
      return deviceId;
    } catch (_) {
      return null;
    }
  }

  Future<void> load({
    Future<List<AccountSyncState>> Function()? recoveryLoader,
  }) async {
    var needsRecovery = false;

    try {
      final file = await _file();
      if (!await file.exists()) {
        needsRecovery = true;
      } else {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('账号数据格式无效。');
        }
        final json = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final schemaVersion = json['schemaVersion'];
        if (schemaVersion is! int || schemaVersion < 1 || schemaVersion > 4) {
          throw const FormatException('本机账号数据版本不匹配。');
        }

        _accounts.clear();

        final rawAccounts = json['accounts'];
        final migrated = schemaVersion != 4;
        if (rawAccounts is List) {
          for (final item in rawAccounts) {
            if (item is! Map) {
              throw const FormatException('本机账号记录格式无效。');
            }
            final map = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final record = _LocalAccountRecord.fromJson(
              map,
              allowMissingPassword: schemaVersion < 4,
            );
            final accountId = record.syncState.accountId;
            if (_accounts.containsKey(accountId)) {
              throw const FormatException('本机账号数据包含重复账号。');
            }
            _accounts[accountId] = record;
          }
        } else if (schemaVersion < 4) {
          final rawSync = json['syncState'];
          final legacyDeviceId = json['currentDeviceId'];
          if (rawSync is! Map ||
              legacyDeviceId is! String ||
              legacyDeviceId.isEmpty) {
            throw const FormatException('旧版本机账号数据格式无效。');
          }
          var syncState = AccountSyncState.fromCompatibleJson(
            rawSync.map((key, value) => MapEntry(key.toString(), value)),
            allowMissingPassword: true,
          );
          if (!syncState.devices.containsKey(legacyDeviceId)) {
            final now = DateTime.now().toUtc();
            syncState = syncState.copyWith(
              devices: <String, AccountDevice>{
                ...syncState.devices,
                legacyDeviceId: AccountDevice(
                  id: legacyDeviceId,
                  name: '当前设备',
                  platform: 'unknown',
                  firstSeenAt: now,
                  lastSeenAt: now,
                ),
              },
            );
          }
          _accounts[syncState.accountId] = _LocalAccountRecord(
            syncState: syncState,
            currentDeviceId: legacyDeviceId,
            activationSerial: json['activationSerial'] as String?,
            stayLoggedIn: json['stayLoggedIn'] as bool? ?? true,
          );
          _selectedAccountId = syncState.accountId;
        } else {
          throw const FormatException('账号数据不是当前多账号格式。');
        }
        final selectedAccountId = json['selectedAccountId'];
        if (selectedAccountId != null && selectedAccountId is! String) {
          throw const FormatException('本机账号选择状态格式无效。');
        }
        if (rawAccounts is List) {
          _selectedAccountId = selectedAccountId as String?;
        }

        if (_selectedAccountId != null &&
            !_accounts.containsKey(_selectedAccountId)) {
          throw const FormatException('本机当前账号不存在。');
        }

        await _restoreSelectedStatus();
        if (migrated &&
            _accounts.values.every(
              (record) => record.syncState.hasCredentials,
            )) {
          await _save();
        }
        notifyListeners();
        return;
      }
    } catch (_) {
      _accounts.clear();
      _selectedAccountId = null;
      needsRecovery = true;
    }

    if (needsRecovery && recoveryLoader != null) {
      try {
        final recovered = await recoveryLoader();
        if (await _recoverLocalAccounts(recovered)) {
          notifyListeners();
          return;
        }
      } catch (_) {
        // If recovery data is unavailable, fall back to the normal entry page.
      }
    }

    status = AccountStatus.unactivated;
    notifyListeners();
  }

  Future<bool> _recoverLocalAccounts(List<AccountSyncState> recovered) async {
    final unique = <String, AccountSyncState>{};
    for (final state in recovered) {
      if (state.accountId.isEmpty || !state.hasCredentials) continue;
      unique.putIfAbsent(state.accountId, () => state);
    }
    if (unique.isEmpty) return false;

    _accounts.clear();
    _selectedAccountId = null;

    for (final state in unique.values) {
      final currentDeviceId = await _readDeviceIdentity(state);
      if (currentDeviceId == null) {
        // Never mint a fresh trusted device identity during passive recovery.
        // Without the local marker, the account must be joined explicitly.
        continue;
      }

      _accounts[state.accountId] = _LocalAccountRecord(
        syncState: state,
        currentDeviceId: currentDeviceId,
        activationSerial: null,
        stayLoggedIn: false,
      );
    }

    if (_accounts.isEmpty) return false;

    if (_accounts.length == 1) {
      _selectedAccountId = _accounts.keys.single;
      final record = _selectedRecord!;
      status = record.syncState.isRevoked(record.currentDeviceId)
          ? AccountStatus.revoked
          : AccountStatus.locked;
    } else {
      status = AccountStatus.unactivated;
    }

    await _save();
    return true;
  }

  Future<void> _restoreSelectedStatus() async {
    final record = _selectedRecord;
    if (record == null || !record.syncState.hasCredentials) {
      status = AccountStatus.unactivated;
      return;
    }

    if (record.syncState.isRevoked(record.currentDeviceId)) {
      status = AccountStatus.revoked;
      return;
    }

    status = record.stayLoggedIn
        ? AccountStatus.unlocked
        : AccountStatus.locked;
    await touchCurrentDevice(notify: false);
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
      throw const FormatException('这个激活码对应的账号已经存在于本机，请直接登录该账号。');
    }

    final now = DateTime.now().toUtc();
    final descriptor = await DeviceDescriptor.current();
    final newDeviceId = _randomId();

    var state = AccountSyncState(
      accountId: license.accountId,
      accountName: trimmedName,
      password: password,
      accountNameUpdatedAt: now,
      passwordUpdatedAt: now,
      devices: const <String, AccountDevice>{},
      revocations: const <String, DeviceRevocation>{},
    );

    final devices = <String, AccountDevice>{...state.devices};
    devices[newDeviceId] = AccountDevice(
      id: newDeviceId,
      name: descriptor.name,
      platform: descriptor.platform,
      firstSeenAt: now,
      lastSeenAt: now,
    );
    state = state.copyWith(devices: devices);

    _accounts[license.accountId] = _LocalAccountRecord(
      syncState: state,
      currentDeviceId: newDeviceId,
      activationSerial: license.serial,
      stayLoggedIn: true,
    );
    _selectedAccountId = license.accountId;
    status = AccountStatus.unlocked;

    await _save();
    notifyListeners();
  }

  Future<void> selectLocalAccount(String accountId) async {
    final record = _accounts[accountId];
    if (record == null) {
      throw const FormatException('这个本机账号已经不存在。');
    }

    _selectedAccountId = accountId;
    _accounts[accountId] = record.copyWith(stayLoggedIn: false);

    if (record.syncState.isRevoked(record.currentDeviceId)) {
      status = AccountStatus.revoked;
    } else {
      status = AccountStatus.locked;
    }

    await _save();
    notifyListeners();
  }

  Future<bool> unlock({
    required String accountName,
    required String password,
  }) async {
    final record = _selectedRecord;
    if (record == null || record.syncState.isRevoked(record.currentDeviceId)) {
      status = record?.syncState.isRevoked(record.currentDeviceId) == true
          ? AccountStatus.revoked
          : AccountStatus.unactivated;
      notifyListeners();
      return false;
    }

    // Constant-time string comparison to prevent timing attacks
    bool constantTimeEquals(String a, String b) {
      if (a.length != b.length) return false;
      var result = 0;
      for (var i = 0; i < a.length; i++) {
        result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
      }
      return result == 0;
    }

    final ok =
        accountName.trim() == record.syncState.accountName &&
        constantTimeEquals(password, record.syncState.password);

    if (ok) {
      _accounts[record.syncState.accountId] = record.copyWith(
        stayLoggedIn: true,
      );
      status = AccountStatus.unlocked;
      await touchCurrentDevice(notify: false);
      notifyListeners();
    }
    return ok;
  }

  Future<void> lock() async {
    final record = _selectedRecord;
    if (record == null) {
      status = AccountStatus.unactivated;
      notifyListeners();
      return;
    }

    _accounts[record.syncState.accountId] = record.copyWith(
      stayLoggedIn: false,
    );

    if (record.syncState.isRevoked(record.currentDeviceId)) {
      status = AccountStatus.revoked;
    } else {
      status = AccountStatus.locked;
    }

    await _save();
    notifyListeners();
  }

  Future<void> returnToAccountChooser() async {
    final record = _selectedRecord;
    if (record != null) {
      _accounts[record.syncState.accountId] = record.copyWith(
        stayLoggedIn: false,
      );
    }
    _selectedAccountId = null;
    status = AccountStatus.unactivated;
    await _save();
    notifyListeners();
  }

  Future<void> touchCurrentDevice({bool notify = true}) async {
    final record = _selectedRecord;
    if (record == null || record.syncState.isRevoked(record.currentDeviceId)) {
      return;
    }

    final current = record.syncState.devices[record.currentDeviceId];
    if (current == null) return;

    final devices = <String, AccountDevice>{...record.syncState.devices};
    devices[record.currentDeviceId] = current.copyWith(
      lastSeenAt: DateTime.now().toUtc(),
    );

    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(devices: devices),
    );

    await _save();
    if (notify) notifyListeners();
  }

  void validateSyncTransportBinding({
    required String appDeviceId,
    required String syncTransportId,
  }) {
    final normalizedAppDeviceId = appDeviceId.trim();
    final normalizedTransportId = syncTransportId.trim();
    if (normalizedAppDeviceId.isEmpty) {
      throw const FormatException('同步设备身份缺失。');
    }
    if (normalizedTransportId.length < 20) {
      throw const FormatException('同步设备 ID 格式无效。');
    }

    final record = _selectedRecord;
    if (record == null) return;

    if (record.syncState.isRevoked(normalizedAppDeviceId)) {
      throw const FormatException('这台设备已经解绑，不能重新加入同步。');
    }

    final current = record.syncState.devices[normalizedAppDeviceId];
    if (current?.syncTransportId != null &&
        current!.syncTransportId != normalizedTransportId) {
      throw const FormatException('这台设备的同步身份与已记录身份不一致。');
    }

    for (final device in record.syncState.devices.values) {
      if (device.id == normalizedAppDeviceId) continue;
      if (device.syncTransportId == normalizedTransportId &&
          !record.syncState.isRevoked(device.id)) {
        throw const FormatException('这个同步身份已经绑定到另一台使用中设备。');
      }
    }
  }

  Future<void> bindSyncTransportId({
    required String appDeviceId,
    required String syncTransportId,
    required String name,
    required String platform,
  }) async {
    final normalizedAppDeviceId = appDeviceId.trim();
    final normalizedTransportId = syncTransportId.trim();
    final normalizedName = name.trim();
    final normalizedPlatform = platform.trim();
    if (normalizedName.isEmpty || normalizedPlatform.isEmpty) {
      throw const FormatException('同步设备信息不完整。');
    }
    validateSyncTransportBinding(
      appDeviceId: normalizedAppDeviceId,
      syncTransportId: normalizedTransportId,
    );

    final record = _selectedRecord;
    if (record == null) return;

    final now = DateTime.now().toUtc();
    final devices = <String, AccountDevice>{...record.syncState.devices};
    final current = devices[normalizedAppDeviceId];

    if (current != null && current.syncTransportId == normalizedTransportId) {
      return;
    }

    devices[normalizedAppDeviceId] = current == null
        ? AccountDevice(
            id: normalizedAppDeviceId,
            name: normalizedName,
            platform: normalizedPlatform,
            firstSeenAt: now,
            lastSeenAt: now,
            syncTransportId: normalizedTransportId,
          )
        : current.copyWith(
            syncTransportId: normalizedTransportId,
            lastSeenAt: now,
          );

    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(devices: devices),
    );

    await _save();
    notifyListeners();
  }

  Future<void> renameDevice(String deviceId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) {
      throw const FormatException('设备名称需要在 1–40 个字符之间。');
    }

    final record = _selectedRecord;
    if (record == null) return;
    if (record.syncState.isRevoked(deviceId)) {
      throw const FormatException('已解绑设备不能修改名称。');
    }

    final current = record.syncState.devices[deviceId];
    if (current == null) {
      throw const FormatException('这台设备已经不存在。');
    }

    final devices = <String, AccountDevice>{...record.syncState.devices};
    devices[deviceId] = current.copyWith(
      name: trimmed,
      nameUpdatedAt: DateTime.now().toUtc(),
    );

    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(devices: devices),
    );

    await _save();
    notifyListeners();
  }

  Future<void> renameCurrentDevice(String name) {
    final id = currentDeviceId;
    if (id == null) return Future<void>.value();
    return renameDevice(id, name);
  }

  Future<void> renameAccount(String name) async {
    final trimmed = name.trim();
    if (trimmed.length < 2 || trimmed.length > 32) {
      throw const FormatException('账号名长度需要在 2–32 个字符之间。');
    }

    final record = _selectedRecord;
    if (record == null) return;

    final now = DateTime.now().toUtc();
    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(
        accountName: trimmed,
        accountNameUpdatedAt: now,
      ),
    );

    await _save();
    notifyListeners();
  }

  Future<void> setAccountAvatarBytes(List<int> bytes) async {
    if (bytes.isEmpty) {
      throw const FormatException('头像图片为空。');
    }
    if (bytes.length > 256 * 1024) {
      throw const FormatException('头像处理后仍超过 256 KB，请换一张图片。');
    }

    final record = _selectedRecord;
    if (record == null || !isUnlocked) {
      throw const FormatException('当前账号未登录，不能修改头像。');
    }

    final now = DateTime.now().toUtc();
    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(
        avatarBase64: base64Encode(bytes),
        avatarUpdatedAt: now,
      ),
    );

    await _save();
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final record = _selectedRecord;
    if (record == null || !isUnlocked) {
      throw const FormatException('当前账号未登录，不能修改密码。');
    }
    if (currentPassword != record.syncState.password) {
      throw const FormatException('当前密码不正确。');
    }
    if (newPassword.length < 6) {
      throw const FormatException('新密码至少需要 6 个字符。');
    }

    final now = DateTime.now().toUtc();
    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(
        password: newPassword,
        passwordUpdatedAt: now,
      ),
    );

    await _save();
    notifyListeners();
  }

  Future<void> revokeDevice(String deviceId) async {
    final record = _selectedRecord;
    if (record == null || !record.syncState.devices.containsKey(deviceId)) {
      return;
    }
    if (deviceId == record.currentDeviceId) {
      throw const FormatException('当前设备不能在这里解绑。');
    }

    final revocations = <String, DeviceRevocation>{
      ...record.syncState.revocations,
    };
    revocations[deviceId] = DeviceRevocation(
      deviceId: deviceId,
      revokedAt: DateTime.now().toUtc(),
    );

    _accounts[record.syncState.accountId] = record.copyWith(
      syncState: record.syncState.copyWith(revocations: revocations),
    );

    await _save();
    notifyListeners();
  }

  Future<void> adoptSyncedAccount(AccountSyncState incoming) async {
    if (!incoming.hasCredentials) {
      throw const FormatException('同步账号缺少登录信息，不能加入。');
    }

    final existing = _accounts[incoming.accountId];
    if (existing != null &&
        !existing.syncState.isRevoked(existing.currentDeviceId)) {
      _accounts[incoming.accountId] = existing.copyWith(
        syncState: existing.syncState.merge(incoming),
        stayLoggedIn: false,
      );
      _selectedAccountId = incoming.accountId;
      status = AccountStatus.locked;
      await _save();
      notifyListeners();
      return;
    }

    final now = DateTime.now().toUtc();
    final descriptor = await DeviceDescriptor.current();
    final rememberedDeviceId =
        existing == null ? await _readDeviceIdentity(incoming) : null;
    final newDeviceId =
        rememberedDeviceId != null && !incoming.isRevoked(rememberedDeviceId)
        ? rememberedDeviceId
        : _randomId();

    // A locally removed account keeps only its device marker so rejoining the
    // same account can reuse the existing app-device identity. A revoked
    // physical device still rejoins under a fresh app-device ID, while its
    // locally known tombstones are still authoritative safety history. Do not
    // replace that history with an older transfer/backup snapshot, otherwise
    // a stale package could resurrect devices that were already unshared.
    final baseState = existing == null
        ? incoming
        : existing.syncState.merge(incoming);
    final devices = <String, AccountDevice>{...baseState.devices};

    devices[newDeviceId] = AccountDevice(
      id: newDeviceId,
      name: descriptor.name,
      platform: descriptor.platform,
      firstSeenAt: now,
      lastSeenAt: now,
    );

    final state = baseState.copyWith(devices: devices);
    _accounts[incoming.accountId] = _LocalAccountRecord(
      syncState: state,
      currentDeviceId: newDeviceId,
      activationSerial: null,
      stayLoggedIn: false,
    );
    _selectedAccountId = incoming.accountId;
    status = AccountStatus.locked;

    await _save();
    notifyListeners();
  }

  Future<void> mergeSyncedState(AccountSyncState incoming) async {
    final record = _selectedRecord;
    if (record == null) return;
    if (record.syncState.accountId != incoming.accountId) {
      throw const FormatException('同步数据属于另一个账号，已拒绝合并。');
    }

    final merged = record.syncState.merge(incoming);
    _accounts[record.syncState.accountId] = record.copyWith(syncState: merged);

    if (merged.isRevoked(record.currentDeviceId)) {
      status = AccountStatus.revoked;
    }

    await _save();
    notifyListeners();
  }

  Future<void> removeLocalAccount({
    required Future<void> Function(String accountId) deleteAccountData,
  }) {
    final id = _selectedAccountId;
    if (id == null) return Future<void>.value();
    return removeLocalAccountById(
      accountId: id,
      deleteAccountData: deleteAccountData,
    );
  }

  Future<void> removeLocalAccountById({
    required String accountId,
    required Future<void> Function(String accountId) deleteAccountData,
  }) async {
    final id = requireValidAccountId(accountId);
    final record = _accounts[id];
    if (record == null) return;

    final retainedDeviceId = record.currentDeviceId;
    await deleteAccountData(id);

    // Keep only the tiny local device marker. If this account is joined again
    // on the same installation, the existing device identity can be reused
    // instead of leaving a duplicate active device on the other peers.
    final marker = await _deviceIdentityFile(id);
    await marker.parent.create(recursive: true);
    await atomicWriteString(marker, retainedDeviceId);

    _accounts.remove(id);
    if (_selectedAccountId == id) {
      _selectedAccountId = null;
      status = AccountStatus.unactivated;
    }
    await _save();
    notifyListeners();
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

    final payload = <String, dynamic>{
      'schemaVersion': 4,
      'selectedAccountId': _selectedAccountId,
      'accounts': [for (final record in _accounts.values) record.toJson()],
    };

    await atomicWriteString(file, jsonEncode(payload));

    for (final record in _accounts.values) {
      final marker = await _deviceIdentityFile(record.syncState.accountId);
      await marker.parent.create(recursive: true);
      await atomicWriteString(marker, record.currentDeviceId);
    }
  }
}

String _randomId() => base64UrlEncode(_randomBytes(12)).replaceAll('=', '');

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
