import 'package:flutter/material.dart';

import '../core/theme/app_theme_background.dart';
import '../core/theme/app_theme_palette.dart';
import '../core/theme/app_theme_store.dart';
import '../core/theme/app_ui_style.dart';
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
    if (store.isImageThemeActive) return _imageTheme(store);
    final palette = store.palette;
    return GuildVisualTheme.build(
      scheme(store, Brightness.light),
      style: store.style,
      semanticColors: palette.semanticColorsFor(Brightness.light),
    );
  }

  static ThemeData dark(AppThemeStore store) {
    if (store.isImageThemeActive) return _imageTheme(store);
    final palette = store.palette;
    return GuildVisualTheme.build(
      scheme(store, Brightness.dark),
      style: store.style,
      semanticColors: palette.semanticColorsFor(Brightness.dark),
    );
  }

  static ThemeData _imageTheme(AppThemeStore store) {
    final font = store.imageFontColor;
    final brightness =
        font.computeLuminance() > 0.55 ? Brightness.dark : Brightness.light;
    final glass = store.imageBackgroundMode == AppImageBackgroundMode.glass;
    final tintBase =
        brightness == Brightness.dark ? Colors.black : Colors.white;
    final semantic = AppThemeSemanticColors(
      primary: font,
      accent: font,
      background: Colors.transparent,
      surface: glass ? tintBase : Colors.transparent,
      surfaceAlt: glass ? tintBase : Colors.transparent,
      foreground: font,
      mutedForeground: font.withValues(alpha: 0.72),
      border: font.withValues(alpha: glass ? 0.26 : 0.34),
    );
    final seedScheme = ColorScheme.fromSeed(
      seedColor: font,
      brightness: brightness,
    );
    final base = GuildVisualTheme.build(
      seedScheme,
      style: glass ? AppUiStyle.glass : AppUiStyle.minimal,
      semanticColors: semantic,
    );
    return _applyImageSurfaceOverrides(
      base,
      font: font,
      brightness: brightness,
      glass: glass,
    );
  }

  static ThemeData _applyImageSurfaceOverrides(
    ThemeData base, {
    required Color font,
    required Brightness brightness,
    required bool glass,
  }) {
    final tintBase =
        brightness == Brightness.dark ? Colors.black : Colors.white;
    final layer = glass
        ? tintBase.withValues(
            alpha: brightness == Brightness.dark ? 0.30 : 0.42,
          )
        : Colors.transparent;
    final overlayLayer = glass
        ? tintBase.withValues(
            alpha: brightness == Brightness.dark ? 0.48 : 0.62,
          )
        : Colors.transparent;
    final side = BorderSide(
      color: font.withValues(alpha: glass ? 0.24 : 0.42),
      width: 1,
    );

    ButtonStyle transparentButton(ButtonStyle? current) {
      return (current ?? const ButtonStyle()).copyWith(
        backgroundColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        foregroundColor: WidgetStatePropertyAll<Color>(font),
        elevation: const WidgetStatePropertyAll<double>(0),
        side: WidgetStatePropertyAll<BorderSide>(side),
      );
    }

    return base.copyWith(
      canvasColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: layer,
        foregroundColor: font,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: layer,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: base.drawerTheme.copyWith(
        backgroundColor: layer,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: overlayLayer,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: overlayLayer,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: overlayLayer,
        modalBackgroundColor: overlayLayer,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: layer,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: layer,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: layer,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: layer,
        selectedColor: font.withValues(alpha: 0.16),
      ),
      filledButtonTheme: glass
          ? base.filledButtonTheme
          : FilledButtonThemeData(
              style: transparentButton(base.filledButtonTheme.style),
            ),
      elevatedButtonTheme: glass
          ? base.elevatedButtonTheme
          : ElevatedButtonThemeData(
              style: transparentButton(base.elevatedButtonTheme.style),
            ),
      floatingActionButtonTheme: glass
          ? base.floatingActionButtonTheme
          : base.floatingActionButtonTheme.copyWith(
              backgroundColor: Colors.transparent,
              foregroundColor: font,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
            ),
    );
  }
}
