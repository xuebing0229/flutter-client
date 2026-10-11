import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('materializes node progress operation', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-1',
      'currentNodeId': 'coloring',
      'currentNodeProgress': 0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'currentNodeProgress': 30},
      deviceId: 'desktop',
    );

    expect(engine.materialize(changed)!['currentNodeProgress'], 30);
  });

  test('materializes multi-sale operation', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'product-1',
      'saleType': 'multiple',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-1',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-05T00:00:00.000Z'],
      },
      deviceId: 'desktop',
    );

    expect(engine.materialize(changed)!['soldCount'], 1);
    expect(
      engine.materialize(changed)!['saleRecords'],
      <String>['2026-10-05T00:00:00.000Z'],
    );
  });

  test('concurrent single-sale marks converge without sale-record conflict', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'product-single',
      'saleType': 'single',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-single',
      values: values,
      deviceId: 'seed',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-11T10:00:00.000Z'],
      },
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-11T10:00:02.000Z'],
      },
      deviceId: 'desktop',
    );

    final merged = engine.merge(phone, desktop);
    final materialized = engine.materialize(merged)!;

    expect(materialized['soldCount'], 1);
    expect(
      materialized['saleRecords'],
      <String>['2026-10-11T10:00:00.000Z'],
    );
    expect(
      merged.conflicts.values.where(
        (conflict) => conflict.field == 'saleRecords',
      ),
      isEmpty,
    );
  });

  test('operation metadata survives transport decoding', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-1',
      'currentNodeId': 'coloring',
      'currentNodeProgress': 0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'currentNodeProgress': 30,
      },
      deviceId: 'phone',
    );

    final decoded = SyncRecord.decode(changed.encode());
    expect(engine.materialize(decoded)!['currentNodeProgress'], 30);

    const productValues = <String, dynamic>{
      'id': 'product-1',
      'saleType': 'multiple',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final productBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-1',
      values: productValues,
      deviceId: 'phone',
    );
    final productChanged = engine.applyLocalSnapshot(
      record: productBaseline,
      previousValues: productValues,
      nextValues: <String, dynamic>{
        ...productValues,
        'soldCount': 1,
        'saleRecords': <String>['sale-1'],
      },
      deviceId: 'phone',
    );
    final decodedProduct = SyncRecord.decode(productChanged.encode());
    expect(engine.materialize(decodedProduct)!['soldCount'], 1);
    expect(
      engine.materialize(decodedProduct)!['saleRecords'],
      <String>['sale-1'],
    );
  });

  test('acknowledged operation compaction preserves materialized state', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'product-compact',
      'saleType': 'multiple',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-compact',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'soldCount': 1,
        'saleRecords': <String>['sale-1'],
      },
      deviceId: 'phone',
    );

    final before = engine.materialize(changed);
    final compacted = engine.compactAcknowledgedOperations(
      changed,
      deviceId: 'desktop',
    );

    expect(engine.materialize(compacted), before);
    expect(compacted.operations, isNotEmpty);
    expect(compacted.operations.values.every((item) => item.compacted), isTrue);
    expect(compacted.operations.values.every((item) => item.delta == null), isTrue);
    expect(
      compacted.operations.values.every((item) => item.metadata.isEmpty),
      isTrue,
    );
  });

  test('compacted operation marker wins over stale full operation', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-compact',
      'supplementAmount': 0.0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-compact',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'supplementAmount': 100.0},
      deviceId: 'phone',
    );
    final compacted = engine.compactAcknowledgedOperations(
      changed,
      deviceId: 'desktop',
    );

    final merged = engine.merge(changed, compacted);
    expect(engine.materialize(merged)!['supplementAmount'], 100.0);
    expect(merged.operations.values.every((item) => item.compacted), isTrue);
  });

  test('compaction does not manufacture a delete conflict', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-delete-after-ack',
      'supplementAmount': 0.0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-delete-after-ack',
      values: values,
      deviceId: 'phone',
    );
    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'supplementAmount': 100.0},
      deviceId: 'phone',
    );

    final compacted = engine.compactAcknowledgedOperations(
      changed,
      deviceId: 'desktop',
    );
    final deletedOnStalePeer = engine.markDeleted(
      changed,
      deviceId: 'phone',
    );
    final merged = engine.merge(deletedOnStalePeer, compacted);

    expect(merged.isDeleted, isTrue);
    expect(merged.conflicts, isEmpty);
  });

  test('independent feature settings merge without a conflict', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'app',
      'feature.search': true,
      'feature.sorting': true,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: values,
      deviceId: 'phone',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'feature.search': false},
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'feature.sorting': false},
      deviceId: 'desktop',
    );

    final merged = engine.merge(phone, desktop);
    final materialized = engine.materialize(merged)!;

    expect(materialized['feature.search'], isFalse);
    expect(materialized['feature.sorting'], isFalse);
    expect(merged.conflicts, isEmpty);
  });

  test('concurrent amount reductions never materialize below zero', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-amount',
      'supplementAmount': 10.0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-amount',
      values: values,
      deviceId: 'phone',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'supplementAmount': 0.0},
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'supplementAmount': 0.0},
      deviceId: 'desktop',
    );

    final merged = engine.merge(phone, desktop);
    expect(engine.materialize(merged)!['supplementAmount'], 0.0);
  });
  test('reference image cleanup metadata survives first compaction phase', () {
    final engine = SyncMergeEngine();
    final image = <String, dynamic>{
      'id': 'ref-a',
      'fileName': 'a.png',
      'relativePath': 'assets/order-reference-images/order/ref-a.png',
      'addedAt': '2026-10-11T00:00:00.000Z',
      'sizeBytes': 10,
    };
    final values = <String, dynamic>{
      'id': 'order-image',
      'referenceImages': <dynamic>[image],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-image',
      values: values,
      deviceId: 'phone',
    );
    final removed = engine.applyLocalSnapshot(
      record: base,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'referenceImages': <dynamic>[]},
      deviceId: 'phone',
    );

    final compacted = engine.compactAcknowledgedOperations(
      removed,
      deviceId: 'phone',
    );
    final marker = compacted.operations.values.single;
    expect(marker.compacted, isTrue);
    expect(marker.metadata['removed'], isNotEmpty);
    expect(engine.materialize(compacted)!['referenceImages'], isEmpty);
  });

  test('deleted records enter compacted tombstone phase before disappearing', () {
    final engine = SyncMergeEngine();
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-deleted',
      values: const <String, dynamic>{'id': 'order-deleted'},
      deviceId: 'phone',
    );
    final deleted = engine.markDeleted(base, deviceId: 'phone');

    final compacted = engine.compactAcknowledgedOperations(
      deleted,
      deviceId: 'phone',
    );

    expect(compacted.isDeleted, isTrue);
    expect(compacted.operations, isNotEmpty);
    expect(compacted.operations.values.every((operation) => operation.compacted), isTrue);
  });
}
