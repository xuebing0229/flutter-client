import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../imports/presentation/screenshot_import_page.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/presentation/add_order_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/presentation/add_product_page.dart';
import '../../products/state/product_store.dart';

Widget buildWorkspaceManualAddPage({
  required bool products,
  required String accountId,
  required OrderStore orderStore,
  required ProductStore productStore,
  required NodePresetStore nodePresetStore,
  required PricingPresetStore pricingPresetStore,
  required AppFeatureStore featureStore,
}) {
  return products
      ? AddProductPage(
          accountId: accountId,
          store: productStore,
          pricingPresetStore: pricingPresetStore,
          featureStore: featureStore,
        )
      : AddOrderPage(
          accountId: accountId,
          store: orderStore,
          nodePresetStore: nodePresetStore,
          pricingPresetStore: pricingPresetStore,
          featureStore: featureStore,
        );
}

Widget buildWorkspaceScreenshotImportPage({
  required bool products,
  required String accountId,
  required OrderStore orderStore,
  required ProductStore productStore,
  required NodePresetStore nodePresetStore,
}) {
  return ScreenshotImportPage(
    kind: products
        ? ScreenshotImportKind.products
        : ScreenshotImportKind.orders,
    accountId: accountId,
    orderStore: orderStore,
    productStore: productStore,
    presetStore: nodePresetStore,
  );
}
