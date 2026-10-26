import 'package:flutter/material.dart';

import '../core/theme/app_theme_store.dart';
import '../core/theme/guild_visual_theme.dart';

class GuildAppTheme {
  const GuildAppTheme._();

  static Color _onColor(Color color) {
    return color.computeLuminance() > 0.48 ? Colors.black : Colors.white;
  }

  static ColorScheme scheme(
    AppThemeStore store,
    Brightness brightness,
  ) {
    final palette = store.palette;
    final colors = palette.previewColors;
    final primary = colors.first;
    final secondary = colors.length > 1 ? colors[1] : primary;
    final tertiary = colors.length > 2 ? colors[2] : secondary;
    final primaryContainer =
        colors.length > 3 ? colors[3] : primary;
    final secondaryContainer =
        colors.length > 4 ? colors[4] : secondary;
    final tertiaryContainer =
        colors.length > 2 ? colors.last : primary;

    final dark = brightness == Brightness.dark;
    final semantic = palette.semanticColorsFor(brightness);
    final base = ColorScheme.fromSeed(
      seedColor: dark ? palette.effectiveDarkSeed : palette.lightSeed,
      brightness: brightness,
    );

    if (semantic != null) {
      final semanticTertiary = Color.lerp(
            semantic.primary,
            semantic.accent,
            0.55,
          ) ??
          semantic.accent;
      return base.copyWith(
        primary: semantic.primary,
        onPrimary: _onColor(semantic.primary),
        primaryContainer: semantic.surfaceAlt,
        onPrimaryContainer: semantic.foreground,
        secondary: semantic.accent,
        onSecondary: _onColor(semantic.accent),
        secondaryContainer: semantic.surfaceAlt,
        onSecondaryContainer: semantic.foreground,
        tertiary: semanticTertiary,
        onTertiary: _onColor(semanticTertiary),
        tertiaryContainer: semantic.surfaceAlt,
        onTertiaryContainer: semantic.foreground,
        surface: semantic.surface,
        onSurface: semantic.foreground,
        surfaceContainerLowest: semantic.background,
        surfaceContainerLow: semantic.surface,
        surfaceContainer: semantic.surfaceAlt,
        surfaceContainerHigh: semantic.surfaceAlt,
        surfaceContainerHighest: semantic.surfaceAlt,
        onSurfaceVariant: semantic.mutedForeground,
        outline: semantic.border,
        outlineVariant: semantic.border,
        inversePrimary: semantic.primary,
        surfaceTint: Colors.transparent,
      );
    }

    return base.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: _onColor(primaryContainer),
      secondary: secondary,
      onSecondary: _onColor(secondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _onColor(secondaryContainer),
      tertiary: tertiary,
      onTertiary: _onColor(tertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _onColor(tertiaryContainer),
      surface: base.surface,
      onSurface: base.onSurface,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurfaceVariant: base.onSurfaceVariant,
      outline: base.outline,
      outlineVariant: base.outlineVariant,
      inversePrimary: primary,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData light(AppThemeStore store) {
    final palette = store.palette;
    return GuildVisualTheme.build(
      scheme(store, Brightness.light),
      style: store.style,
      semanticColors: palette.semanticColorsFor(Brightness.light),
    );
  }

  static ThemeData dark(AppThemeStore store) {
    final palette = store.palette;
    return GuildVisualTheme.build(
      scheme(store, Brightness.dark),
      style: store.style,
      semanticColors: palette.semanticColorsFor(Brightness.dark),
    );
  }
}
