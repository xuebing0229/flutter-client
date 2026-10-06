import '../account/account_models.dart';

const int currentSyncProtocolVersion = 1;
const int minimumCompatibleSyncProtocolVersion = 1;

enum SyncVersionStatus {
  differentBuild,
  legacyUnknown,
  incompatible,
}

class SyncDeviceVersionNotice {
  const SyncDeviceVersionNotice({
    required this.device,
    required this.status,
    required this.localBuild,
  });

  final AccountDevice device;
  final SyncVersionStatus status;
  final int? localBuild;

  String get signature =>
      '${device.id}|${device.appBuild ?? 'unknown'}|'
      '${device.syncProtocolVersion ?? 'unknown'}|'
      '${device.minSyncProtocolVersion ?? 'unknown'}|${status.name}';
}

List<SyncDeviceVersionNotice> syncDeviceVersionNotices({
  required AccountSyncState? state,
  required String? currentDeviceId,
}) {
  if (state == null || currentDeviceId == null) {
    return const <SyncDeviceVersionNotice>[];
  }

  final local = state.devices[currentDeviceId];
  if (local == null) return const <SyncDeviceVersionNotice>[];

  final notices = <SyncDeviceVersionNotice>[];
  for (final remote in state.activeDevices) {
    if (remote.id == currentDeviceId) continue;

    final localProtocol = local.syncProtocolVersion;
    final localMinimum = local.minSyncProtocolVersion;
    final remoteProtocol = remote.syncProtocolVersion;
    final remoteMinimum = remote.minSyncProtocolVersion;

    if (localProtocol == null ||
        localMinimum == null ||
        remoteProtocol == null ||
        remoteMinimum == null) {
      notices.add(
        SyncDeviceVersionNotice(
          device: remote,
          status: SyncVersionStatus.legacyUnknown,
          localBuild: local.appBuild,
        ),
      );
      continue;
    }

    final compatible =
        localProtocol >= remoteMinimum && remoteProtocol >= localMinimum;
    if (!compatible) {
      notices.add(
        SyncDeviceVersionNotice(
          device: remote,
          status: SyncVersionStatus.incompatible,
          localBuild: local.appBuild,
        ),
      );
      continue;
    }

    if (local.appBuild != null &&
        remote.appBuild != null &&
        local.appBuild != remote.appBuild) {
      notices.add(
        SyncDeviceVersionNotice(
          device: remote,
          status: SyncVersionStatus.differentBuild,
          localBuild: local.appBuild,
        ),
      );
    }
  }

  notices.sort((a, b) {
    final severity = <SyncVersionStatus, int>{
      SyncVersionStatus.incompatible: 0,
      SyncVersionStatus.legacyUnknown: 1,
      SyncVersionStatus.differentBuild: 2,
    };
    final bySeverity =
        severity[a.status]!.compareTo(severity[b.status]!);
    if (bySeverity != 0) return bySeverity;
    return a.device.name.compareTo(b.device.name);
  });
  return notices;
}
