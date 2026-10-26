import 'dart:convert';

import '../sync/sync_merge_engine.dart';
import '../sync/sync_models.dart';
import '../sync/sync_record_store.dart';

typedef FlushNativeWorkspace = Future<void> Function();

/// Native-side bridge between the app's canonical CRDT record graph and the
/// Cloudflare relay used by the PWA.
///
/// This class deliberately does not know about Syncthing, its process, pairing,
/// transport IDs, or scan API. Android/Windows keep their existing native
/// transport untouched; the relay only reads and merges the same app-level
/// records that the workspace already owns.
class NativeCloudflareRecordBridge {
  NativeCloudflareRecordBridge({
    required this.accountId,
    required this.flushNativeWorkspace,
    SyncRecordStore? recordStore,
    SyncMergeEngine? mergeEngine,
  })  : _recordStore = recordStore ?? SyncRecordStore(),
        _mergeEngine = mergeEngine ?? SyncMergeEngine();

  final String accountId;
  final FlushNativeWorkspace flushNativeWorkspace;
  final SyncRecordStore _recordStore;
  final SyncMergeEngine _mergeEngine;

  Future<List<Map<String, dynamic>>> exportRecords() async {
    // Commit pending UI edits into the canonical record graph before taking a
    // Cloudflare snapshot. No transport operation is performed here.
    await flushNativeWorkspace();
    return _recordStore.exportPortableRecords(accountId: accountId);
  }

  Future<void> mergeRecords(List<Map<String, dynamic>> incoming) async {
    if (incoming.isEmpty) return;

    // Make local edits durable first so every incoming record merges against
    // the newest native state rather than an older on-disk snapshot.
    await flushNativeWorkspace();

    for (final raw in incoming) {
      final decoded = SyncRecord.decode(jsonEncode(raw));
      if (decoded.accountId != null && decoded.accountId != accountId) {
        throw const FormatException('同步记录属于另一个账号');
      }
      if (decoded.fields['id']?.value != decoded.id) {
        throw const FormatException('同步记录身份不一致');
      }

      final bound = decoded.copyWith(accountId: accountId);
      final local = await _recordStore.readMergedRecord(
        accountId: accountId,
        kind: bound.kind,
        recordId: bound.id,
      );
      final merged = local == null ? bound : _mergeEngine.merge(local, bound);
      await _recordStore.write(accountId: accountId, record: merged);
    }

    // The existing native workspace watcher will observe these canonical
    // records on its normal poll cycle. Keeping that hand-off asynchronous is
    // intentional: Cloudflare never invokes or configures the native transport.
  }
}
