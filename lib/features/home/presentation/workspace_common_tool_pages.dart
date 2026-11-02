import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../../core/sync/sync_coordinator_view.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/state/order_store.dart';
import '../../products/state/product_store.dart';
import '../../shared/domain/receipt_style_store.dart';
import '../../shared/presentation/preset_center_page.dart';
import '../../shared/presentation/receipt_center_page.dart';
import '../../shared/presentation/spotlight_guide.dart';
import 'app_drawer.dart';
import 'archive_page.dart';
import 'feature_toggle_page.dart';

Widget? buildWorkspaceCommonToolPage({
  required String tool,
  required String accountId,
  required String accountName,
  required OrderStore orderStore,
  required ProductStore productStore,
  required NodePresetStore nodePresetStore,
  required PricingPresetStore pricingPresetStore,
  required ReceiptStyleStore receiptStyleStore,
  required AppFeatureStore featureStore,
  required SyncCoordinatorView syncCoordinator,
  required QuickStartGuideTargets guideTargets,
  required String? guideOrderId,
  VoidCallback? onHideFeatureToggle,
}) {
  return switch (tool) {
    AppToolMenu.presetTool => PresetCenterPage(
        nodePresetStore: nodePresetStore,
        pricingPresetStore: pricingPresetStore,
        guideTargets: guideTargets,
      ),
    AppToolMenu.receiptTool => ReceiptCenterPage(
        orderStore: orderStore,
        productStore: productStore,
        receiptStyleStore: receiptStyleStore,
        accountName: accountName,
        guideTargets: guideTargets,
      ),
    AppToolMenu.featureToggleTool => FeatureTogglePage(
        store: featureStore,
        onHideFeatureToggle: onHideFeatureToggle,
        guideTargets: guideTargets,
      ),
    AppToolMenu.archiveTool => ArchivePage(
        accountId: accountId,
        orderStore: orderStore,
        productStore: productStore,
        nodePresetStore: nodePresetStore,
        pricingPresetStore: pricingPresetStore,
        receiptStyleStore: receiptStyleStore,
        featureStore: featureStore,
        syncCoordinator: syncCoordinator,
        guideTargets: guideTargets,
        guideOrderId: guideOrderId,
      ),
    _ => null,
  };
}
