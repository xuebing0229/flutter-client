import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/app_ui_style.dart';
import '../../../core/theme/guild_visual_theme.dart';
import '../../shared/presentation/spotlight_guide.dart';
import 'about_page.dart';
import 'theme_color_page.dart';

class GuildSettingsAppearanceCard extends StatelessWidget {
  const GuildSettingsAppearanceCard({
    required this.themeStore,
    required this.featureStore,
    this.onOpenThemeColor,
    super.key,
  });

  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final VoidCallback? onOpenThemeColor;

  @override
  Widget build(BuildContext context) {
    return GuildSettingsSectionCard(
      title: '外观',
      icon: Icons.brightness_6_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('夜间模式'),
          const SizedBox(height: 6),
          Text(
            '可以固定浅色、固定深色，或跟随手机系统切换。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _ThemeModeSelector(store: themeStore),
          const SizedBox(height: 8),
          const Divider(height: 24),
          AnimatedBuilder(
            animation: themeStore,
            builder: (context, _) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('UI主题色'),
                subtitle: Text('当前：${themeStore.palette.name}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemePalettePreview(
                      palette: themeStore.palette,
                      width: 58,
                      height: 32,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: onOpenThemeColor ??
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ThemeColorPage(store: themeStore),
                        ),
                      );
                    },
              );
            },
          ),
          const Divider(height: 24),
          const Text('UI风格'),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: themeStore,
            builder: (context, _) {
              return Text(
                '当前：${themeStore.style.label}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _UiStyleSelector(store: themeStore),
          const SizedBox(height: 8),
          const Divider(height: 24),
          AnimatedBuilder(
            animation: featureStore,
            builder: (context, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('抽象版'),
                subtitle: const Text('切换普通版与抽象版；首次进入抽象版会自动打开一次教程。'),
                value: featureStore.abstractMode,
                onChanged: (value) {
                  featureStore.setEnabled(
                    AppFeature.abstractMode,
                    value,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class GuildSettingsDataCard extends StatelessWidget {
  const GuildSettingsDataCard({
    required this.exportBusy,
    required this.onExport,
    required this.onImport,
    this.guideTargets,
    this.exportSubtitle =
        '包含工作数据、UI 设置、账号设备记录、完整同步历史、参考图和截图重复检测历史',
    this.importSubtitle = '选择完整备份并覆盖当前数据，同时恢复参考图原文件',
    super.key,
  });

  final bool exportBusy;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final QuickStartGuideTargets? guideTargets;
  final String exportSubtitle;
  final String importSubtitle;

  @override
  Widget build(BuildContext context) {
    return SpotlightTarget(
      targetKey: guideTargets?.settingsBackupKey,
      child: GuildSettingsSectionCard(
        title: '数据与备份',
        icon: Icons.inventory_2_outlined,
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('导出完整备份'),
              subtitle: Text(exportSubtitle),
              trailing: exportBusy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: exportBusy ? null : onExport,
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('导入完整备份'),
              subtitle: Text(importSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: exportBusy ? null : onImport,
            ),
          ],
        ),
      ),
    );
  }
}

class GuildSettingsNewsCard extends StatelessWidget {
  const GuildSettingsNewsCard({
    required this.onOpen,
    super.key,
  });

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GuildSettingsSectionCard(
      title: '冒险者新见闻',
      icon: Icons.auto_stories_rounded,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('查看更新日志'),
        subtitle: const Text('回顾已经加入公会的新功能'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpen,
      ),
    );
  }
}

class GuildSettingsAboutCard extends StatelessWidget {
  const GuildSettingsAboutCard({
    this.version,
    this.buildNumber,
    this.onOpen,
    super.key,
  }) : assert(
          onOpen != null || (version != null && buildNumber != null),
          'Provide either onOpen or version/buildNumber.',
        );

  final String? version;
  final int? buildNumber;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return GuildSettingsSectionCard(
      title: '关于',
      icon: Icons.info_outline_rounded,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.shield_outlined),
        title: const Text('关于冒险者公会'),
        subtitle: const Text('版本信息、开源软件与致谢'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpen ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AppAboutPage(
                    version: version!,
                    buildNumber: buildNumber!,
                  ),
                ),
              );
            },
      ),
    );
  }
}

class GuildSettingsSectionCard extends StatelessWidget {
  const GuildSettingsSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = GuildStyleTheme.of(context);
    final radius = style.isClassic
        ? const BorderRadius.all(Radius.circular(18))
        : style.cardBorderRadius;
    return GuildStyledSurface(
      borderRadius: radius,
      role: GuildSurfaceRole.content,
      backdropAvailable: style.isGlass,
      child: Material(
        color: style.isClassic
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.store});

  final AppThemeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Row(
          children: [
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.system,
                icon: Icons.settings_brightness_rounded,
                label: '跟随',
                onPressed: () => store.setMode(ThemeMode.system),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: '浅色',
                onPressed: () => store.setMode(ThemeMode.light),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: '深色',
                onPressed: () => store.setMode(ThemeMode.dark),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uiStyle = GuildStyleTheme.of(context);
    final radius = uiStyle.isClassic
        ? BorderRadius.circular(16)
        : uiStyle.surfaceBorderRadius;
    final side = BorderSide(
      color: selected
          ? colors.primary
          : uiStyle.isClassic
              ? colors.outline
              : uiStyle.borderColor,
      width: uiStyle.isClassic
          ? 1
          : uiStyle.borderWidth <= 0
              ? 1
              : uiStyle.borderWidth,
    );

    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: side,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UiStyleSelector extends StatelessWidget {
  const _UiStyleSelector({required this.store});

  final AppThemeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final columns = constraints.maxWidth >= 540 ? 4 : 3;
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final style in AppUiStyle.values)
                  SizedBox(
                    width: itemWidth,
                    child: _UiStyleButton(
                      style: style,
                      selected: store.style == style,
                      onPressed: () => store.setStyle(style),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _UiStyleButton extends StatelessWidget {
  const _UiStyleButton({
    required this.style,
    required this.selected,
    required this.onPressed,
  });

  final AppUiStyle style;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        child: Text(
          style.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      child: Text(
        style.label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );
  }
}
