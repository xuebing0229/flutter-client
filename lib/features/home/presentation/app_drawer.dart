import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/cloud_sync/native_sync_coordinator_view_adapter.dart';
import '../../../core/desktop_pet/desktop_pet_service.dart';
import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/guild_visual_theme.dart';
import '../../account/presentation/account_page.dart';
import '../../orders/data/node_presets.dart';
import '../../focus/state/focus_store.dart';
import '../../orders/state/order_store.dart';
import '../../products/state/product_store.dart';
import '../../shared/domain/receipt_style_store.dart';
import '../../shared/presentation/preset_center_page.dart';
import '../../shared/presentation/receipt_center_page.dart';
import '../../sync/presentation/device_sync_page.dart';
import 'archive_page.dart';
import 'desktop_pet_page.dart';
import 'feature_toggle_page.dart';
import 'feedback_page.dart';
import 'settings_page.dart';

Future<String> buildAccountTransferPackage(AccountStore accountStore) async {
  final account = accountStore.syncSnapshot;
  if (account == null || !account.hasCredentials) {
    throw StateError('当前账号信息尚未准备好，不能添加设备。');
  }

  final backup = AppBackupData(
    exportedAt: DateTime.now(),
    orders: const [],
    products: const [],
    nodePresets: const [],
    accountSyncState: account,
    syncRecords: const <Map<String, dynamic>>[],
    settings: const <String, dynamic>{'bootstrapOnly': true},
  );
  return backup.encode(pretty: false);
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.pricingPresetStore,
    required this.receiptStyleStore,
    required this.focusStore,
    required this.desktopPetSettings,
    required this.onOpenOrder,
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    required this.syncCoordinator,
    required this.onApplyWorkspaceSettings,
    required this.onBeforeSignOut,
    required this.onShowTutorial,
    required this.showFeatureToggle,
    required this.onHideFeatureToggle,
    super.key,
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final PricingPresetStore pricingPresetStore;
  final ReceiptStyleStore receiptStyleStore;
  final FocusStore focusStore;
  final DesktopPetSettings desktopPetSettings;
  final Future<void> Function(String orderId) onOpenOrder;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function(Map<String, dynamic> settings)
  onApplyWorkspaceSettings;
  final Future<void> Function() onBeforeSignOut;
  final VoidCallback onShowTutorial;
  final bool showFeatureToggle;
  final VoidCallback onHideFeatureToggle;

  @override
  Widget build(BuildContext context) {
    final uiStyle = GuildStyleTheme.of(context);
    final radius = BorderRadius.horizontal(
      right: Radius.circular(uiStyle.isClassic ? 26 : uiStyle.cardRadius),
    );

    return GuildStyledSurface(
      role: GuildSurfaceRole.chrome,
      borderRadius: radius,
      backdropAvailable: uiStyle.isGlass,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Drawer(
        width: MediaQuery.sizeOf(context).width * 0.78,
        backgroundColor: uiStyle.isClassic ? null : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: SafeArea(
          child: AppToolMenu(
            orderStore: orderStore,
            productStore: productStore,
            nodePresetStore: nodePresetStore,
            pricingPresetStore: pricingPresetStore,
            receiptStyleStore: receiptStyleStore,
            focusStore: focusStore,
            desktopPetSettings: desktopPetSettings,
            onOpenOrder: onOpenOrder,
            themeStore: themeStore,
            featureStore: featureStore,
            accountStore: accountStore,
            syncCoordinator: syncCoordinator,
            onApplyWorkspaceSettings: onApplyWorkspaceSettings,
            onBeforeSignOut: onBeforeSignOut,
            onBeforeNavigate: () => Navigator.of(context).pop(),
            onShowTutorial: onShowTutorial,
            showFeatureToggle: showFeatureToggle,
            onHideFeatureToggle: onHideFeatureToggle,
            closeBeforeTutorial: true,
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 20),
          ),
        ),
      ),
    );
  }
}

