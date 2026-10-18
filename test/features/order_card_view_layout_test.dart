import 'package:flutter/material.dart';
import 'package:flutter_app/core/account/account_store.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/core/sync/sync_coordinator.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/presentation/order_queue_page.dart';
import 'package:flutter_app/features/orders/presentation/order_summary_card.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'order card view keeps confirm buttons inside equal-height cards',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
      for (final (index, title) in <String>[
        '短标题',
        '一个很长很长的标题，会在紧凑卡片里换成两行显示',
        '第三张',
        '第四张',
      ].indexed) {
        orders.addOrder(
          QueueOrder(
            id: 'card-view-$index',
            platform: CommissionPlatform.mihuashi,
            title: title,
            clientName: '单主',
            deadline: null,
            nodePresetId: defaultNodePreset.id,
            nodePresetSnapshot: defaultNodePreset,
            currentNodeId: nodes[index % 2].id,
            tags: index.isEven ? const <String>['加急'] : const <String>[],
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderQueuePage(
              accountId: 'test-account',
              store: orders,
              nodePresetStore: presets,
              featureStore: features,
              syncCoordinator: coordinator,
              cardView: true,
              onCardViewChanged: (_) {},
              sortModeName: 'defaultOrder',
              onSortModeChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final cards = find.byType(OrderSummaryCard);
      expect(cards, findsAtLeastNWidgets(2));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(first.top, second.top);
      expect(first.height, second.height);

      for (var index = 0; index < 2; index++) {
        final card = tester.getRect(cards.at(index));
        final button = tester.getRect(
          find.descendant(
            of: cards.at(index),
            matching: find.text('确认节点'),
          ),
        );
        expect(card.contains(button.topLeft), isTrue);
        expect(card.contains(button.bottomRight), isTrue);
      }
    },
  );
}
