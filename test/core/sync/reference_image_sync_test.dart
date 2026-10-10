import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> image(String id) => <String, dynamic>{
        'id': id,
        'fileName': '$id.png',
        'relativePath': 'assets/order-reference-images/order/$id.png',
        'addedAt': '2026-10-05T12:00:00.000Z',
        'sizeBytes': 123,
      };

  test('concurrent reference image additions merge by image id', () {
    final engine = SyncMergeEngine();
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: <String, dynamic>{
        'referenceImages': <dynamic>[],
      },
      deviceId: 'device-a',
    );

    final left = engine.applyLocalSnapshot(
      record: base,
      previousValues: <String, dynamic>{
        'referenceImages': <dynamic>[],
      },
      nextValues: <String, dynamic>{
        'referenceImages': <dynamic>[image('a')],
      },
      deviceId: 'device-a',
    );
    final right = engine.applyLocalSnapshot(
      record: base,
      previousValues: <String, dynamic>{
        'referenceImages': <dynamic>[],
      },
      nextValues: <String, dynamic>{
        'referenceImages': <dynamic>[image('b')],
      },
      deviceId: 'device-b',
    );

    final merged = engine.merge(left, right);
    final materialized = engine.materialize(merged)!;
    final images = materialized['referenceImages'] as List<dynamic>;
    final ids = images
        .map((item) => (item as Map)['id'])
        .toSet();

    expect(ids, <Object?>{'a', 'b'});
    expect(
      merged.conflicts.values
          .where((conflict) => conflict.field == 'referenceImages'),
      isEmpty,
    );
  });


  test('clock-skewed stale image add cannot resurrect a removed reference', () {
    final engine = SyncMergeEngine();
    final original = image('a');
    final other = image('b');
    final empty = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[],
    };
    final withA = <String, dynamic>{
      'id': 'order-1',
      'referenceImages': <dynamic>[original],
    };
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: empty,
      deviceId: 'phone',
    );
    final created = engine.applyLocalSnapshot(
      record: base,
      previousValues: empty,
      nextValues: withA,
      deviceId: 'phone',
    );
    final removed = engine.applyLocalSnapshot(
      record: created,
      previousValues: withA,
      nextValues: empty,
      deviceId: 'computer',
    );

    // The phone's wall clock is ten years ahead; the computer removes a
    // reference *after observing it* but stamps that operation much earlier.
    // A clock-time-ordered replay previously applied the stale add last.
    final skewedOperations = <String, SyncOperation>{
      for (final operation in removed.operations.values)
        operation.id: SyncOperation.fromJson(<String, dynamic>{
          ...operation.toJson(),
          'occurredAt': operation.metadata.containsKey('added')
              ? '2036-10-10T00:00:00.000Z'
              : '2026-10-10T00:00:00.000Z',
        }),
    };
    final skewedRemoved = removed.copyWith(operations: skewedOperations);
    final stalePeer = created.copyWith(
      operations: <String, SyncOperation>{
        for (final operation in created.operations.values)
          operation.id: skewedOperations[operation.id]!,
      },
    );
    final unrelated = engine.applyLocalSnapshot(
      record: base,
      previousValues: empty,
      nextValues: <String, dynamic>{
        ...empty,
        'referenceImages': <dynamic>[other],
      },
      deviceId: 'tablet',
    );

    for (final merged in <SyncRecord>[
      engine.merge(skewedRemoved, engine.merge(stalePeer, unrelated)),
      engine.merge(engine.merge(unrelated, stalePeer), skewedRemoved),
    ]) {
      final refs = engine.materialize(merged)!['referenceImages'] as List;
      expect(refs.map((value) => (value as Map)['id']).toSet(), {'b'});

      final compacted = engine.compactAcknowledgedOperations(
        merged,
        deviceId: 'computer',
      );
      final replayed = engine.merge(compacted, stalePeer);
      final replayedRefs =
          engine.materialize(replayed)!['referenceImages'] as List;
      expect(replayedRefs.map((value) => (value as Map)['id']).toSet(), {'b'});
    }
  });

  test('legacy sync record without referenceImages can add its first image', () {
    final engine = SyncMergeEngine();
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: const <String, dynamic>{},
      deviceId: 'device-a',
    );

    final updated = engine.applyLocalSnapshot(
      record: base,
      previousValues: <String, dynamic>{
        'referenceImages': <dynamic>[],
      },
      nextValues: <String, dynamic>{
        'referenceImages': <dynamic>[image('first')],
      },
      deviceId: 'device-a',
    );

    final materialized = engine.materialize(updated)!;
    final images = materialized['referenceImages'] as List<dynamic>;

    expect(images, hasLength(1));
    expect((images.single as Map)['id'], 'first');
  });

  test('reference image removal and concurrent addition both survive merge', () {
    final engine = SyncMergeEngine();
    final baseImages = <dynamic>[image('a')];
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'order-1',
      values: <String, dynamic>{
        'referenceImages': baseImages,
      },
      deviceId: 'device-a',
    );

    final removed = engine.applyLocalSnapshot(
      record: base,
      previousValues: <String, dynamic>{
        'referenceImages': baseImages,
      },
      nextValues: <String, dynamic>{
        'referenceImages': <dynamic>[],
      },
      deviceId: 'device-a',
    );
    final added = engine.applyLocalSnapshot(
      record: base,
      previousValues: <String, dynamic>{
        'referenceImages': baseImages,
      },
      nextValues: <String, dynamic>{
        'referenceImages': <dynamic>[image('a'), image('b')],
      },
      deviceId: 'device-b',
    );

    final materialized = engine.materialize(engine.merge(removed, added))!;
    final images = materialized['referenceImages'] as List<dynamic>;
    final ids = images
        .map((item) => (item as Map)['id'])
        .toSet();

    expect(ids, <Object?>{'b'});
  });
}
