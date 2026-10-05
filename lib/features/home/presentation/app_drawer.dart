import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/features/app_feature_store.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../account/presentation/account_page.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/presentation/node_preset_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/state/product_store.dart';
import '../../sync/presentation/device_sync_page.dart';
import 'archive_page.dart';
import 'feature_toggle_page.dart';
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
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    required this.syncCoordinator,
    required this.onBeforeSignOut,
    required this.onShowTutorial,
    super.key,
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function() onBeforeSignOut;
  final VoidCallback onShowTutorial;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.78,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(26),
        ),
      ),
      child: SafeArea(
        child: AppToolMenu(
          orderStore: orderStore,
          productStore: productStore,
          nodePresetStore: nodePresetStore,
          themeStore: themeStore,
          featureStore: featureStore,
          accountStore: accountStore,
          syncCoordinator: syncCoordinator,
          onBeforeSignOut: onBeforeSignOut,
          onBeforeNavigate: () => Navigator.of(context).pop(),
          onShowTutorial: onShowTutorial,
          closeBeforeTutorial: true,
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 20),
        ),
      ),
    );
  }
}

class AppToolMenu extends StatelessWidget {
  static const nodePresetTool = 'nodePreset';
  static const featureToggleTool = 'featureToggle';
  static const archiveTool = 'archive';
  static const syncTool = 'sync';
  static const accountTool = 'account';
  static const settingsTool = 'settings';
  static const themeColorTool = 'themeColor';

  const AppToolMenu({
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    required this.syncCoordinator,
    required this.onBeforeSignOut,
    required this.onShowTutorial,
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
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function() onBeforeSignOut;
  final VoidCallback onShowTutorial;
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

    onBeforeNavigate?.call();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => page,
      ),
    );
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
    return ListView(
      padding: padding,
      children: [
        _item(
          icon: Icons.account_tree_outlined,
          title: '节点预设',
          tool: nodePresetTool,
          onTap: () => _open(
            context,
            nodePresetTool,
            NodePresetPage(store: nodePresetStore),
          ),
        ),
        _item(
          icon: Icons.extension_outlined,
          title: '附加功能开关',
          tool: featureToggleTool,
          onTap: () => _open(
            context,
            featureToggleTool,
            FeatureTogglePage(store: featureStore),
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
              orderStore: orderStore,
              productStore: productStore,
              nodePresetStore: nodePresetStore,
              featureStore: featureStore,
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
              themeStore: themeStore,
              featureStore: featureStore,
              accountStore: accountStore,
              syncCoordinator: syncCoordinator,
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      selected: selected,
      selectedTileColor: colors.secondaryContainer,
      selectedColor: colors.onSecondaryContainer,
      leading: Icon(selected ? (selectedIcon ?? icon) : icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: showTrailing ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: onTap,
    );
  }
}
