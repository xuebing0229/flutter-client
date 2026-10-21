import 'package:flutter/material.dart';
import 'package:flutter_app/core/account/account_store.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/core/sync/sync_coordinator.dart';
import 'package:flutter_app/core/cloud_sync/native_sync_coordinator_view_adapter.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/presentation/product_page.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'sale confirmation opened before remote archive cannot mutate archive',
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

      products.addProduct(
        const FinishedProduct(
          id: 'stale-sale-product',
          title: '并发售出测试',
          platform: CommissionPlatform.mihuashi,
          saleType: ProductSaleType.multiple,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductPage(
              accountId: 'test-account',
              store: products,
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

      await tester.tap(find.text('售出'));
      await tester.pump();

      products.setArchived('stale-sale-product', true);
      final archivedAt = products.byId('stale-sale-product').archivedAt;
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '确认售出'));
      await tester.pump();

      final product = products.byId('stale-sale-product');
      expect(product.isArchived, isTrue);
      expect(product.archivedAt, archivedAt);
      expect(product.soldCount, 0);
      expect(product.saleRecords, isEmpty);
      expect(
        find.text('成品状态已在另一处更新，请按当前状态重新确认售出。'),
        findsOneWidget,
      );
    },
  );
}
