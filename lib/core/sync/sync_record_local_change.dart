import 'sync_merge_engine.dart';
import 'sync_models.dart';

SyncRecord? buildLocalSyncRecordChange({
  required String accountId,
  required String deviceId,
  required SyncEntityKind kind,
  required String id,
  required Map<String, dynamic>? before,
  required Map<String, dynamic>? after,
  required SyncRecord? baselineRecord,
  required SyncRecord? currentRecord,
  required SyncMergeEngine mergeEngine,
}) {
  if (syncJsonEquals(before, after)) return null;

  SyncRecord localRecord;
  if (after == null) {
    final baseRecord = baselineRecord ?? currentRecord;
    if (baseRecord == null) {
      if (before == null) return null;
      localRecord = SyncRecord.bootstrap(
        kind: kind,
        id: id,
        values: before,
        deviceId: deviceId,
      ).copyWith(accountId: accountId);
    } else {
      localRecord = baseRecord;
    }
    localRecord = mergeEngine.markDeleted(
      localRecord,
      deviceId: deviceId,
    );
  } else if (baselineRecord != null) {
    localRecord = mergeEngine.applyLocalSnapshot(
      record: baselineRecord,
      previousValues: before ?? after,
      nextValues: after,
      deviceId: deviceId,
    );
  } else if (currentRecord == null) {
    localRecord = SyncRecord.bootstrap(
      kind: kind,
      id: id,
      values: after,
      deviceId: deviceId,
    ).copyWith(accountId: accountId);
  } else {
    localRecord = mergeEngine.applyLocalSnapshot(
      record: currentRecord,
      previousValues: before ?? after,
      nextValues: after,
      deviceId: deviceId,
    );
  }

  final merged = currentRecord == null
      ? localRecord
      : mergeEngine.merge(currentRecord, localRecord);
  return merged.copyWith(accountId: accountId);
}
