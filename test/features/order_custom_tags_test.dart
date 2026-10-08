import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/core/sync/sync_entity_codec.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  QueueOrder createOrder() => QueueOrder(
        id: 'order-tags-test',
        platform: CommissionPlatform.mihuashi,
        title: '标签测试',
        clientName: '',
        deadline: null,
        nodePresetId: defaultNodePreset.id,
        nodePresetSnapshot: defaultNodePreset,
        currentNodeId: defaultNodePreset.nodes.first.id,
        tags: normalizeOrderTags(['加急', '  商稿  ', '加急', '']),
      );

  test('labels are normalized, stable when copying, and appear in sync', () {
    final order = createOrder();
    expect(order.tags, ['加急', '商稿']);
    expect(order.copyWith(description: '修改备注').tags, ['加急', '商稿']);

    final fields = SyncEntityCodec.orderToFields(order);
    expect(fields['tags'], ['加急', '商稿']);
    expect(SyncEntityCodec.orderFromFields(fields).tags, ['加急', '商稿']);
  });

  test('complete backup round-trip preserves labels', () {
    final source = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 8),
      orders: [createOrder()],
      products: const [],
      nodePresets: const [],
    );
    final restored = AppBackupData.decode(source.encode());
    expect(restored.orders.single.tags, ['加急', '商稿']);
  });

  test('old records without tags remain readable', () {
    final fields = SyncEntityCodec.orderToFields(createOrder())
      ..remove('tags');
    expect(SyncEntityCodec.orderFromFields(fields).tags, isEmpty);

    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 8),
      orders: [createOrder()],
      products: const [],
      nodePresets: const [],
    );
    final raw = jsonDecode(backup.encode()) as Map<String, dynamic>;
    final payload = raw['payload'] as Map<String, dynamic>;
    final orders = payload['orders'] as List<dynamic>;
    (orders.single as Map<String, dynamic>).remove('tags');
    final oldBackup = AppBackupData.decode(jsonEncode(raw));
    expect(oldBackup.orders.single.tags, isEmpty);
  });
}
