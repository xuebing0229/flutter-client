import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_ui_texture.dart';

class GuildTextureTheme extends ThemeExtension<GuildTextureTheme> {
  const GuildTextureTheme(this.texture);

  final AppUiTexture texture;

  bool get enabled => texture != AppUiTexture.classic;

  double get blurSigma => switch (texture) {
    AppUiTexture.classic => 0,
    AppUiTexture.frosted => 14,
    // On non-Apple platforms this is an adaptive glass fallback, not
    // simulated optical refraction. Keep blur within the verified
    // Glassmorphism 10-20px range.
    AppUiTexture.liquid => 14,
  };

  double overlayOpacity(TargetPlatform platform) {
    return switch (texture) {
      AppUiTexture.classic => 1,
      AppUiTexture.frosted => 0.80,
      AppUiTexture.liquid =>
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
            ? 0.74
            : platform == TargetPlatform.android
            ? 0.86
            : 0.94,
    };
  }

  static GuildTextureTheme of(BuildContext context) =>
      Theme.of(context).extension<GuildTextureTheme>() ??
      const GuildTextureTheme(AppUiTexture.classic);

  @override
  GuildTextureTheme copyWith({AppUiTexture? texture}) =>
      GuildTextureTheme(texture ?? this.texture);

  @override
  GuildTextureTheme lerp(
    covariant ThemeExtension<GuildTextureTheme>? other,
    double t,
  ) {
    if (other is! GuildTextureTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Visual-only theme tokens.
///
/// ui-ux-pro-max product guidance classifies this app as a productivity tool:
/// content remains flat/clear, while glass is limited to navigation and
/// overlays that have a meaningful backdrop.
abstract final class GuildVisualTheme {
  static ThemeData build(
    ColorScheme colors, {
    AppUiTexture texture = AppUiTexture.classic,
  }) {
    final dark = colors.brightness == Brightness.dark;
    final platform = defaultTargetPlatform;
    final liquidAndroid =
        texture == AppUiTexture.liquid && platform == TargetPlatform.android;
    final textureTheme = GuildTextureTheme(texture);
    final outline = colors.outlineVariant.withValues(alpha: dark ? 0.66 : 0.72);
    final innerOutline = colors.primary.withValues(alpha: dark ? 0.20 : 0.15);
    final raisedSurface = Color.alphaBlend(
      colors.primary.withValues(alpha: dark ? 0.035 : 0.018),
      colors.surface,
    );
    final selectedSurface = Color.alphaBlend(
      colors.primary.withValues(alpha: dark ? 0.18 : 0.11),
      colors.surfaceContainer,
    );
    final selectedForeground = Color.alphaBlend(
      colors.onSurface.withValues(alpha: dark ? 0.48 : 0.53),
      colors.primary,
    );
    final dialogOutline = GuildDoubleOutline(
      outerColor: outline,
      innerColor: innerOutline,
      radius: 20,
    );
    final menuOutline = GuildDoubleOutline(
      outerColor: colors.primary.withValues(alpha: dark ? 0.42 : 0.34),
      innerColor: innerOutline,
      radius: 13,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      extensions: <ThemeExtension<dynamic>>[textureTheme],
      // Preserve the existing subtle guild tint. Texture modes do not replace
      // the user's palette with a new hard-coded color system.
      scaffoldBackgroundColor: Color.alphaBlend(
        colors.primary.withValues(alpha: dark ? 0.025 : 0.018),
        colors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.primary.withValues(alpha: 0.07),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // A normal AppBar has no backdrop layer to blur. Keep it opaque rather
        // than faking glass with a translucent fill.
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor:
            liquidAndroid ? colors.secondaryContainer : selectedSurface,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? selectedForeground
                : colors.onSurfaceVariant,
          ),
        ),
        height: 70,
      ),
      drawerTheme: const DrawerThemeData(),
      // Content surfaces stay opaque in every texture mode. This is the core
      // productivity-tool rule that the first glass pass violated.
      cardTheme: CardThemeData(
        color: raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.27 : 0.14),
        shape: dialogOutline,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.27 : 0.13),
        shape: menuOutline,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raisedSurface,
        modalBackgroundColor: raisedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          side: BorderSide(color: outline, width: 0.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          // Material 3 Expressive fallback for the non-Apple "liquid" mode.
          shape: liquidAndroid
              ? const WidgetStatePropertyAll(StadiumBorder())
              : null,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: liquidAndroid
              ? const WidgetStatePropertyAll(StadiumBorder())
              : null,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: dark ? 0.63 : 0.58),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: Color.alphaBlend(
          colors.primary.withValues(alpha: dark ? 0.025 : 0.012),
          colors.surfaceContainerLow,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
      ),
    );
  }
}

/// Glass chrome for navigation/overlay surfaces only.
///
/// [backdropAvailable] must be true only when actual app content exists behind
/// this widget. When false (for example the Windows side navigation), the
/// surface stays opaque and uses platform-aligned subtle depth instead of
/// pretending a blur/refraction exists.
class GuildGlassSurface extends StatelessWidget {
  const GuildGlassSurface({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.backgroundColor,
    this.backdropAvailable = true,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? backgroundColor;
  final bool backdropAvailable;

  @override
  Widget build(BuildContext context) {
    final texture = GuildTextureTheme.of(context);
    if (!texture.enabled) return child;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final platform = theme.platform;
    final canBlur = backdropAvailable && texture.blurSigma > 0;
    final opacity = canBlur ? texture.overlayOpacity(platform) : 1.0;
    final base = (backgroundColor ?? colors.surfaceContainer).withValues(
      alpha: opacity,
    );

    // No decorative highlight gradients and no synthetic refraction.
    // Liquid Glass is native to Apple platforms; Android/Windows use their
    // platform-aligned material treatment instead.
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: borderRadius,
        border: Border.all(
          color: colors.outlineVariant.withValues(
            alpha: dark ? 0.58 : 0.72,
          ),
          width: 0.8,
        ),
      ),
      child: child,
    );

    if (canBlur) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: texture.blurSigma,
          sigmaY: texture.blurSigma,
        ),
        child: surface,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: surface,
    );
  }
}

/// Two restrained strokes paint *inside* the existing shape bounds. The
/// border has zero dimensions so it never adds padding to a dialog or menu.
class GuildDoubleOutline extends ShapeBorder {
  const GuildDoubleOutline({
    required this.outerColor,
    required this.innerColor,
    required this.radius,
    this.inset = 3,
  });

  final Color outerColor;
  final Color innerColor;
  final double radius;
  final double inset;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: outerColor, width: 0.8),
    ).paint(canvas, rect, textDirection: textDirection);

    if (rect.width <= inset * 2 || rect.height <= inset * 2) return;
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        (radius > inset ? radius - inset : 0.0),
      ),
      side: BorderSide(color: innerColor, width: 0.7),
    ).paint(
      canvas,
      rect.deflate(inset),
      textDirection: textDirection,
    );
  }

  @override
  ShapeBorder scale(double t) => GuildDoubleOutline(
    outerColor: outerColor,
    innerColor: innerColor,
    radius: radius * t,
    inset: inset * t,
  );
}
