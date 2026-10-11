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

  test('restored snapshot overrides known newer fields and operations', () {
    final engine = SyncMergeEngine();
    const oldValues = <String, dynamic>{
      'id': 'order-restore',
      'title': '旧备份标题',
      'supplementAmount': 0.0,
    };
    final oldRecord = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-restore',
      values: oldValues,
      deviceId: 'phone',
    ).copyWith(accountId: 'account-1');

    final newer = engine.applyLocalSnapshot(
      record: oldRecord,
      previousValues: oldValues,
      nextValues: const <String, dynamic>{
        'id': 'order-restore',
        'title': '后来修改的标题',
        'supplementAmount': 80.0,
      },
      deviceId: 'desktop',
    );

    final restored = engine.restoreSnapshot(
      kind: SyncEntityKind.order,
      id: 'order-restore',
      accountId: 'account-1',
      values: oldValues,
      deviceId: 'phone',
      histories: <SyncRecord>[oldRecord, newer],
    );

    final mergedWithStalePeer = engine.merge(restored, newer);
    final materialized = engine.materialize(mergedWithStalePeer)!;
    expect(materialized['title'], '旧备份标题');
    expect(materialized['supplementAmount'], 0.0);
    expect(mergedWithStalePeer.conflicts, isEmpty);
    expect(
      mergedWithStalePeer.operations.values.every((item) => item.compacted),
      isTrue,
    );
  });

  test('restored snapshot tombstones entities absent from the backup', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'product-after-backup',
      'saleType': 'multiple',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final current = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-after-backup',
      values: values,
      deviceId: 'desktop',
    ).copyWith(accountId: 'account-1');

    final restoredDeletion = engine.restoreSnapshot(
      kind: SyncEntityKind.product,
      id: 'product-after-backup',
      accountId: 'account-1',
      values: null,
      deviceId: 'phone',
      histories: <SyncRecord>[current],
    );

    expect(restoredDeletion.isDeleted, isTrue);
    final hiddenPayload =
        engine.materializeIncludingDeleted(restoredDeletion);
    expect(hiddenPayload['saleType'], 'multiple');
    expect(hiddenPayload['soldCount'], 0);

    final mergedWithStalePeer = engine.merge(restoredDeletion, current);
    expect(mergedWithStalePeer.isDeleted, isTrue);
    expect(engine.materialize(mergedWithStalePeer), isNull);
    expect(mergedWithStalePeer.conflicts, isEmpty);
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

}
