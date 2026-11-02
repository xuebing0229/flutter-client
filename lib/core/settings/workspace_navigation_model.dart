import 'package:flutter/material.dart';

import '../features/app_feature_store.dart';
import '../../features/home/presentation/app_drawer.dart';
import '../../features/home/presentation/first_run_guide.dart';

class WorkspaceTabSpec {
  const WorkspaceTabSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

List<WorkspaceTabSpec> workspaceTabSpecs(AppFeatureStore features) => <WorkspaceTabSpec>[
      const WorkspaceTabSpec(
        id: 'orders',
        label: '排单',
        icon: Icons.format_list_bulleted_rounded,
        selectedIcon: Icons.view_list_rounded,
      ),
      if (features.products)
        const WorkspaceTabSpec(
          id: 'products',
          label: '成品',
          icon: Icons.image_outlined,
          selectedIcon: Icons.image_rounded,
        ),
      if (features.schedule)
        const WorkspaceTabSpec(
          id: 'schedule',
          label: '日程',
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_rounded,
        ),
      if (features.statistics)
        const WorkspaceTabSpec(
          id: 'statistics',
          label: '统计',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
        ),
    ];

String workspaceToolTitle(String tool, {required String fallback}) {
  return switch (tool) {
    AppToolMenu.presetTool => '节点＆加价预设',
    AppToolMenu.receiptTool => '生成小票',
    AppToolMenu.featureToggleTool => '附加功能开关',
    AppToolMenu.desktopPetTool => '专注',
    AppToolMenu.archiveTool => '归档',
    AppToolMenu.syncTool => '设备同步',
    AppToolMenu.accountTool => '账号与设备',
    AppToolMenu.settingsTool => '设置',
    AppToolMenu.themeColorTool => 'UI主题色',
    _ => fallback,
  };
}

String? quickStartTabId(QuickStartGuideDestination destination) {
  return switch (destination) {
    QuickStartGuideDestination.orders => 'orders',
    QuickStartGuideDestination.products => 'products',
    QuickStartGuideDestination.schedule => 'schedule',
    QuickStartGuideDestination.statistics => 'statistics',
    _ => null,
  };
}

String? quickStartTool(QuickStartGuideDestination destination) {
  return switch (destination) {
    QuickStartGuideDestination.presetCenter => AppToolMenu.presetTool,
    QuickStartGuideDestination.receiptCenter => AppToolMenu.receiptTool,
    QuickStartGuideDestination.archive => AppToolMenu.archiveTool,
    QuickStartGuideDestination.sync => AppToolMenu.syncTool,
    QuickStartGuideDestination.account => AppToolMenu.accountTool,
    QuickStartGuideDestination.settings ||
    QuickStartGuideDestination.pwaInstall => AppToolMenu.settingsTool,
    QuickStartGuideDestination.featureToggle => AppToolMenu.featureToggleTool,
    _ => null,
  };
}

bool quickStartDestinationAvailable(
  QuickStartGuideDestination destination,
  AppFeatureStore features,
) {
  return switch (destination) {
    QuickStartGuideDestination.products => features.products,
    QuickStartGuideDestination.schedule => features.schedule,
    QuickStartGuideDestination.statistics => features.statistics,
    _ => true,
  };
}
