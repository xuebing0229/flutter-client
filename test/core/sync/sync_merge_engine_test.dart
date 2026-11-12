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

  test('concurrent stale active state cannot undo first archive', () {
    final engine = SyncMergeEngine();
    const active = <String, dynamic>{
      'id': 'archive-race',
      'isArchived': false,
    };

    // The local device edits from its last known baseline while another
    // independently-seeded peer still carries the old active value.
    final localBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-race',
      values: active,
      deviceId: 'phone',
    );
    final archived = engine.applyLocalSnapshot(
      record: localBaseline,
      previousValues: active,
      nextValues: const <String, dynamic>{
        'id': 'archive-race',
        'isArchived': true,
      },
      deviceId: 'phone',
    );
    final staleActive = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-race',
      values: active,
      deviceId: 'desktop',
    );

    final merged = engine.merge(archived, staleActive);
    final reverseMerged = engine.merge(staleActive, archived);

    expect(engine.materialize(merged)!['isArchived'], isTrue);
    expect(engine.materialize(reverseMerged)!['isArchived'], isTrue);
    expect(
      merged.conflicts.values.where((item) => item.field == 'isArchived'),
      isEmpty,
    );
  });

  // Restore remains a later causal action; the archive preference above
  // must not turn isArchived into a one-way flag.
  test('causally newer restore still wins after archive race', () {
    final engine = SyncMergeEngine();
    const active = <String, dynamic>{
      'id': 'archive-restore',
      'isArchived': false,
    };
    final localBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-restore',
      values: active,
      deviceId: 'phone',
    );
    final archived = engine.applyLocalSnapshot(
      record: localBaseline,
      previousValues: active,
      nextValues: const <String, dynamic>{
        'id': 'archive-restore',
        'isArchived': true,
      },
      deviceId: 'phone',
    );
    final staleActive = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-restore',
      values: active,
      deviceId: 'desktop',
    );
    final merged = engine.merge(archived, staleActive);
    final archivedValues = engine.materialize(merged)!;

    final restored = engine.applyLocalSnapshot(
      record: merged,
      previousValues: archivedValues,
      nextValues: <String, dynamic>{
        ...archivedValues,
        'isArchived': false,
      },
      deviceId: 'phone',
    );

    expect(engine.materialize(restored)!['isArchived'], isFalse);
  });

  test('explicit node advance beats a stale concurrent node snapshot', () {
    final engine = SyncMergeEngine();
    const start = <String, dynamic>{
      'id': 'node-race',
      'currentNodeId': 'draft',
      'currentNodeProgress': 0,
    };

    final localBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'node-race',
      values: start,
      deviceId: 'phone',
    );
    final advanced = engine.applyLocalSnapshot(
      record: localBaseline,
      previousValues: start,
      nextValues: const <String, dynamic>{
        'id': 'node-race',
        'currentNodeId': 'line-art',
        'currentNodeProgress': 0,
      },
      deviceId: 'phone',
    );
    final stale = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'node-race',
      values: start,
      deviceId: 'desktop',
    );

    final merged = engine.merge(advanced, stale);
    final reverseMerged = engine.merge(stale, advanced);

    expect(engine.materialize(merged)!['currentNodeId'], 'line-art');
    expect(engine.materialize(reverseMerged)!['currentNodeId'], 'line-art');
    expect(
      merged.conflicts.values.where((item) => item.field == 'currentNodeId'),
      isEmpty,
    );
  });

  test('coalesced rapid node advance still beats the old starting node', () {
    final engine = SyncMergeEngine();
    const start = <String, dynamic>{
      'id': 'rapid-node-race',
      'currentNodeId': 'draft',
      'currentNodeProgress': 0,
    };

    final localBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'rapid-node-race',
      values: start,
      deviceId: 'phone',
    );
    // The 220 ms local debounce may observe draft -> coloring as one snapshot
    // when the user confirms two nodes quickly. The operation still carries
    // the explicit from/to pair and must not be rolled back to draft.
    final rapidlyAdvanced = engine.applyLocalSnapshot(
      record: localBaseline,
      previousValues: start,
      nextValues: const <String, dynamic>{
        'id': 'rapid-node-race',
        'currentNodeId': 'coloring',
        'currentNodeProgress': 0,
      },
      deviceId: 'phone',
    );
    final stale = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'rapid-node-race',
      values: start,
      deviceId: 'desktop',
    );

    final merged = engine.merge(rapidlyAdvanced, stale);
    expect(engine.materialize(merged)!['currentNodeId'], 'coloring');
  });

  test('compacted node transition still beats a stale peer snapshot', () {
    final engine = SyncMergeEngine();
    const start = <String, dynamic>{
      'id': 'compacted-node-race',
      'currentNodeId': 'draft',
      'currentNodeProgress': 0,
    };

    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'compacted-node-race',
      values: start,
      deviceId: 'phone',
    );
    final advanced = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: start,
      nextValues: const <String, dynamic>{
        'id': 'compacted-node-race',
        'currentNodeId': 'line-art',
        'currentNodeProgress': 0,
      },
      deviceId: 'phone',
    );
    final compacted = engine.compactAcknowledgedOperations(
      advanced,
      deviceId: 'phone',
    );
    final stale = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'compacted-node-race',
      values: start,
      deviceId: 'desktop',
    );

    expect(
      engine.materialize(engine.merge(compacted, stale))!['currentNodeId'],
      'line-art',
    );
  });

  // Two real advances are intentionally different from "advance vs stale":
  // keep surfacing those so the user can resolve a genuine cross-device race.
  test('divergent concurrent node advances remain a real conflict', () {
    final engine = SyncMergeEngine();
    const start = <String, dynamic>{
      'id': 'divergent-node-race',
      'currentNodeId': 'draft',
      'currentNodeProgress': 0,
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'divergent-node-race',
      values: start,
      deviceId: 'seed',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: start,
      nextValues: const <String, dynamic>{
        'id': 'divergent-node-race',
        'currentNodeId': 'line-art',
        'currentNodeProgress': 0,
      },
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: start,
      nextValues: const <String, dynamic>{
        'id': 'divergent-node-race',
        'currentNodeId': 'coloring',
        'currentNodeProgress': 0,
      },
      deviceId: 'desktop',
    );

    final merged = engine.merge(phone, desktop);
    expect(
      merged.conflicts.values.where((item) => item.field == 'currentNodeId'),
      hasLength(1),
    );
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

  test('legacy multi-sale count survives sync without sale timestamps', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'legacy-product',
      'saleType': 'multiple',
      'soldCount': 3,
      'saleRecords': <String>[],
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'legacy-product',
      values: values,
      deviceId: 'phone',
    );

    expect(engine.materialize(baseline)!['soldCount'], 3);
    expect(engine.materialize(baseline)!['saleRecords'], isEmpty);

    final changed = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'soldCount': 4,
        'saleRecords': <String>['2026-10-11T12:00:00.000Z'],
      },
      deviceId: 'desktop',
    );
    final materialized = engine.materialize(changed)!;
    expect(materialized['soldCount'], 4);
    expect(
      materialized['saleRecords'],
      <String>['2026-10-11T12:00:00.000Z'],
    );

    final compacted = engine.compactAcknowledgedOperations(
      changed,
      deviceId: 'phone',
    );
    expect(engine.materialize(compacted)!['soldCount'], 4);
    expect(
      engine.materialize(compacted)!['saleRecords'],
      <String>['2026-10-11T12:00:00.000Z'],
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

  test('later single-sale correction wins over an earlier timestamp', () {
    final engine = SyncMergeEngine();
    const original = <String, dynamic>{
      'id': 'product-single-correction',
      'saleType': 'single',
      'soldCount': 0,
      'saleRecords': <String>[],
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-single-correction',
      values: original,
      deviceId: 'phone',
    );
    final firstSale = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: original,
      nextValues: <String, dynamic>{
        ...original,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-11T10:00:00.000Z'],
      },
      deviceId: 'phone',
    );
    final corrected = engine.applyLocalSnapshot(
      record: firstSale,
      previousValues: engine.materialize(firstSale)!,
      nextValues: <String, dynamic>{
        ...engine.materialize(firstSale)!,
        'saleRecords': <String>['2026-10-11T11:00:00.000Z'],
      },
      deviceId: 'phone',
    );

    for (final record in <SyncRecord>[
      engine.merge(firstSale, corrected),
      engine.merge(corrected, firstSale),
    ]) {
      expect(
        engine.materialize(record)!['saleRecords'],
        <String>['2026-10-11T11:00:00.000Z'],
      );
    }
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

  test('older snapshot preserves fields introduced by a newer client', () {
    final engine = SyncMergeEngine();
    const oldValues = <String, dynamic>{
      'id': 'order-forward-compatible',
      'title': '旧客户端可见标题',
    };
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-forward-compatible',
      values: <String, dynamic>{
        ...oldValues,
        'futureField': <String, dynamic>{'value': 42},
      },
      deviceId: 'newer-client',
    );

    final changed = engine.applyLocalSnapshot(
      record: record,
      previousValues: oldValues,
      nextValues: <String, dynamic>{
        ...oldValues,
        'title': '旧客户端修改后的标题',
      },
      deviceId: 'older-client',
    );

    final materialized = engine.materialize(changed)!;
    expect(materialized['title'], '旧客户端修改后的标题');
    expect(materialized['futureField'], <String, dynamic>{'value': 42});
  });

  test('older client never compacts an unknown future operation kind', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'order-future-operation',
      'title': '测试',
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-future-operation',
      values: values,
      deviceId: 'newer-client',
    );
    final futureOperation = SyncOperation(
      id: 'future-op-1',
      field: 'futureField',
      kind: 'future-operation-v2',
      deviceId: 'newer-client',
      occurredAt: DateTime.utc(2026, 10, 12),
      metadata: const <String, dynamic>{'payload': 'must-survive'},
    );
    final record = baseline.copyWith(
      operations: <String, SyncOperation>{
        futureOperation.id: futureOperation,
      },
    );

    expect(engine.hasUnsupportedOperations(record), isTrue);

    final compacted = engine.compactAcknowledgedOperations(
      record,
      deviceId: 'older-client',
    );
    expect(compacted.toJson(), record.toJson());
    expect(
      compacted.operations['future-op-1']!.metadata['payload'],
      'must-survive',
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

  test('concurrent sale client attribution merges by sale timestamp', () {
    final engine = SyncMergeEngine();
    const values = <String, dynamic>{
      'id': 'product-clients',
      'saleType': 'multiple',
      'soldCount': 0,
      'saleRecords': <String>[],
      'saleClientNames': <String, dynamic>{},
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'product-clients',
      values: values,
      deviceId: 'seed',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'saleClientNames': <String, dynamic>{
          '2026-10-24T10:00:00.000Z': 'Alice',
        },
      },
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{
        ...values,
        'saleClientNames': <String, dynamic>{
          '2026-10-24T11:00:00.000Z': 'Bob',
        },
      },
      deviceId: 'desktop',
    );

    final merged = engine.merge(phone, desktop);
    expect(
      engine.materialize(merged)!['saleClientNames'],
      <String, dynamic>{
        '2026-10-24T10:00:00.000Z': 'Alice',
        '2026-10-24T11:00:00.000Z': 'Bob',
      },
    );
    expect(
      merged.conflicts.values.where(
        (conflict) => conflict.field == 'saleClientNames',
      ),
      isEmpty,
    );
  });

  test('explicit state transitions beat stale independently-seeded snapshots', () {
    final engine = SyncMergeEngine();

    const activeOrder = <String, dynamic>{
      'id': 'transition-order',
      'currentNodeId': 'node-a',
      'currentNodeProgress': 60,
      'completedAt': null,
      'settledAt': null,
      'settledIncome': null,
      'archiveOutcome': null,
      'settlementNodeId': null,
      'customRefundAmount': null,
      'isArchived': false,
      'isPinned': false,
    };
    final orderBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'transition-order',
      values: activeOrder,
      deviceId: 'phone',
    );
    final archivedOrder = engine.applyLocalSnapshot(
      record: orderBaseline,
      previousValues: activeOrder,
      nextValues: <String, dynamic>{
        ...activeOrder,
        'currentNodeId': 'node-final',
        'currentNodeProgress': 0,
        'completedAt': '2026-11-12T10:00:00.000Z',
        'settledAt': '2026-11-12T10:01:00.000Z',
        'settledIncome': 123.0,
        'archiveOutcome': 'successful',
        'isArchived': true,
      },
      deviceId: 'phone',
    );
    final staleOrder = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'transition-order',
      values: activeOrder,
      deviceId: 'desktop',
    );

    for (final merged in <SyncRecord>[
      engine.merge(archivedOrder, staleOrder),
      engine.merge(staleOrder, archivedOrder),
    ]) {
      final values = engine.materialize(merged)!;
      expect(values['currentNodeId'], 'node-final');
      expect(values['currentNodeProgress'], 0);
      expect(values['completedAt'], '2026-11-12T10:00:00.000Z');
      expect(values['settledAt'], '2026-11-12T10:01:00.000Z');
      expect(values['settledIncome'], 123.0);
      expect(values['archiveOutcome'], 'successful');
      expect(values['isArchived'], isTrue);
      expect(
        merged.conflicts.values.where(
          (conflict) => <String>{
            'currentNodeId',
            'currentNodeProgress',
            'completedAt',
            'settledAt',
            'settledIncome',
            'archiveOutcome',
            'isArchived',
          }.contains(conflict.field),
        ),
        isEmpty,
      );
    }

    final pinned = engine.applyLocalSnapshot(
      record: orderBaseline,
      previousValues: activeOrder,
      nextValues: <String, dynamic>{...activeOrder, 'isPinned': true},
      deviceId: 'phone',
    );
    for (final merged in <SyncRecord>[
      engine.merge(pinned, staleOrder),
      engine.merge(staleOrder, pinned),
    ]) {
      expect(engine.materialize(merged)!['isPinned'], isTrue);
      expect(
        merged.conflicts.values.where((item) => item.field == 'isPinned'),
        isEmpty,
      );
    }
  });

  test('single-sale transition beats stale unsold snapshot as one state change', () {
    final engine = SyncMergeEngine();
    const unsold = <String, dynamic>{
      'id': 'single-sale-stale',
      'saleType': 'single',
      'soldCount': 0,
      'saleRecords': <String>[],
      'saleClientNames': <String, dynamic>{},
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'single-sale-stale',
      values: unsold,
      deviceId: 'phone',
    );
    final sold = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: unsold,
      nextValues: <String, dynamic>{
        ...unsold,
        'soldCount': 1,
        'saleRecords': <String>['2026-11-12T10:00:00.000Z'],
      },
      deviceId: 'phone',
    );
    final stale = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'single-sale-stale',
      values: unsold,
      deviceId: 'desktop',
    );

    for (final merged in <SyncRecord>[
      engine.merge(sold, stale),
      engine.merge(stale, sold),
    ]) {
      final values = engine.materialize(merged)!;
      expect(values['soldCount'], 1);
      expect(
        values['saleRecords'],
        <String>['2026-11-12T10:00:00.000Z'],
      );
      expect(
        merged.conflicts.values.where(
          (conflict) =>
              conflict.field == 'soldCount' ||
              conflict.field == 'saleRecords',
        ),
        isEmpty,
      );
    }
  });

  test('legacy archive transaction stays consistent against stale active snapshot', () {
    final engine = SyncMergeEngine();
    const active = <String, dynamic>{
      'id': 'legacy-archive-bundle',
      'currentNodeId': 'node-a',
      'currentNodeProgress': 50,
      'completedAt': null,
      'settledAt': null,
      'settledIncome': null,
      'archiveOutcome': null,
      'settlementNodeId': null,
      'customRefundAmount': null,
      'isArchived': false,
      'isPinned': true,
    };
    const archived = <String, dynamic>{
      'id': 'legacy-archive-bundle',
      'currentNodeId': 'node-final',
      'currentNodeProgress': 0,
      'completedAt': '2026-11-10T10:00:00.000Z',
      'settledAt': '2026-11-10T10:01:00.000Z',
      'settledIncome': 88.0,
      'archiveOutcome': 'successful',
      'settlementNodeId': null,
      'customRefundAmount': null,
      'isArchived': true,
      'isPinned': false,
    };

    // Bootstrap both sides directly to simulate records created by clients
    // predating state-transition operations.
    final archivedRecord = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'legacy-archive-bundle',
      values: archived,
      deviceId: 'phone',
    );
    final staleActive = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'legacy-archive-bundle',
      values: active,
      deviceId: 'desktop',
    );

    for (final merged in <SyncRecord>[
      engine.merge(archivedRecord, staleActive),
      engine.merge(staleActive, archivedRecord),
    ]) {
      final values = engine.materialize(merged)!;
      expect(values['currentNodeId'], 'node-final');
      expect(values['currentNodeProgress'], 0);
      expect(values['completedAt'], '2026-11-10T10:00:00.000Z');
      expect(values['settledAt'], '2026-11-10T10:01:00.000Z');
      expect(values['settledIncome'], 88.0);
      expect(values['archiveOutcome'], 'successful');
      expect(values['isArchived'], isTrue);
      expect(values['isPinned'], isFalse);
    }
  });

  test('opposing explicit archive and restore transitions remain a conflict', () {
    final engine = SyncMergeEngine();
    const active = <String, dynamic>{
      'id': 'archive-opposition',
      'isArchived': false,
    };
    const archivedValues = <String, dynamic>{
      'id': 'archive-opposition',
      'isArchived': true,
    };

    final archiveBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-opposition',
      values: active,
      deviceId: 'phone',
    );
    final archived = engine.applyLocalSnapshot(
      record: archiveBaseline,
      previousValues: active,
      nextValues: archivedValues,
      deviceId: 'phone',
    );

    final restoreBaseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'archive-opposition',
      values: archivedValues,
      deviceId: 'desktop',
    );
    final restored = engine.applyLocalSnapshot(
      record: restoreBaseline,
      previousValues: archivedValues,
      nextValues: active,
      deviceId: 'desktop',
    );

    final merged = engine.merge(archived, restored);
    expect(
      merged.conflicts.values.where((item) => item.field == 'isArchived'),
      hasLength(1),
    );
  });

}
