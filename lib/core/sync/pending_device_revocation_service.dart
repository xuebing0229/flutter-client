import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../account/account_models.dart';
import '../account/account_store.dart';
import '../storage/app_data_persistence.dart';
import '../storage/atomic_file.dart';
import 'account_sync_record_store.dart';
import 'embedded_syncthing_bridge.dart';

class PendingDeviceRevocationService {
  PendingDeviceRevocationService({
    required AccountSyncRecordStore accountSyncStore,
    required AppDataPersistence persistence,
    EmbeddedSyncthingBridge bridge = const EmbeddedSyncthingBridge(),
  }) : _accountSyncStore = accountSyncStore,
       _persistence = persistence,
       _bridge = bridge;

  static const String _directoryName = 'pending-device-revocations-v1';

  final AccountSyncRecordStore _accountSyncStore;
  final AppDataPersistence _persistence;
  final EmbeddedSyncthingBridge _bridge;

  bool _flushing = false;

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}$_directoryName',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String accountId, String deviceId) async {
    requireValidAccountId(accountId);
    if (deviceId.trim().isEmpty) {
      throw const FormatException('待发送解绑记录缺少设备身份。');
    }
    final directory = await _directory();
    String safe(String value) => base64Url
        .encode(utf8.encode(value))
        .replaceAll('=', '');
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '${safe(accountId)}-${safe(deviceId)}.json',
    );
  }

  /// Stages the current installation's final revocation using the same
  /// tombstone + acknowledgement protocol as remote device unbinding.
  ///
  /// The caller may remove the visible local account immediately afterwards.
  /// The sync workspace itself must be retained while this method returns true
  /// so the queued tombstone can be delivered silently on a later app launch.
  Future<bool> stageLocalRemoval(LocalDeviceRemovalSnapshot snapshot) async {
    final state = snapshot.state;
    final deviceId = snapshot.deviceId;
    final accountId = state.accountId;

    if (state.isRevoked(deviceId)) {
      return false;
    }

    final requiredPeers = <_PendingPeer>[
      for (final device in state.activeDevices)
        if (device.id != deviceId)
          _PendingPeer(
            appDeviceId: device.id,
            name: device.name,
            transportId: device.syncTransportId?.trim(),
          ),
    ];

    // Nobody else can ever need this tombstone.
    if (requiredPeers.isEmpty) {
      return false;
    }

    final revokedAt = DateTime.now().toUtc();
    final revokedState = state.copyWith(
      revocations: <String, DeviceRevocation>{
        ...state.revocations,
        deviceId: DeviceRevocation(
          deviceId: deviceId,
          revokedAt: revokedAt,
        ),
      },
    );

    // Write the existing revocation protocol first. If any of these durable
    // writes fail, the visible account has not been removed yet, so the user
    // can safely retry instead of losing the only copy of the tombstone.
    await _accountSyncStore.writeSelfRevocation(
      accountId: accountId,
      deviceId: deviceId,
      state: revokedState,
    );
    await _accountSyncStore.writeRevocationAck(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: revokedAt,
    );

    final pending = _PendingRevocation(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: revokedAt,
      peers: requiredPeers,
      deliveredAppDeviceIds: const <String>{},
    );
    await _writePending(pending);
    return true;
  }

  Future<void> flushPending({
    required bool Function(String accountId) hasLocalAccount,
  }) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final directory = await _directory();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final pending = await _readPending(entity);
          if (pending == null) continue;
          final delivered = await _tryDeliver(pending, entity);
          if (!delivered) continue;

          // If the same account was rejoined while its old-device revocation
          // was pending, keep the live workspace. Only the old outbox entry is
          // finished in that case.
          if (!hasLocalAccount(pending.accountId)) {
            try {
              await _bridge.removeAccountFolder(accountId: pending.accountId);
            } catch (_) {}
            try {
              await _persistence.deletePreservedSyncWorkspace(
                pending.accountId,
              );
            } catch (_) {}
          }

          try {
            if (await entity.exists()) await entity.delete();
          } catch (_) {
            // A later pass can retry harmlessly.
          }
        } catch (_) {
          // Pending revocation delivery is intentionally silent. Keep the
          // durable outbox entry and retry while the app remains open or the
          // next time it launches.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _tryDeliver(
    _PendingRevocation pending,
    File sourceFile,
  ) async {
    final mutablePeers = <_PendingPeer>[...pending.peers];

    // Refresh transport bindings from the preserved workspace. This lets an
    // older pending entry learn a peer transport ID after another peer brings
    // newer account metadata into the folder.
    try {
      final merged = await _accountSyncStore.readMerged(
        accountId: pending.accountId,
      );
      if (merged != null) {
        for (var index = 0; index < mutablePeers.length; index++) {
          final peer = mutablePeers[index];
          final refreshed = merged.devices[peer.appDeviceId];
          if (refreshed == null || merged.isRevoked(peer.appDeviceId)) {
            continue;
          }
          final transportId = refreshed.syncTransportId?.trim();
          if ((peer.transportId == null || peer.transportId!.isEmpty) &&
              transportId != null &&
              transportId.length >= 20) {
            mutablePeers[index] = peer.copyWith(
              name: refreshed.name,
              transportId: transportId,
            );
          }
        }
      }
    } catch (_) {}

    final peersWithTransport = mutablePeers
        .where(
          (peer) =>
              peer.transportId != null && peer.transportId!.trim().length >= 20,
        )
        .toList(growable: false);
    if (peersWithTransport.isEmpty) {
      final refreshed = pending.copyWith(peers: mutablePeers);
      if (!_samePending(pending, refreshed)) {
        await _writePending(refreshed, file: sourceFile);
      }
      return false;
    }

    final syncRoot = await _accountSyncStore.recordStore.rootPath(
      pending.accountId,
    );
    final prepared = await _bridge.prepare(
      accountId: pending.accountId,
      folderPath: syncRoot,
      force: true,
    );
    if (!prepared) return false;

    for (final peer in peersWithTransport) {
      try {
        await _bridge.pairDevice(
          accountId: pending.accountId,
          deviceId: peer.transportId!,
          name: peer.name,
        );
      } catch (_) {}
    }

    try {
      await _bridge.setAccountFolderPaused(
        accountId: pending.accountId,
        paused: false,
      );
    } catch (_) {}
    try {
      await _bridge.requestScan(accountId: pending.accountId);
    } catch (_) {}

    // A short bounded wait makes one foreground pass useful without blocking
    // the UI. The app-level timer will keep retrying silently afterwards.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final status = await _bridge.status(accountId: pending.accountId);

    final delivered = <String>{...pending.deliveredAppDeviceIds};
    final connected = status.connectedDeviceIds.toSet();
    final worstCompletion =
        (status.syncProgress?['completion'] as num?)?.toDouble() ?? 0.0;

    // status.syncProgress is the lowest completion across this folder's local
    // and connected remote candidates. If that floor is 100%, every connected
    // valid peer has the tombstone and ACK currently present in the folder.
    for (final peer in mutablePeers) {
      final transportId = peer.transportId;
      if (transportId == null || !connected.contains(transportId)) continue;
      final remoteState = status.remoteFolderStates[transportId];

      // A peer only reports notSharing after it has stopped sharing this
      // account folder. Under the existing revocation protocol that happens
      // after it has observed our tombstone and matching ACK, so it is also a
      // positive delivery signal even if we missed the brief 100% window.
      if (remoteState == 'notSharing') {
        delivered.add(peer.appDeviceId);
        continue;
      }

      if (worstCompletion >= 99.99 &&
          (remoteState == null || remoteState == 'valid')) {
        delivered.add(peer.appDeviceId);
      }
    }

    // Peers that are themselves revoked no longer need to acknowledge this
    // device's removal. Their own tombstone already excludes them from the
    // active account membership set.
    try {
      final merged = await _accountSyncStore.readMerged(
        accountId: pending.accountId,
      );
      if (merged != null) {
        for (final peer in mutablePeers) {
          if (merged.isRevoked(peer.appDeviceId)) {
            delivered.add(peer.appDeviceId);
          }
        }
      }
    } catch (_) {}

    final refreshed = pending.copyWith(
      peers: mutablePeers,
      deliveredAppDeviceIds: delivered,
    );
    if (!_samePending(pending, refreshed)) {
      await _writePending(refreshed, file: sourceFile);
    }

    return refreshed.peers.every(
      (peer) => delivered.contains(peer.appDeviceId),
    );
  }

  Future<_PendingRevocation?> _readPending(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return _PendingRevocation.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePending(
    _PendingRevocation pending, {
    File? file,
  }) async {
    final target = file ?? await _file(pending.accountId, pending.deviceId);
    await target.parent.create(recursive: true);
    await atomicWriteString(target, jsonEncode(pending.toJson()));
  }
}

