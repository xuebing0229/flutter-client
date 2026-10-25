import 'package:flutter/material.dart';

import '../../../core/theme/guild_visual_theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.onSelectTool,
    required this.onShowTutorial,
    required this.showFeatureToggle,
    required this.showPetFocusEntry,
    required this.showDesktopPet,
    this.showFeedback = true,
    this.accountSubtitle,
    this.onHideFeatureToggle,
    super.key,
  });

  final ValueChanged<String> onSelectTool;
  final VoidCallback onShowTutorial;
  final bool showFeatureToggle;
  final bool showPetFocusEntry;
  final bool showDesktopPet;
  final bool showFeedback;
  final String? accountSubtitle;
  final VoidCallback? onHideFeatureToggle;

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
            onSelectTool: onSelectTool,
            onShowTutorial: onShowTutorial,
            showFeatureToggle: showFeatureToggle,
            showPetFocusEntry: showPetFocusEntry,
            showDesktopPet: showDesktopPet,
            showFeedback: showFeedback,
            accountSubtitle: accountSubtitle,
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
  static const nodePresetTool = 'nodePreset';
  static const pricingPresetTool = 'pricingPreset';
  static const featureToggleTool = 'featureToggle';
  static const archiveTool = 'archive';
  static const syncTool = 'sync';
  static const feedbackTool = 'feedback';
  static const accountTool = 'account';
  static const settingsTool = 'settings';
  static const themeColorTool = 'themeColor';
  static const desktopPetTool = 'desktopPet';

  const AppToolMenu({
    required this.onSelectTool,
    required this.onShowTutorial,
    required this.showFeatureToggle,
    required this.showPetFocusEntry,
    required this.showDesktopPet,
    this.showFeedback = true,
    this.accountSubtitle,
    this.onHideFeatureToggle,
    this.selectedTool,
    this.closeBeforeTutorial = false,
    this.showTrailing = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final ValueChanged<String> onSelectTool;
  final VoidCallback onShowTutorial;
  final bool showFeatureToggle;
  final bool showPetFocusEntry;
  final bool showDesktopPet;
  final bool showFeedback;
  final String? accountSubtitle;
  final VoidCallback? onHideFeatureToggle;
  final String? selectedTool;
  final bool closeBeforeTutorial;
  final bool showTrailing;
  final EdgeInsets padding;

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
    void select(String tool) => onSelectTool(tool);

    return ListView(
      padding: padding,
      children: [
        _item(
          icon: Icons.tune_rounded,
          title: '节点＆加价预设',
          tool: presetTool,
          onTap: () => select(presetTool),
        ),
        _item(
          icon: Icons.receipt_long_outlined,
          title: '生成小票',
          tool: receiptTool,
          onTap: () => select(receiptTool),
        ),
        if (showFeatureToggle)
          _item(
            icon: Icons.extension_outlined,
            title: '附加功能开关',
            tool: featureToggleTool,
            onTap: () => select(featureToggleTool),
          ),
        if (showPetFocusEntry)
          _item(
            icon: showDesktopPet ? Icons.pets_outlined : Icons.timer_outlined,
            title: showDesktopPet ? '桌宠' : '专注',
            tool: desktopPetTool,
            onTap: () => select(desktopPetTool),
          ),
        _item(
          icon: Icons.archive_outlined,
          title: '归档',
          tool: archiveTool,
          onTap: () => select(archiveTool),
        ),
        _item(
          icon: Icons.school_outlined,
          title: '使用教程',
          onTap: () {
            if (closeBeforeTutorial) Navigator.of(context).pop();
            if (closeBeforeTutorial) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onShowTutorial();
              });
            } else {
              onShowTutorial();
            }
          },
        ),
        if (showFeedback)
          _item(
            icon: Icons.feedback_outlined,
            title: '问题反馈',
            tool: feedbackTool,
            onTap: () => select(feedbackTool),
          ),
        _item(
          icon: Icons.sync_alt_rounded,
          title: '设备同步',
          tool: syncTool,
          onTap: () => select(syncTool),
        ),
        _item(
          icon: Icons.manage_accounts_outlined,
          title: '账号与设备',
          subtitle: accountSubtitle,
          tool: accountTool,
          onTap: () => select(accountTool),
        ),
        _item(
          icon: Icons.settings_outlined,
          title: '设置',
          tool: settingsTool,
          onTap: () => select(settingsTool),
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
