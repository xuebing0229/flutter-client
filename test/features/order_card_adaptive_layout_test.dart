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
    'card rows align corresponding fields without forcing every row to two lines',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
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
        '一个很长很长的标题，会在同一排里自然换成多行显示',
        '第三张',
        '第四张',
      ].indexed) {
        orders.addOrder(
          QueueOrder(
            id: 'card-view-$index',
            platform: CommissionPlatform.mihuashi,
            title: title,
            clientName: index == 1 ? '一个比较长的单主名称' : '单主',
            deadline: null,
            nodePresetId: defaultNodePreset.id,
            nodePresetSnapshot: defaultNodePreset,
            currentNodeId: nodes[index % 2].id,
            tags: index == 1
                ? const <String>['定向企划', '第二个标签', '第三个标签']
                : const <String>[],
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
      expect(cards, findsAtLeastNWidgets(4));

      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(first.top, second.top);
      expect(first.height, second.height);

      final third = tester.getRect(cards.at(2));
      final fourth = tester.getRect(cards.at(3));
      expect(third.top, fourth.top);
      expect(third.height, fourth.height);

      // The second row contains only short titles, so it must stay shorter
      // than the first row instead of inheriting a global two-line slot.
      expect(third.height, lessThan(first.height));
    },
  );

  testWidgets('list view puts the full title below the platform row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final order = QueueOrder(
      id: 'list-title',
      platform: CommissionPlatform.mihuashi,
      title: '这是一个需要在列表视图完整换行展示的很长图名标题',
      clientName: '单主',
      deadline: null,
      nodePresetId: defaultNodePreset.id,
      nodePresetSnapshot: defaultNodePreset,
      currentNodeId: notStartedNodeId,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: OrderSummaryCard(
              order: order,
              compact: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final platformTop = tester.getTopLeft(find.text('米画师')).dy;
    final titleTop = tester
        .getTopLeft(find.text(order.title, findRichText: true))
        .dy;
    expect(titleTop, greaterThan(platformTop));
  });
}
