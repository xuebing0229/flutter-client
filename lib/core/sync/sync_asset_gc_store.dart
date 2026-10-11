import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../storage/atomic_file.dart';
import 'sync_gc_ack_store.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';
import 'sync_record_store.dart';

/// Conservative, P2P-only garbage collection for *previously committed* art.
///
/// Draft imports are cleaned by OrderReferenceImageStore, not here. Every
/// committed binary must be explicitly scheduled when its sync metadata is
/// removed, then retained until every still-bound device has acknowledged
/// precisely the same complete sync-record inventory with the new asset-GC
/// capability. Old/offline devices block collection. No time-based hold.
class SyncAssetGcStore {
  SyncAssetGcStore({
    SyncRecordStore? recordStore,
    SyncGcAckStore? gcAckStore,
    SyncMergeEngine? mergeEngine,
  }) : _recordStore = recordStore ?? SyncRecordStore(),
       _gcAckStore = gcAckStore ?? SyncGcAckStore(recordStore: recordStore),
       _mergeEngine = mergeEngine ?? SyncMergeEngine();

  final SyncRecordStore _recordStore;
  final SyncGcAckStore _gcAckStore;
  final SyncMergeEngine _mergeEngine;
  final Sha256 _sha256 = Sha256();

  static bool isSafeReferencePath(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'assets' ||
        parts[1] != 'order-reference-images' ||
        path.contains('\\')) {
      return false;
    }
    return parts.every((part) =>
        part.isNotEmpty &&
        part != '.' &&
        part != '..' &&
        RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(part));
  }

  /// Extract paths from the saved order/product fields. An invalid metadata
  /// format is not evidence that the corresponding asset is unreferenced.
  static Set<String>? referencePaths(Map<String, dynamic> values) {
    final raw = values['referenceImages'];
    if (raw == null) return <String>{};
    if (raw is! List) return null;
    final paths = <String>{};
    for (final entry in raw) {
      if (entry is! Map) return null;
      final path = entry['relativePath'];
      if (path is! String || !isSafeReferencePath(path)) return null;
      paths.add(path);
    }
    return paths;
  }

  Future<File> _candidateFile(String rootPath, String relativePath) async {
    final hash = await _sha256.hash(utf8.encode(relativePath));
    final filename = base64UrlEncode(hash.bytes).replaceAll('=', '');
    return File(
      '$rootPath${Platform.pathSeparator}gc-asset-candidates'
      '${Platform.pathSeparator}$filename.json',
    );
  }

  /// Add only paths which were actually unlinked from a saved sync entity.
  /// Never register every unreferenced file in a directory; an unfinished
  /// upload may legitimately exist before its first metadata commit.
  Future<void> registerUnlinked({
    required String accountId,
    required Iterable<String> relativePaths,
  }) async {
    final safe = relativePaths.where(isSafeReferencePath).toSet();
    if (safe.isEmpty) return;
    final root = await _recordStore.rootDirectory(accountId);
    for (final path in safe) {
      final candidate = await _candidateFile(root.path, path);
      if (await candidate.exists()) continue;
      await candidate.parent.create(recursive: true);
      await atomicWriteString(
        candidate,
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'relativePath': path,
        }),
      );
    }
  }

  /// Return number of binaries physically deleted. Returns zero on *any*
  /// incomplete device acknowledgement or unresolved reference conflict.
  ///
  /// Only call after publishing this device's acknowledgement of the current
  /// post-reconcile record set; hold the coordinator's serialized sync queue.
  Future<int> collectAcknowledged({
    required String accountId,
    required Set<String> activeDeviceIds,
    required Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  }) async {
    if (activeDeviceIds.isEmpty) return 0;
    final root = await _recordStore.rootDirectory(accountId);
    final directory = Directory('${root.path}/gc-asset-candidates');
    if (!await directory.exists()) return 0;
    // Most users have no pending unlink candidates. Skip all record hashing
    // and device-ACK reads when the candidate directory is empty.
    if (await directory.list(followLinks: false).isEmpty) return 0;

    final referenced = <String>{};
    for (final kind in const [SyncEntityKind.order, SyncEntityKind.product]) {
      for (final record in recordsByKind[kind]?.values ?? <SyncRecord>[]) {
        if (record.conflicts.isNotEmpty) return 0;
        if (record.isDeleted) continue;
        final values = _mergeEngine.materialize(record);
        if (values == null) return 0;
        final paths = referencePaths(values);
        if (paths == null) return 0;
        referenced.addAll(paths);
      }
    }

    // All active devices must be on the *new* asset-GC protocol and must
    // attest to the exact same FULL history. Matching just the owning order
    // would miss an image reused by another product/record on an old peer.
    final acknowledgements = await _gcAckStore.readAll(
      accountId,
      requireAssetGcSupport: true,
      expectedAssetGcPeers: activeDeviceIds,
    );
    if (!activeDeviceIds.every(acknowledgements.containsKey)) return 0;
    final current = await _gcAckStore.signatures(recordsByKind);
    for (final id in activeDeviceIds) {
      final peer = acknowledgements[id]!;
      if (peer.length != current.length) return 0;
      for (final entry in current.entries) {
        if (peer[entry.key] != entry.value) return 0;
      }
    }

    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map || decoded['schemaVersion'] != 1) continue;
        final relativePath = decoded['relativePath'];
        if (relativePath is! String ||
            !isSafeReferencePath(relativePath) ||
            referenced.contains(relativePath)) {
          continue;
        }
        final expected = await _candidateFile(root.path, relativePath);
        if (expected.path != entity.path) continue;

        final segments = relativePath.split('/');
        var currentPath = root.path;
        var unsafe = false;
        // Do not follow any shared-folder symlink, even if a remote client
        // inserts one. In particular never delete outside our account root.
        for (final segment in segments.take(segments.length - 1)) {
          currentPath = '$currentPath${Platform.pathSeparator}$segment';
          if (await FileSystemEntity.type(currentPath, followLinks: false) ==
              FileSystemEntityType.link) {
            unsafe = true;
            break;
          }
        }
        if (unsafe) continue;
        final path = '${root.path}${Platform.pathSeparator}'
            '${segments.join(Platform.pathSeparator)}';
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.directory) {
          continue;
        }
        if (type == FileSystemEntityType.file) {
          await File(path).delete();
          removed++;
        }
        // File may already have been deleted by Syncthing after another
        // device safely collected the same candidate.
        await entity.delete();
      } catch (_) {
        // A locked Windows image, interrupted Syncthing replacement, corrupt
        // marker or full disk must never block ordinary local sync.
      }
    }
    return removed;
  }
}
