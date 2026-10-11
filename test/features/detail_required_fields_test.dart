import 'package:flutter/material.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/presentation/order_detail_page.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/presentation/product_detail_page.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('order detail cannot save an empty required title', (tester) async {
    final store = OrderStore();
    final presets = NodePresetStore();
    final features = AppFeatureStore();
    addTearDown(store.dispose);
    addTearDown(presets.dispose);
    addTearDown(features.dispose);

    store.addOrder(
      QueueOrder(
        id: 'required-order',
        platform: CommissionPlatform.mihuashi,
        title: '原图名',
        clientName: '原单主',
        deadline: null,
        nodePresetId: defaultNodePreset.id,
        nodePresetSnapshot: defaultNodePreset,
        currentNodeId: defaultNodePreset.nodes.first.id,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailPage(
          accountId: 'test-account',
          store: store,
          orderId: 'required-order',
          nodePresetStore: presets,
          featureStore: features,
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();

    expect(store.byId('required-order').title, '原图名');
    expect(find.text('图名和单主需要填写'), findsOneWidget);
  });

  testWidgets('order detail asks before overwriting a synced same-field edit', (
    tester,
  ) async {
    final store = OrderStore();
    final presets = NodePresetStore();
    final features = AppFeatureStore();
    addTearDown(store.dispose);
    addTearDown(presets.dispose);
    addTearDown(features.dispose);

    store.addOrder(
      QueueOrder(
        id: 'concurrent-order-detail',
        platform: CommissionPlatform.mihuashi,
        title: '原图名',
        clientName: '原单主',
        deadline: null,
        nodePresetId: defaultNodePreset.id,
        nodePresetSnapshot: defaultNodePreset,
        currentNodeId: defaultNodePreset.nodes.first.id,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailPage(
          accountId: 'test-account',
          store: store,
          orderId: 'concurrent-order-detail',
          nodePresetStore: presets,
          featureStore: features,
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '本机图名');

    final current = store.byId('concurrent-order-detail');
    store.updateOrder(current.copyWith(title: '同步图名'));
    await tester.pump();

    await tester.tap(find.byTooltip('保存'));
    await tester.pump();

    expect(find.text('这笔排单已在另一处更新'), findsOneWidget);
    expect(store.byId('concurrent-order-detail').title, '同步图名');

    await tester.tap(find.text('保留本机修改'));
    await tester.pumpAndSettle();

    expect(store.byId('concurrent-order-detail').title, '本机图名');
  });

  testWidgets('product detail can reload synced value instead of stale local edit', (
    tester,
  ) async {
    final store = ProductStore();
    final features = AppFeatureStore();
    addTearDown(store.dispose);
    addTearDown(features.dispose);

    store.addProduct(
      const FinishedProduct(
        id: 'concurrent-product-detail',
        title: '原成品名',
        platform: CommissionPlatform.mihuashi,
        saleType: ProductSaleType.single,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailPage(
          accountId: 'test-account',
          store: store,
          productId: 'concurrent-product-detail',
          featureStore: features,
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '本机成品名');

    final current = store.byId('concurrent-product-detail');
    store.updateProduct(current.copyWith(title: '同步成品名'));
    await tester.pump();

    await tester.tap(find.byTooltip('保存'));
    await tester.pump();

    expect(find.text('这个成品已在另一处更新'), findsOneWidget);
    expect(store.byId('concurrent-product-detail').title, '同步成品名');

    await tester.tap(find.text('使用同步版本'));
    await tester.pumpAndSettle();

    expect(store.byId('concurrent-product-detail').title, '同步成品名');
    expect(find.byTooltip('编辑'), findsOneWidget);
  });

  testWidgets('product detail cannot save an empty required title', (tester) async {
    final store = ProductStore();
    final features = AppFeatureStore();
    addTearDown(store.dispose);
    addTearDown(features.dispose);

    store.addProduct(
      const FinishedProduct(
        id: 'required-product',
        title: '原成品名',
        platform: CommissionPlatform.mihuashi,
        saleType: ProductSaleType.single,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailPage(
          accountId: 'test-account',
          store: store,
          productId: 'required-product',
          featureStore: features,
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();

    expect(store.byId('required-product').title, '原成品名');
    expect(find.text('请先填写图名'), findsOneWidget);
  });
}
