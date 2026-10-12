import 'package:flutter/material.dart';
import 'package:flutter_app/core/features/app_feature_store.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/presentation/product_detail_page.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'multi-sale rollback preserves a sale added remotely while editing',
    (tester) async {
      final store = ProductStore();
      final features = AppFeatureStore();
      addTearDown(store.dispose);
      addTearDown(features.dispose);

      final originalSale = DateTime.utc(2026, 10, 11, 10);
      final remoteSale = DateTime.utc(2026, 10, 11, 10, 5);
      store.addProduct(
        FinishedProduct(
          id: 'product-concurrent-sale',
          title: '测试成品',
          platform: CommissionPlatform.mihuashi,
          saleType: ProductSaleType.multiple,
          soldCount: 1,
          saleRecords: <DateTime>[originalSale],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductDetailPage(
            accountId: 'test-account',
            store: store,
            productId: 'product-concurrent-sale',
            featureStore: features,
          ),
        ),
      );

      await tester.tap(find.byTooltip('编辑'));
      await tester.pump();

      final soldCountField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.number &&
            widget.decoration?.hintText == '0',
      );
      expect(soldCountField, findsOneWidget);
      await tester.enterText(soldCountField, '0');

      // Another device adds a sale after this editor opened.
      final current = store.byId('product-concurrent-sale');
      store.updateProduct(
        current.copyWith(
          soldCount: 2,
          saleRecords: <DateTime>[originalSale, remoteSale],
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('保存'));
      await tester.pump();

      final updated = store.byId('product-concurrent-sale');
      expect(updated.soldCount, 1);
      expect(updated.saleRecords, <DateTime>[remoteSale]);
    },
  );
  testWidgets(
    'editing a legacy count keeps unattributed historical sales',
    (tester) async {
      final store = ProductStore();
      final features = AppFeatureStore();
      addTearDown(store.dispose);
      addTearDown(features.dispose);

      store.addProduct(
        const FinishedProduct(
          id: 'legacy-product-count',
          title: '旧版多次售卖',
          platform: CommissionPlatform.mihuashi,
          saleType: ProductSaleType.multiple,
          soldCount: 3,
          saleRecords: <DateTime>[],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductDetailPage(
            accountId: 'test-account',
            store: store,
            productId: 'legacy-product-count',
            featureStore: features,
          ),
        ),
      );

      await tester.tap(find.byTooltip('编辑'));
      await tester.pump();

      final soldCountField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.number &&
            widget.decoration?.hintText == '0',
      );
      await tester.enterText(soldCountField, '4');
      await tester.tap(find.byTooltip('保存'));
      await tester.pump();

      final updated = store.byId('legacy-product-count');
      expect(updated.soldCount, 4);
      expect(updated.saleRecords, hasLength(1));
    },
  );

}
