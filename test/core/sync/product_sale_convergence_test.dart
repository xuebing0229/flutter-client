import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = <String, dynamic>{
    'id': 'product-convergence-1',
    'saleType': 'multiple',
    'soldCount': 0,
    'saleRecords': <String>[],
  };

  test('offline phone and PC sales merge once, regardless of merge order', () {
    final engine = SyncMergeEngine();
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: original['id']! as String,
      values: original,
      deviceId: 'initial',
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: original,
      nextValues: <String, dynamic>{
        ...original,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-10T08:30:00.000Z'],
      },
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: original,
      nextValues: <String, dynamic>{
        ...original,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-10T09:45:00.000Z'],
      },
      deviceId: 'desktop',
    );

    final forward = engine.materialize(engine.merge(phone, desktop))!;
    final reverse = engine.materialize(engine.merge(desktop, phone))!;
    expect(forward['soldCount'], 2);
    expect(
      (forward['saleRecords'] as List<dynamic>).toSet(),
      <String>{
        '2026-10-10T08:30:00.000Z',
        '2026-10-10T09:45:00.000Z',
      },
    );
    expect(reverse['soldCount'], forward['soldCount']);
    expect(
      (reverse['saleRecords'] as List<dynamic>).toSet(),
      (forward['saleRecords'] as List<dynamic>).toSet(),
    );
  });

  test('replaying the same remote sale does not double-count', () {
    final engine = SyncMergeEngine();
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: original['id']! as String,
      values: original,
      deviceId: 'initial',
    );
    final sold = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: original,
      nextValues: <String, dynamic>{
        ...original,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-10T08:30:00.000Z'],
      },
      deviceId: 'phone',
    );

    final twice = engine.merge(sold, engine.merge(sold, baseline));
    expect(engine.materialize(twice)!['soldCount'], 1);
    expect(engine.materialize(twice)!['saleRecords'], hasLength(1));
  });

  test('sale reversal after both devices synced survives compaction', () {
    final engine = SyncMergeEngine();
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: original['id']! as String,
      values: original,
      deviceId: 'initial',
    );

    final sold = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: original,
      nextValues: <String, dynamic>{
        ...original,
        'soldCount': 2,
        'saleRecords': <String>[
          '2026-10-10T08:30:00.000Z',
          '2026-10-10T09:45:00.000Z',
        ],
      },
      deviceId: 'phone',
    );

    final counted = engine.materialize(sold)!;
    final reversed = engine.applyLocalSnapshot(
      record: sold,
      previousValues: counted,
      nextValues: <String, dynamic>{
        ...counted,
        'soldCount': 1,
        'saleRecords': <String>['2026-10-10T08:30:00.000Z'],
      },
      deviceId: 'desktop',
    );
    expect(engine.materialize(reversed)!['soldCount'], 1);
    expect(
      engine.materialize(reversed)!['saleRecords'],
      <String>['2026-10-10T08:30:00.000Z'],
    );

    final compacted = engine.compactAcknowledgedOperations(
      reversed,
      deviceId: 'desktop',
    );
    final replayed = engine.merge(compacted, sold);
    expect(engine.materialize(replayed)!['soldCount'], 1);
    expect(
      engine.materialize(replayed)!['saleRecords'],
      <String>['2026-10-10T08:30:00.000Z'],
    );
  });
}
