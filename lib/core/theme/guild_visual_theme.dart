import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_ui_texture.dart';

class GuildTextureTheme extends ThemeExtension<GuildTextureTheme> {
  const GuildTextureTheme(this.texture);

  final AppUiTexture texture;

  bool get enabled => texture.isGlass;

  double get blurSigma => switch (texture) {
    AppUiTexture.classic => 0,
    AppUiTexture.frosted => 10,
    AppUiTexture.liquid => 16,
  };

  double get surfaceOpacity => switch (texture) {
    AppUiTexture.classic => 1,
    AppUiTexture.frosted => 0.78,
    AppUiTexture.liquid => 0.62,
  };

  double get strongSurfaceOpacity => switch (texture) {
    AppUiTexture.classic => 1,
    AppUiTexture.frosted => 0.88,
    AppUiTexture.liquid => 0.74,
  };

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

/// Visual-only theme tokens. Existing widget dimensions, icons and callbacks
/// remain the responsibility of their original components.
abstract final class GuildVisualTheme {
  static ThemeData build(
    ColorScheme colors, {
    AppUiTexture texture = AppUiTexture.classic,
  }) {
    final dark = colors.brightness == Brightness.dark;
    final textureTheme = GuildTextureTheme(texture);
    final glass = texture.isGlass;
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
    final glassSurface = raisedSurface.withValues(
      alpha: textureTheme.strongSurfaceOpacity,
    );
    final glassNavigation = Color.alphaBlend(
      colors.primary.withValues(alpha: dark ? 0.075 : 0.045),
      colors.surfaceContainer,
    ).withValues(alpha: textureTheme.strongSurfaceOpacity);
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
      // A hint of palette tint, not a parchment texture or a second surface.
      scaffoldBackgroundColor: Color.alphaBlend(
        colors.primary.withValues(alpha: dark ? 0.025 : 0.018),
        colors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.primary.withValues(alpha: 0.07),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: glass ? glassSurface : colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: glass ? glassNavigation : colors.surfaceContainer,
        indicatorColor: selectedSurface,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? selectedForeground
                : colors.onSurfaceVariant,
          ),
        ),
        height: 70,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: glass ? Colors.transparent : colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: glass ? glassSurface : raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glass ? glassSurface : raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.27 : 0.14),
        shape: dialogOutline,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: glass ? glassSurface : raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.27 : 0.13),
        shape: menuOutline,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glass ? glassSurface : raisedSurface,
        modalBackgroundColor: glass ? glassSurface : raisedSurface,
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
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
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

class GuildGlassSurface extends StatelessWidget {
  const GuildGlassSurface({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.backgroundColor,
    this.blur = true,
    this.paintHighlight = true,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? backgroundColor;
  final bool blur;
  final bool paintHighlight;

  @override
  Widget build(BuildContext context) {
    final texture = GuildTextureTheme.of(context);
    if (!texture.enabled) return child;

    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = (backgroundColor ?? colors.surface).withValues(
      alpha: texture.surfaceOpacity,
    );

    final decoration = BoxDecoration(
      color: base,
      borderRadius: borderRadius,
      border: Border.all(
        color: Color.alphaBlend(
          colors.primary.withValues(
            alpha: texture.texture == AppUiTexture.liquid
                ? (dark ? 0.28 : 0.22)
                : (dark ? 0.20 : 0.16),
          ),
          colors.outlineVariant.withValues(alpha: dark ? 0.68 : 0.58),
        ),
        width: 0.8,
      ),
      gradient: !paintHighlight
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: texture.texture == AppUiTexture.liquid
                  ? <Color>[
                      colors.onSurface.withValues(alpha: dark ? 0.09 : 0.14),
                      colors.primary.withValues(alpha: dark ? 0.08 : 0.065),
                      Colors.transparent,
                    ]
                  : <Color>[
                      colors.onSurface.withValues(alpha: dark ? 0.035 : 0.07),
                      colors.primary.withValues(alpha: dark ? 0.035 : 0.025),
                      Colors.transparent,
                    ],
              stops: const <double>[0, 0.42, 1],
            ),
    );

    Widget surface = DecoratedBox(
      decoration: decoration,
      child: child,
    );

    if (blur) {
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