class AppToolMenu extends StatelessWidget {
  static const presetTool = 'presetCenter';
  static const receiptTool = 'receiptCenter';
  static const featureToggleTool = 'featureToggle';
  static const archiveTool = 'archive';
  static const syncTool = 'sync';
  static const feedbackTool = 'feedback';
  static const accountTool = 'account';
  static const settingsTool = 'settings';
  static const themeColorTool = 'themeColor';
  static const desktopPetTool = 'desktopPet';

  const AppToolMenu({
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.pricingPresetStore,
    required this.receiptStyleStore,
    required this.focusStore,
    required this.desktopPetSettings,
    required this.onOpenOrder,
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    required this.syncCoordinator,
    required this.onApplyWorkspaceSettings,
    required this.onBeforeSignOut,
    required this.onShowTutorial,
    required this.showFeatureToggle,
    required this.onHideFeatureToggle,
    this.onBeforeNavigate,
    this.onSelectTool,
    this.selectedTool,
    this.closeBeforeTutorial = false,
    this.showTrailing = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final PricingPresetStore pricingPresetStore;
  final ReceiptStyleStore receiptStyleStore;
  final FocusStore focusStore;
  final DesktopPetSettings desktopPetSettings;
  final Future<void> Function(String orderId) onOpenOrder;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function(Map<String, dynamic> settings)
  onApplyWorkspaceSettings;
  final Future<void> Function() onBeforeSignOut;
  final VoidCallback onShowTutorial;
  final bool showFeatureToggle;
  final VoidCallback onHideFeatureToggle;
  final VoidCallback? onBeforeNavigate;
  final ValueChanged<String>? onSelectTool;
  final String? selectedTool;
  final bool closeBeforeTutorial;
  final bool showTrailing;
  final EdgeInsets padding;

  Future<String> _buildTransferPackage() async {
    return buildAccountTransferPackage(accountStore);
  }

  void _open(BuildContext context, String tool, Widget page) {
    if (onSelectTool != null) {
      onSelectTool!(tool);
      return;
    }

    // Keep the mobile drawer open underneath the pushed tool page. Flutter's
    // drawer lives as local route history, so popping the tool page naturally
    // reveals the drawer again instead of dropping straight back to the
    // current work tab.
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _item({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? tool,
    String? subtitle,
  }) {
    return AppMenuTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      selected: tool != null && selectedTool == tool,
      showTrailing: showTrailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDesktopPet =
        Platform.isWindows && featureStore.enabled(AppFeature.desktopPet);
    final showFocus = featureStore.enabled(AppFeature.focus);
    final showPetFocusEntry = showDesktopPet || showFocus;

    return ListView(
      padding: padding,
      children: [
        _item(
          icon: Icons.tune_rounded,
          title: '节点＆加价预设',
          tool: presetTool,
          onTap: () => _open(
            context,
            presetTool,
            PresetCenterPage(
              nodePresetStore: nodePresetStore,
              pricingPresetStore: pricingPresetStore,
            ),
          ),
        ),
        _item(
          icon: Icons.receipt_long_outlined,
          title: '生成小票',
          tool: receiptTool,
          onTap: () => _open(
            context,
            receiptTool,
            ReceiptCenterPage(
              orderStore: orderStore,
              productStore: productStore,
              receiptStyleStore: receiptStyleStore,
            ),
          ),
        ),
        if (showFeatureToggle)
          _item(
            icon: Icons.extension_outlined,
            title: '附加功能开关',
            tool: featureToggleTool,
            onTap: () => _open(
              context,
              featureToggleTool,
              FeatureTogglePage(
                store: featureStore,
                onHideFeatureToggle: onHideFeatureToggle,
              ),
            ),
          ),
        if (showPetFocusEntry)
          _item(
            icon: showDesktopPet ? Icons.pets_outlined : Icons.timer_outlined,
            title: showDesktopPet ? '桌宠' : '专注',
            tool: desktopPetTool,
            onTap: () => _open(
              context,
              desktopPetTool,
              DesktopPetPage(
                orderStore: orderStore,
                focusStore: focusStore,
                settings: desktopPetSettings,
                onOpenOrder: onOpenOrder,
                showDesktopPet: showDesktopPet,
                showFocus: showFocus,
              ),
            ),
          ),
        _item(
          icon: Icons.archive_outlined,
          title: '归档',
          tool: archiveTool,
          onTap: () => _open(
            context,
            archiveTool,
            ArchivePage(
              accountId: syncCoordinator.accountId,
              orderStore: orderStore,
              productStore: productStore,
              nodePresetStore: nodePresetStore,
              pricingPresetStore: pricingPresetStore,
              receiptStyleStore: receiptStyleStore,
              featureStore: featureStore,
              syncCoordinator: NativeSyncCoordinatorViewAdapter(syncCoordinator),
            ),
          ),
        ),
        _item(
          icon: Icons.school_outlined,
          title: '使用教程',
          onTap: () {
            onBeforeNavigate?.call();
            if (closeBeforeTutorial) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onShowTutorial();
              });
            } else {
              onShowTutorial();
            }
          },
        ),
        _item(
          icon: Icons.feedback_outlined,
          title: '问题反馈',
          tool: feedbackTool,
          onTap: () => _open(
            context,
            feedbackTool,
            const FeedbackPage(),
          ),
        ),
        _item(
          icon: Icons.sync_alt_rounded,
          title: '设备同步',
          tool: syncTool,
          onTap: () => _open(
            context,
            syncTool,
            DeviceSyncPage(coordinator: syncCoordinator),
          ),
        ),
        _item(
          icon: Icons.manage_accounts_outlined,
          title: '账号与设备',
          subtitle: accountStore.accountName ?? '本地账号',
          tool: accountTool,
          onTap: () => _open(
            context,
            accountTool,
            AccountPage(
              store: accountStore,
              buildTransferPackage: _buildTransferPackage,
              syncCoordinator: syncCoordinator,
              onBeforeSignOut: onBeforeSignOut,
              onRevokeDevice: syncCoordinator.revokeDevice,
            ),
          ),
        ),
        _item(
          icon: Icons.settings_outlined,
          title: '设置',
          tool: settingsTool,
          onTap: () => _open(
            context,
            settingsTool,
            SettingsPage(
              orderStore: orderStore,
              productStore: productStore,
              nodePresetStore: nodePresetStore,
              focusStore: focusStore,
              themeStore: themeStore,
              featureStore: featureStore,
              desktopPetSettings: desktopPetSettings,
              accountStore: accountStore,
              syncCoordinator: syncCoordinator,
              onApplyWorkspaceSettings: onApplyWorkspaceSettings,
            ),
          ),
        ),
      ],
    );
  }
}

