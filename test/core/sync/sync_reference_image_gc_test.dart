import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_app/core/sync/sync_reference_image_gc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> image(String id) => <String, dynamic>{
        'id': id,
        'fileName': '$id.png',
        'relativePath': 'assets/order-reference-images/order/$id.png',
        'addedAt': '2026-10-11T00:00:00.000Z',
        'sizeBytes': 123,
      };

  Map<SyncEntityKind, Map<String, SyncRecord>> records(SyncRecord record) =>
      <SyncEntityKind, Map<String, SyncRecord>>{
        for (final kind in SyncEntityKind.values) kind: <String, SyncRecord>{},
      }..[record.kind]![record.id] = record;

  test('acknowledged removal becomes an orphan candidate', () {
    final engine = SyncMergeEngine();
    final baseValues = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[image('a')],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: baseValues,
      deviceId: 'phone',
    );
    final removed = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{
        ...baseValues,
        'referenceImages': <dynamic>[],
      },
      deviceId: 'phone',
    );

    final protected = syncGcProtectedReferencePaths(
      recordsByKind: records(removed),
      mergeEngine: engine,
    );
    final orphaned = syncGcOrphanReferenceImages(
      record: removed,
      protectedPaths: protected,
    );

    expect(protected, isEmpty);
    expect(orphaned.map((item) => item.id), <String>['a']);
  });

  test('compaction keeps removed image metadata for second-phase cleanup', () {
    final engine = SyncMergeEngine();
    final baseValues = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[image('a')],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: baseValues,
      deviceId: 'phone',
    );
    final removed = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{
        ...baseValues,
        'referenceImages': <dynamic>[],
      },
      deviceId: 'phone',
    );

    final compacted = engine.compactAcknowledgedOperations(
      removed,
      deviceId: 'phone',
    );
    final protected = syncGcProtectedReferencePaths(
      recordsByKind: records(compacted),
      mergeEngine: engine,
    );
    final orphaned = syncGcOrphanReferenceImages(
      record: compacted,
      protectedPaths: protected,
    );

    expect(
      compacted.operations.values.every((operation) => operation.compacted),
      isTrue,
    );
    expect(protected, isEmpty);
    expect(orphaned.map((item) => item.id), <String>['a']);
  });

  test('concurrent addition stays protected while removed image can be reclaimed', () {
    final engine = SyncMergeEngine();
    final baseValues = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[image('a')],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: baseValues,
      deviceId: 'phone',
    );
    final removed = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{...baseValues, 'referenceImages': <dynamic>[]},
      deviceId: 'phone',
    );
    final added = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{
        ...baseValues,
        'referenceImages': <dynamic>[image('a'), image('b')],
      },
      deviceId: 'desktop',
    );
    final merged = engine.merge(removed, added);

    final protected = syncGcProtectedReferencePaths(
      recordsByKind: records(merged),
      mergeEngine: engine,
    );
    final orphaned = syncGcOrphanReferenceImages(
      record: merged,
      protectedPaths: protected,
    );

    expect(protected, <String>{'assets/order-reference-images/order/b.png'});
    expect(orphaned.map((item) => item.id), <String>['a']);
  });

  test('conflicted records protect every historical reference', () {
    final engine = SyncMergeEngine();
    final baseValues = <String, dynamic>{
      'id': 'order-1',
      'title': 'old',
      'referenceImages': <dynamic>[image('a')],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: baseValues,
      deviceId: 'seed',
    );
    final left = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{...baseValues, 'title': 'left'},
      deviceId: 'phone',
    );
    final right = engine.applyLocalSnapshot(
      record: base,
      previousValues: baseValues,
      nextValues: <String, dynamic>{...baseValues, 'title': 'right'},
      deviceId: 'desktop',
    );
    final conflicted = engine.merge(left, right);

    final protected = syncGcProtectedReferencePaths(
      recordsByKind: records(conflicted),
      mergeEngine: engine,
    );
    final orphaned = syncGcOrphanReferenceImages(
      record: conflicted,
      protectedPaths: protected,
    );

    expect(conflicted.conflicts, isNotEmpty);
    expect(protected, <String>{'assets/order-reference-images/order/a.png'});
    expect(orphaned, isEmpty);
  });

  test('deleted entity reference becomes reclaimable without a time delay', () {
    final engine = SyncMergeEngine();
    final baseValues = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[image('a')],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: baseValues,
      deviceId: 'phone',
    );
    final deleted = engine.markDeleted(base, deviceId: 'phone');

    final protected = syncGcProtectedReferencePaths(
      recordsByKind: records(deleted),
      mergeEngine: engine,
    );
    final orphaned = syncGcOrphanReferenceImages(
      record: deleted,
      protectedPaths: protected,
    );

    expect(protected, isEmpty);
    expect(orphaned.map((item) => item.id), <String>['a']);
  });
}