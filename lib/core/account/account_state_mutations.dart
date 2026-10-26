import 'account_models.dart';

AccountSyncState renameAccountState(AccountSyncState state, String name) {
  final trimmed = name.trim();
  if (trimmed.length < 2 || trimmed.length > 32) {
    throw const FormatException('账号名长度需要在 2–32 个字符之间。');
  }
  return state.copyWith(
    accountName: trimmed,
    accountNameUpdatedAt: DateTime.now().toUtc(),
  );
}

AccountSyncState changeAccountPasswordState(
  AccountSyncState state, {
  required String currentPassword,
  required String newPassword,
}) {
  if (currentPassword != state.password) {
    throw const FormatException('当前密码不正确。');
  }
  if (newPassword.length < 6) {
    throw const FormatException('新密码至少需要 6 个字符。');
  }
  return state.copyWith(
    password: newPassword,
    passwordUpdatedAt: DateTime.now().toUtc(),
  );
}

AccountSyncState renameAccountDeviceState(
  AccountSyncState state, {
  required String deviceId,
  required String name,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 40) {
    throw const FormatException('设备名称需要在 1–40 个字符之间。');
  }
  if (state.isRevoked(deviceId)) {
    throw const FormatException('已解绑设备不能修改名称。');
  }
  final current = state.devices[deviceId];
  if (current == null) {
    throw const FormatException('这台设备已经不存在。');
  }
  final devices = <String, AccountDevice>{...state.devices};
  devices[deviceId] = current.copyWith(
    name: trimmed,
    nameUpdatedAt: DateTime.now().toUtc(),
  );
  return state.copyWith(devices: devices);
}

AccountSyncState revokeAccountDeviceState(
  AccountSyncState state, {
  required String currentDeviceId,
  required String deviceId,
}) {
  if (!state.devices.containsKey(deviceId)) return state;
  if (deviceId == currentDeviceId) {
    throw const FormatException('当前设备不能在这里解绑。');
  }
  final revocations = <String, DeviceRevocation>{...state.revocations};
  revocations[deviceId] = DeviceRevocation(
    deviceId: deviceId,
    revokedAt: DateTime.now().toUtc(),
  );
  return state.copyWith(revocations: revocations);
}
