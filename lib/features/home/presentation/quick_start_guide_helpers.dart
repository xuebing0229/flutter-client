import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../imports/presentation/screenshot_import_page.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/presentation/add_order_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/state/product_store.dart';
import '../../shared/presentation/spotlight_guide.dart';

Widget buildQuickStartAddOrderPage({
  required String accountId,
  required OrderStore orderStore,
  required NodePresetStore nodePresetStore,
  required PricingPresetStore pricingPresetStore,
  required AppFeatureStore featureStore,
  required QuickStartGuideTargets guideTargets,
}) {
  return AddOrderPage(
    accountId: accountId,
    store: orderStore,
    nodePresetStore: nodePresetStore,
    pricingPresetStore: pricingPresetStore,
    featureStore: featureStore,
    guideTargets: guideTargets,
  );
}

Widget buildQuickStartScreenshotImportPage({
  required String accountId,
  required OrderStore orderStore,
  required ProductStore productStore,
  required NodePresetStore nodePresetStore,
  required QuickStartGuideTargets guideTargets,
}) {
  return ScreenshotImportPage(
    kind: ScreenshotImportKind.orders,
    accountId: accountId,
    orderStore: orderStore,
    productStore: productStore,
    presetStore: nodePresetStore,
    guideTargets: guideTargets,
    autoPick: false,
  );
}

String? findNewGuideOrderId(
  Iterable<String> beforeIds,
  OrderStore orderStore,
) {
  final existing = beforeIds.toSet();
  for (final order in orderStore.orders.reversed) {
    if (!existing.contains(order.id)) return order.id;
  }
  return null;
}

Future<bool> waitForGuideOrderArchive({
  required BuildContext context,
  required OrderStore orderStore,
  required String orderId,
}) async {
  if (!orderStore.contains(orderId)) return false;
  if (orderStore.byId(orderId).isArchived) return true;

  final completer = Completer<bool>();
  void checkArchive() {
    if (completer.isCompleted) return;
    if (!orderStore.contains(orderId)) {
      completer.complete(false);
    } else if (orderStore.byId(orderId).isArchived) {
      completer.complete(true);
    }
  }

  orderStore.addListener(checkArchive);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      duration: const Duration(minutes: 30),
      content: const Text('现在试着长按刚创建的排单 → 归档。完成归档后，新手引导会自动继续。'),
      action: SnackBarAction(
        label: '跳过练习',
        onPressed: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    ),
  );
  try {
    final archived = await completer.future;
    controller.close();
    return archived;
  } finally {
    orderStore.removeListener(checkArchive);
  }
}
