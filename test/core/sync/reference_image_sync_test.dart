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
