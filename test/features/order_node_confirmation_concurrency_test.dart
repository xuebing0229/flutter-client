import 'package:flutter/material.dart';
import 'package:flutter_app/core/account/account_store.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/core/sync/sync_coordinator.dart';
import 'package:flutter_app/core/cloud_sync/native_sync_coordinator_view_adapter.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/presentation/order_queue_page.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'stale node confirmation does not advance a remotely advanced order twice',
    (tester) async {
      final accountStore = AccountStore();
      final orders = OrderStore();
      final products = ProductStore();
      final presets = NodePresetStore();
      final features = AppFeatureStore();
      final coordinator = SyncCoordinator(
        accountId: 'test-account',
        deviceId: 'test-device',
        deviceName: 'test',
        accountStore: accountStore,
        orderStore: orders,
        productStore: products,
        nodePresetStore: presets,
        captureSettings: () => <String, dynamic>{},
        applySettings: (_) async {},
      );
      addTearDown(accountStore.dispose);
      addTearDown(orders.dispose);
      addTearDown(products.dispose);
      addTearDown(presets.dispose);
      addTearDown(features.dispose);
      addTearDown(coordinator.dispose);

      final nodes = defaultNodePreset.nodes;
      orders.addOrder(
        QueueOrder(
          id: 'concurrent-node-order',
          platform: CommissionPlatform.mihuashi,
          title: '并发节点测试',
          clientName: '单主',
          deadline: null,
          nodePresetId: defaultNodePreset.id,
          nodePresetSnapshot: defaultNodePreset,
          currentNodeId: nodes.first.id,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderQueuePage(
              accountId: 'test-account',
              store: orders,
              nodePresetStore: presets,
              featureStore: features,
              syncCoordinator: NativeSyncCoordinatorViewAdapter(coordinator),
              cardView: false,
              onCardViewChanged: (_) {},
              sortModeName: 'defaultOrder',
              onSortModeChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('确认节点'));
      await tester.pump();

      // Another device advances from the first node to the second node while
      // this confirmation dialog still describes first -> second.
      final current = orders.byId('concurrent-node-order');
      orders.updateOrder(current.copyWith(currentNodeId: nodes[1].id));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pump();

      expect(orders.byId('concurrent-node-order').currentNodeId, nodes[1].id);
      expect(find.text('排单节点已在另一处更新，请按当前状态重新确认。'), findsOneWidget);
    },
  );
}
