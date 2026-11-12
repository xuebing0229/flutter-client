import 'account_local_state.dart';
import 'account_models.dart';

AccountStatus accountStatusForRecord(LocalAccountRecord? record) {
  if (record == null || !record.syncState.hasCredentials) {
    return AccountStatus.unactivated;
  }
  if (record.syncState.isRevoked(record.currentDeviceId)) {
    return AccountStatus.revoked;
  }
  return record.stayLoggedIn ? AccountStatus.unlocked : AccountStatus.locked;
}

bool accountCredentialsMatch({
  required LocalAccountRecord record,
  required String accountName,
  required String password,
}) {
  return accountName.trim() == record.syncState.accountName &&
      constantTimeStringEquals(password, record.syncState.password);
}

bool constantTimeStringEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var index = 0; index < a.length; index++) {
    result |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
  }
  return result == 0;
}

AccountSyncState createActivatedAccountState({
  required String accountId,
  required String accountName,
  required String password,
  required String deviceId,
  required String deviceName,
  required String platform,
  String? installationId,
  DateTime? now,
}) {
  final timestamp = (now ?? DateTime.now()).toUtc();
  return AccountSyncState(
    accountId: accountId,
    accountName: accountName.trim(),
    password: password,
    accountNameUpdatedAt: timestamp,
    passwordUpdatedAt: timestamp,
    devices: <String, AccountDevice>{
      deviceId: AccountDevice(
        id: deviceId,
        name: deviceName,
        platform: platform,
        firstSeenAt: timestamp,
        lastSeenAt: timestamp,
        installationId: installationId,
      ),
    },
    revocations: const <String, DeviceRevocation>{},
  );
}

AccountSyncState touchAccountDeviceState(
  AccountSyncState state, {
  required String deviceId,
  required bool createIfMissing,
  String? defaultName,
  String? platform,
  String? installationId,
  DateTime? now,
}) {
  if (state.isRevoked(deviceId)) return state;
  final current = state.devices[deviceId];
  if (current == null && !createIfMissing) return state;
  final timestamp = (now ?? DateTime.now()).toUtc();
  final devices = <String, AccountDevice>{...state.devices};
  devices[deviceId] = current == null
      ? AccountDevice(
          id: deviceId,
          name: defaultName ?? '新设备',
          platform: platform ?? 'unknown',
          firstSeenAt: timestamp,
          lastSeenAt: timestamp,
          installationId: installationId,
        )
      : current.copyWith(
          platform: platform ?? current.platform,
          lastSeenAt: timestamp,
          installationId: installationId ?? current.installationId,
        );
  return state.copyWith(devices: devices);
}

List<LocalAccountSummary> sortedLocalAccountSummaries(
  Map<String, LocalAccountRecord> accounts,
) {
  final items = <LocalAccountSummary>[
    for (final entry in accounts.entries)
      LocalAccountSummary(
        accountId: entry.key,
        accountName: entry.value.syncState.accountName,
      ),
  ];
  items.sort(
    (a, b) => a.accountName.toLowerCase().compareTo(b.accountName.toLowerCase()),
  );
  return List<LocalAccountSummary>.unmodifiable(items);
}

List<AccountDevice> sortedActiveAccountDevices(AccountSyncState? state) {
  if (state == null) return const <AccountDevice>[];
  final devices = state.activeDevices.toList()
    ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
  return List<AccountDevice>.unmodifiable(devices);
}
