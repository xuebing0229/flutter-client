import 'package:flutter/material.dart';

/// Visual-only theme tokens. Existing widget dimensions, icons and callbacks
/// remain the responsibility of their original components.
abstract final class GuildVisualTheme {
  static ThemeData build(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
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
      // A hint of palette tint, not a parchment texture or a second surface.
      scaffoldBackgroundColor: Color.alphaBlend(
        colors.primary.withValues(alpha: dark ? 0.025 : 0.018),
        colors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.primary.withValues(alpha: 0.07),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
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