class AppMenuTile extends StatelessWidget {
  const AppMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selectedIcon,
    this.subtitle,
    this.selected = false,
    this.showTrailing = false,
    super.key,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool showTrailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uiStyle = GuildStyleTheme.of(context);
    final selectedTileColor = uiStyle.isClassic
        ? Color.alphaBlend(
            colors.primary.withValues(alpha: 0.11),
            colors.surface,
          )
        : Color.alphaBlend(
            colors.primary.withValues(alpha: 0.18),
            uiStyle.surfaceAlt,
          );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: uiStyle.isClassic
            ? BorderRadius.circular(16)
            : uiStyle.surfaceBorderRadius,
        side: selected
            ? BorderSide(
                color: uiStyle.isClassic
                    ? colors.primary.withValues(alpha: 0.38)
                    : uiStyle.borderWidth > 0
                    ? uiStyle.borderColor
                    : colors.primary.withValues(alpha: 0.55),
                width: uiStyle.isClassic
                    ? 0.8
                    : uiStyle.borderWidth <= 0
                    ? 1
                    : uiStyle.borderWidth,
              )
            : BorderSide.none,
      ),
      selected: selected,
      selectedTileColor: selectedTileColor,
      selectedColor: uiStyle.isClassic
          ? Color.alphaBlend(
              colors.onSurface.withValues(alpha: 0.53),
              colors.primary,
            )
          : colors.primary,
      leading: Icon(selected ? (selectedIcon ?? icon) : icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: showTrailing ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: onTap,
    );
  }
}
