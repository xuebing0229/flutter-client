import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';

typedef ThemePaletteEditCallback = Future<void> Function(
  BuildContext context, {
  AppThemePalette? palette,
  bool forceCopy,
});

class ThemeColorPageBody extends StatelessWidget {
  const ThemeColorPageBody({
    required this.store,
    required this.onEdit,
    required this.onDelete,
    this.onShare,
    super.key,
  });

  final AppThemeStore store;
  final ThemePaletteEditCallback onEdit;
  final Future<void> Function(
    BuildContext context,
    AppThemePalette palette,
  ) onDelete;
  final Future<void> Function(
    BuildContext context,
    AppThemePalette palette,
  )? onShare;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final custom = store.customPalettes;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _CustomColorEntry(
              onTap: () => onEdit(context, forceCopy: false),
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
                        onEdit(
                          context,
                          palette: palette,
                          forceCopy: false,
                        );
                      } else if (value == 'copy') {
                        onEdit(
                          context,
                          palette: palette,
                          forceCopy: true,
                        );
                      } else if (value == 'share') {
                        onShare?.call(context, palette);
                      } else if (value == 'delete') {
                        onDelete(context, palette);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('编辑'),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('复制为新方案'),
                      ),
                      if (onShare != null)
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('分享配色'),
                        ),
                      const PopupMenuItem(
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
    );
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
