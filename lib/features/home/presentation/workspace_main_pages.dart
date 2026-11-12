import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../../core/sync/sync_coordinator_view.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/presentation/order_queue_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/presentation/product_page.dart';
import '../../products/state/product_store.dart';
import '../../schedule/presentation/schedule_page.dart';
import '../../shared/domain/receipt_style_store.dart';
import '../../shared/presentation/spotlight_guide.dart';
import '../../statistics/presentation/statistics_page.dart';

Widget buildWorkspaceMainPage({
  required String id,
  required String accountId,
  required OrderStore orderStore,
  required ProductStore productStore,
  required NodePresetStore nodePresetStore,
  required PricingPresetStore pricingPresetStore,
  required ReceiptStyleStore receiptStyleStore,
  required AppFeatureStore featureStore,
  required SyncCoordinatorView syncCoordinator,
  required bool orderCardView,
  required ValueChanged<bool> onOrderCardViewChanged,
  required bool orderOverviewView,
  required ValueChanged<bool> onOrderOverviewViewChanged,
  required int orderOverviewColumns,
  required ValueChanged<int> onOrderOverviewColumnsChanged,
  required String orderSortMode,
  required ValueChanged<String> onOrderSortModeChanged,
  required bool productCardView,
  required ValueChanged<bool> onProductCardViewChanged,
  required bool productOverviewView,
  required ValueChanged<bool> onProductOverviewViewChanged,
  required int productOverviewColumns,
  required ValueChanged<int> onProductOverviewColumnsChanged,
  required String productSortMode,
  required ValueChanged<String> onProductSortModeChanged,
  QuickStartGuideTargets? guideTargets,
  String? guideOrderId,
}) {
  return switch (id) {
    'products' => ProductPage(
        accountId: accountId,
        store: productStore,
        pricingPresetStore: pricingPresetStore,
        receiptStyleStore: receiptStyleStore,
        featureStore: featureStore,
        syncCoordinator: syncCoordinator,
        cardView: productCardView,
        onCardViewChanged: onProductCardViewChanged,
        overviewView: productOverviewView,
        onOverviewViewChanged: onProductOverviewViewChanged,
        overviewColumns: productOverviewColumns,
        onOverviewColumnsChanged: onProductOverviewColumnsChanged,
        sortModeName: productSortMode,
        onSortModeChanged: onProductSortModeChanged,
      ),
    'schedule' => SchedulePage(
        accountId: accountId,
        store: orderStore,
        productStore: productStore,
        nodePresetStore: nodePresetStore,
        featureStore: featureStore,
      ),
    'statistics' => StatisticsPage(
        store: orderStore,
        productStore: productStore,
      ),
    _ => OrderQueuePage(
        accountId: accountId,
        store: orderStore,
        nodePresetStore: nodePresetStore,
        pricingPresetStore: pricingPresetStore,
        receiptStyleStore: receiptStyleStore,
        featureStore: featureStore,
        syncCoordinator: syncCoordinator,
        cardView: orderCardView,
        onCardViewChanged: onOrderCardViewChanged,
        overviewView: orderOverviewView,
        onOverviewViewChanged: onOrderOverviewViewChanged,
        overviewColumns: orderOverviewColumns,
        onOverviewColumnsChanged: onOrderOverviewColumnsChanged,
        sortModeName: orderSortMode,
        onSortModeChanged: onOrderSortModeChanged,
        guideTargets: guideTargets,
        guideOrderId: guideOrderId,
      ),
  };
}