class _PendingRevocation {
  const _PendingRevocation({
    required this.accountId,
    required this.deviceId,
    required this.revokedAt,
    required this.peers,
    required this.deliveredAppDeviceIds,
  });

  final String accountId;
  final String deviceId;
  final DateTime revokedAt;
  final List<_PendingPeer> peers;
  final Set<String> deliveredAppDeviceIds;

  _PendingRevocation copyWith({
    List<_PendingPeer>? peers,
    Set<String>? deliveredAppDeviceIds,
  }) {
    return _PendingRevocation(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: revokedAt,
      peers: peers ?? this.peers,
      deliveredAppDeviceIds:
          deliveredAppDeviceIds ?? this.deliveredAppDeviceIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'accountId': accountId,
    'deviceId': deviceId,
    'revokedAt': revokedAt.toUtc().toIso8601String(),
    'peers': <Map<String, dynamic>>[
      for (final peer in peers) peer.toJson(),
    ],
    'deliveredAppDeviceIds': deliveredAppDeviceIds.toList()..sort(),
  };

  factory _PendingRevocation.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('待发送解绑记录版本无效。');
    }
    final accountId = json['accountId'];
    final deviceId = json['deviceId'];
    final revokedAt = json['revokedAt'];
    final rawPeers = json['peers'];
    final rawDelivered = json['deliveredAppDeviceIds'];
    if (accountId is! String ||
        deviceId is! String ||
        revokedAt is! String ||
        rawPeers is! List ||
        rawDelivered is! List) {
      throw const FormatException('待发送解绑记录格式无效。');
    }
    requireValidAccountId(accountId);
    final parsedRevokedAt = DateTime.tryParse(revokedAt);
    if (parsedRevokedAt == null) {
      throw const FormatException('待发送解绑记录时间无效。');
    }
    return _PendingRevocation(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: parsedRevokedAt.toUtc(),
      peers: <_PendingPeer>[
        for (final item in rawPeers)
          if (item is Map)
            _PendingPeer.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
      ],
      deliveredAppDeviceIds: <String>{
        for (final item in rawDelivered)
          if (item is String && item.isNotEmpty) item,
      },
    );
  }
}

