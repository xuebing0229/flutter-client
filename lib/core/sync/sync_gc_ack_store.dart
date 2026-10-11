import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../storage/atomic_file.dart';
import 'sync_models.dart';
import 'sync_record_store.dart';

class SyncGcAckStore {
  SyncGcAckStore({SyncRecordStore? recordStore})
      : _recordStore = recordStore ?? SyncRecordStore();

  final SyncRecordStore _recordStore;
  final Sha256 _sha256 = Sha256();

  Future<Directory> _directory(String accountId) async {
    final root = await _recordStore.rootDirectory(accountId);
    final directory = Directory('${root.path}/gc-acks');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String accountId, String deviceId) async {
    final directory = await _directory(accountId);
    final encoded = base64Url
        .encode(utf8.encode(deviceId))
        .replaceAll('=', '');
    return File('${directory.path}/$encoded.json');
  }

  String recordKey(SyncRecord record) {
    final encoded = base64Url
        .encode(utf8.encode(record.id))
        .replaceAll('=', '');
    return '${record.kind.name}:$encoded';
  }

  Future<String> signature(SyncRecord record) async {
    final json = Map<String, dynamic>.from(record.toJson())
      ..remove('accountId');

    // Map order is normalized by stableJsonSignature, but operations and
    // conflicts are serialized as lists. Sort them by their deterministic IDs
    // so two devices that merged the same record in a different order still
    // acknowledge the same state.
    for (final key in const <String>['operations', 'conflicts']) {
      final raw = json[key];
      if (raw is! List) continue;
      final sorted = <dynamic>[...raw]
        ..sort((left, right) {
          final leftId = left is Map ? left['id']?.toString() ?? '' : '';
          final rightId = right is Map ? right['id']?.toString() ?? '' : '';
          return leftId.compareTo(rightId);
        });
      json[key] = sorted;
    }

    final bytes = utf8.encode(stableJsonSignature(json));
    final hash = await _sha256.hash(bytes);
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  Future<Map<String, String>> signatures(
    Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  ) async {
    final result = <String, String>{};
    for (final records in recordsByKind.values) {
      for (final record in records.values) {
        result[recordKey(record)] = await signature(record);
      }
    }
    return result;
  }

  Future<void> writeSnapshot({
    required String accountId,
    required String deviceId,
    required Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
    Set<String>? assetGcPeers,
  }) async {
    final records = await signatures(recordsByKind);
    final peers = assetGcPeers?.toList()?..sort();
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'deviceId': deviceId,
      // Old clients omit this capability. A file GC must never infer support
      // from a normal record-history acknowledgement.
      if (peers != null) 'assetGcVersion': 1,
      // Every peer must agree on the complete bound-device membership, not
      // just the entity records. A peer freshly paired elsewhere could still
      // have a valid reference that hasn't reached this device's account.
      if (peers != null) 'assetGcPeers': peers,
      'records': records,
    };

    final file = await _file(accountId, deviceId);
    final encoded = stableJsonSignature(payload);
    if (await file.exists()) {
      try {
        // No heartbeat and no redundant Syncthing writes: unchanged data
        // already proves that this device has observed the same state.
        if (await file.readAsString() == encoded) return;
      } catch (_) {}
    }
    await atomicWriteString(file, encoded);
  }

  Future<void> pruneDevices({
    required String accountId,
    required Set<String> activeDeviceIds,
  }) async {
    final directory = await _directory(accountId);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        final deviceId = decoded is Map ? decoded['deviceId'] : null;
        if (deviceId is String && !activeDeviceIds.contains(deviceId)) {
          await entity.delete();
        }
      } catch (_) {
        // Leave unreadable/in-flight files for the next pass.
      }
    }
  }

  Future<Map<String, Map<String, String>>> readAll(
    String accountId, {
    bool requireAssetGcSupport = false,
    Set<String>? expectedAssetGcPeers,
  }) async {
    if (requireAssetGcSupport && expectedAssetGcPeers == null) {
      // Never authorize physical deletion without a device-membership list.
      return const <String, Map<String, String>>{};
    }
    final requiredPeers = expectedAssetGcPeers?.toList()?..sort();
    final directory = await _directory(accountId);
    final result = <String, Map<String, String>>{};
    final seenPeerIds = <String>{};

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (requireAssetGcSupport && entity.path.contains('.sync-conflict-')) {
        // Conflicted confirmations are not unanimous approval.
        return const <String, Map<String, String>>{};
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map || decoded['schemaVersion'] != 1) continue;
        final deviceId = decoded['deviceId'];
        final rawRecords = decoded['records'];
        if (deviceId is! String || deviceId.isEmpty || rawRecords is! Map) {
          continue;
        }
        if (requireAssetGcSupport &&
            expectedAssetGcPeers!.contains(deviceId)) {
          // In strict mode a duplicate, old-protocol, or mismatched
          // acknowledgement is enough to block physical deletion.
          if (!seenPeerIds.add(deviceId) ||
              decoded['assetGcVersion'] != 1 ||
              !syncJsonEquals(decoded['assetGcPeers'], requiredPeers)) {
            return const <String, Map<String, String>>{};
          }
        }

        final records = <String, String>{};
        for (final entry in rawRecords.entries) {
          if (entry.key is! String || entry.value is! String) {
            records.clear();
            break;
          }
          records[entry.key as String] = entry.value as String;
        }
        if (records.isEmpty && rawRecords.isNotEmpty) {
          if (requireAssetGcSupport &&
              expectedAssetGcPeers!.contains(deviceId)) {
            return const <String, Map<String, String>>{};
          }
          continue;
        }
        result[deviceId] = records;
      } catch (_) {
        // In-progress Syncthing file changes may be retried at next scan.
        // Missing a bound-device confirmation always prevents deletion.
      }
    }

    return result;
  }
}
