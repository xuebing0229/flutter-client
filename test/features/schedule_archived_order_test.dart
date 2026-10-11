import 'package:flutter/material.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_app/features/schedule/presentation/schedule_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('terminated archived order is not shown as pending', (tester) async {
    final orders = OrderStore();
    final products = ProductStore();
    final presets = NodePresetStore();
    final features = AppFeatureStore();
    final now = DateTime.now();

    orders.replaceAll([
      QueueOrder(
        id: 'terminated-archived',
        platform: CommissionPlatform.mihuashi,
        title: '已中止订单',
        clientName: '单主',
        deadline: DateTime(now.year, now.month, now.day, 23, 59),
        nodePresetId: defaultNodePreset.id,
        nodePresetSnapshot: defaultNodePreset,
        currentNodeId: defaultNodePreset.nodes.first.id,
        isArchived: true,
        archiveOutcome: OrderArchiveOutcome.terminated,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          accountId: 'test-account',
          store: orders,
          productStore: products,
          nodePresetStore: presets,
          featureStore: features,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待交稿 0'), findsOneWidget);
    expect(find.text('已中止订单'), findsNothing);
  });
}
