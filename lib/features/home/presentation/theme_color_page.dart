import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import 'custom_theme_color_page.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({
    required this.store,
    this.onBack,
    super.key,
  });

  final AppThemeStore store;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: '返回设置',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
        title: const Text(
          'UI主题色',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final custom = store.customPalettes;
          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 10,
              right: 16,
            ),
            children: [
              _CustomColorEntry(
                onTap: () => _openEditor(context),
              ),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _SectionTitle(title: '我的配色'),
                const SizedBox(height: 8),
                for (final palette in custom) ...[
                  _PaletteTile(
                    palette: palette,
                    selected: palette.id == store.paletteId,
                    onTap: () => store.setPaletteId(palette.id),
                    trailing: PopupMenuButton<String>(
                      tooltip: '配色操作',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openEditor(context, palette: palette);
                        } else if (value == 'copy') {
                          _openEditor(
                            context,
                            palette: AppThemePalette.custom(
                              id: 'custom:copy-preview',
                              name: '${palette.name} 副本',
                              seed: palette.lightSeed,
                              light: palette.lightSemanticColors!,
                              dark: palette.darkSemanticColors!,
                              advanced: palette.customAdvanced,
                            ),
                            forceCopy: true,
                          );
                        } else if (value == 'delete') {
                          _deletePalette(context, palette);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('复制为新方案'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              const _SectionTitle(title: '预设主题色'),
              const SizedBox(height: 8),
              for (final palette in AppThemePalettes.all) ...[
                _PaletteTile(
                  palette: palette,
                  selected: palette.id == store.paletteId,
                  onTap: () => store.setPaletteId(palette.id),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AppThemePalette? palette,
    bool forceCopy = false,
  }) async {
    AppThemePalette? source = palette;
    if (forceCopy && palette != null) {
      source = AppThemePalette.custom(
        id: 'custom:copy:${DateTime.now().microsecondsSinceEpoch}',
        name: palette.name,
        seed: palette.lightSeed,
        light: palette.lightSemanticColors!,
        dark: palette.darkSemanticColors!,
        advanced: palette.customAdvanced,
      );
    }
    await Navigator.of(context).push<AppThemePalette>(
      MaterialPageRoute(
        builder: (context) => CustomThemeColorPage(
          store: store,
          palette: source,
        ),
      ),
    );
  }

  Future<void> _deletePalette(
    BuildContext context,
    AppThemePalette palette,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个配色？'),
        content: Text('“${palette.name}”会从我的配色中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.deleteCustomPalette(palette.id);
    }
  }
}

class _CustomColorEntry extends StatelessWidget {
  const _CustomColorEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.40),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        leading: Container(
          width: 52,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const SweepGradient(
              colors: <Color>[
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.red,
              ],
            ),
          ),
          child: const Icon(
            Icons.colorize_rounded,
            color: Colors.white,
          ),
        ),
        title: const Text(
          '自定义调色',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('自己决定主色、背景、卡片、文字、边框等颜色'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final AppThemePalette palette;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colors.secondaryContainer.withValues(alpha: 0.55)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minTileHeight: 66,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: ThemePalettePreview(
            palette: palette,
            width: 76,
            height: 42,
          ),
          title: Text(
            palette.name,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          subtitle: selected ? const Text('当前使用') : null,
          trailing: trailing ??
              (selected
                  ? Icon(Icons.check_circle_rounded, color: colors.primary)
                  : const Icon(Icons.chevron_right_rounded)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class ThemePalettePreview extends StatelessWidget {
  const ThemePalettePreview({
    required this.palette,
    this.width = 58,
    this.height = 32,
    super.key,
  });

  final AppThemePalette palette;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = palette.previewColors;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final color in colors)
            Expanded(
              child: ColoredBox(color: color),
            ),
        ],
      ),
    );
  }
}
