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
  }) async {
    final records = await signatures(recordsByKind);
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'deviceId': deviceId,
      // Old clients omit this capability. A file GC must never infer support
      // from a normal record-history acknowledgement.
      'assetGcVersion': 1,
      'records': records,
    };

    final file = await _file(accountId, deviceId);
    final encoded = stableJsonSignature(payload);
    if (await file.exists()) {
      try {
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
  }) async {
    final directory = await _directory(accountId);
    final result = <String, Map<String, String>>{};
    final assetGcSeen = <String>{};
    final assetGcBlocked = <String>{};

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (requireAssetGcSupport &&
          entity.path.contains('.sync-conflict-')) {
        // An unresolvable concurrent rewrite of acknowledgement files can
        // make a stale peer appear current. Fail closed until Syncthing has
        // converged, rather than physically deleting shared artwork.
        return const <String, Map<String, String>>{};
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final deviceId = decoded['deviceId'];
        if (requireAssetGcSupport &&
            deviceId is String &&
            deviceId.isNotEmpty) {
          if (!assetGcSeen.add(deviceId) ||
              decoded['schemaVersion'] != 1 ||
              decoded['assetGcVersion'] != 1) {
            assetGcBlocked.add(deviceId);
            result.remove(deviceId);
          }
          if (assetGcBlocked.contains(deviceId)) continue;
        }
        if (decoded['schemaVersion'] != 1) continue;
        if (requireAssetGcSupport && decoded['assetGcVersion'] != 1) {
          // A legacy installation knows record-history GC, but not this
          // destructive binary-asset protocol. Keep its art until upgraded.
          continue;
        }
        final rawRecords = decoded['records'];
        if (deviceId is! String || deviceId.isEmpty || rawRecords is! Map) {
          continue;
        }

        final records = <String, String>{};
        var valid = true;
        for (final entry in rawRecords.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is! String || value is! String) {
            valid = false;
            break;
          }
          records[key] = value;
        }
        if (valid) result[deviceId] = records;
      } catch (_) {
        // Syncthing can expose a replacement between rename steps.
      }
    }

    return result;
  }
}