class _PendingPeer {
  const _PendingPeer({
    required this.appDeviceId,
    required this.name,
    required this.transportId,
  });

  final String appDeviceId;
  final String name;
  final String? transportId;

  _PendingPeer copyWith({
    String? name,
    String? transportId,
  }) {
    return _PendingPeer(
      appDeviceId: appDeviceId,
      name: name ?? this.name,
      transportId: transportId ?? this.transportId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'appDeviceId': appDeviceId,
    'name': name,
    if (transportId != null && transportId!.isNotEmpty)
      'transportId': transportId,
  };

  factory _PendingPeer.fromJson(Map<String, dynamic> json) {
    final appDeviceId = json['appDeviceId'];
    final name = json['name'];
    final transportId = json['transportId'];
    if (appDeviceId is! String ||
        appDeviceId.isEmpty ||
        name is! String ||
        name.isEmpty ||
        (transportId != null && transportId is! String)) {
      throw const FormatException('待发送解绑设备信息无效。');
    }
    return _PendingPeer(
      appDeviceId: appDeviceId,
      name: name,
      transportId: transportId is String ? transportId.trim() : null,
    );
  }
}

bool _samePending(
  _PendingRevocation left,
  _PendingRevocation right,
) {
  if (left.peers.length != right.peers.length ||
      left.deliveredAppDeviceIds.length !=
          right.deliveredAppDeviceIds.length) {
    return false;
  }
  for (var index = 0; index < left.peers.length; index++) {
    final a = left.peers[index];
    final b = right.peers[index];
    if (a.appDeviceId != b.appDeviceId ||
        a.name != b.name ||
        a.transportId != b.transportId) {
      return false;
    }
  }
  return left.deliveredAppDeviceIds.containsAll(
    right.deliveredAppDeviceIds,
  );
}
