import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform adjustment defaults keep Huajia off and Mihuashi on', () {
    expect(CommissionPlatform.mihuashi.defaultAdjustmentFeeEnabled, isTrue);
    expect(CommissionPlatform.huajia.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.bilibiliWorkshop.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.linjie.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.offline.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.archivedOffline.defaultAdjustmentFeeEnabled, isFalse);
  });

  test('invalid custom refunds cannot archive or poison settled income', () {
    final store = OrderStore();
    final order = QueueOrder(
      id: 'order-finance',
      platform: CommissionPlatform.mihuashi,
      title: '测试',
      clientName: '单主',
      deadline: null,
      nodePresetId: defaultNodePreset.id,
      nodePresetSnapshot: defaultNodePreset,
      currentNodeId: defaultNodePreset.nodes.first.id,
      price: 100,
      feeEnabled: true,
    );
    store.addOrder(order);

    store.archiveAsTerminatedWithCustomRefund(order.id, double.nan);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);

    store.archiveAsTerminatedWithCustomRefund(order.id, double.infinity);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);

    store.archiveAsTerminatedWithCustomRefund(order.id, -1);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);
  });
}