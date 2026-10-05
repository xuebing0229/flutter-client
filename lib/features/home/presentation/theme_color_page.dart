import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../shared/presentation/layout_spacing.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({
    required this.store,
    super.key,
  });

  final AppThemeStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UI主题色',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView.separated(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 10,
              right: 16,
            ),
            itemCount: AppThemePalettes.all.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final palette = AppThemePalettes.all[index];
              final selected = palette.id == store.paletteId;
              final colors = Theme.of(context).colorScheme;

              return Material(
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
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  subtitle: selected ? const Text('当前使用') : null,
                  trailing: selected
                      ? Icon(Icons.check_circle_rounded, color: colors.primary)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () => store.setPaletteId(palette.id),
                ),
              );
            },
          );
        },
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
