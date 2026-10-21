import 'dart:convert';

import '../sync/sync_merge_engine.dart';
import '../sync/sync_models.dart';
import '../sync/sync_record_store.dart';

/// Native-side bridge between the app's canonical CRDT record graph and the
/// Cloudflare relay used by the PWA.
///
/// This bridge deliberately has no Syncthing dependency. Android/Windows keep
/// their existing Syncthing transport untouched; Cloudflare only reads and
/// merges app-level sync records.
class NativeCloudflareRecordBridge {
  NativeCloudflareRecordBridge({
    required this.accountId,
    SyncRecordStore? recordStore,
    SyncMergeEngine? mergeEngine,
  })  : _recordStore = recordStore ?? SyncRecordStore(),
        _mergeEngine = mergeEngine ?? SyncMergeEngine();

  final String accountId;
  final SyncRecordStore _recordStore;
  final SyncMergeEngine _mergeEngine;

  Future<List<Map<String, dynamic>>> exportRecords() {
    return _recordStore.exportPortableRecords(accountId: accountId);
  }

  Future<void> mergeRecords(List<Map<String, dynamic>> incoming) async {
    if (incoming.isEmpty) return;

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
  }
}
