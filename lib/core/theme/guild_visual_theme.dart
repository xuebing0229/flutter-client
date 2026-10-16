import 'package:flutter/material.dart';

import 'app_theme_palette.dart';
import 'app_ui_style.dart';
import 'guild_style_effects.dart';

enum GuildSurfaceRole { content, chrome, inset, emphasized }

class GuildStyleTheme extends ThemeExtension<GuildStyleTheme> {
  const GuildStyleTheme({
    required this.style,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.foreground,
    required this.mutedForeground,
    required this.ink,
    required this.accent2,
    required this.accent3,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.cardRadius,
    required this.shadows,
    required this.chromeShadows,
    required this.glassBlur,
    required this.glassOpacity,
  });

  final AppUiStyle style;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color foreground;
  final Color mutedForeground;
  final Color ink;
  final Color accent2;
  final Color accent3;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final double cardRadius;
  final List<BoxShadow> shadows;
  final List<BoxShadow> chromeShadows;
  final double glassBlur;
  final double glassOpacity;

  bool get isClassic => style.isClassic;
  bool get isGlass => style.isGlass;

  static GuildStyleTheme of(BuildContext context) =>
      Theme.of(context).extension<GuildStyleTheme>() ??
      _fallback(Theme.of(context).colorScheme);

  static GuildStyleTheme _fallback(ColorScheme colors) {
    return GuildStyleTheme(
      style: AppUiStyle.classic,
      background: colors.surface,
      surface: colors.surface,
      surfaceAlt: colors.surfaceContainer,
      foreground: colors.onSurface,
      mutedForeground: colors.onSurfaceVariant,
      ink: colors.onSurface,
      accent2: colors.secondary,
      accent3: colors.tertiary,
      borderColor: colors.outlineVariant,
      borderWidth: 1,
      radius: 16,
      cardRadius: 20,
      shadows: const <BoxShadow>[],
      chromeShadows: const <BoxShadow>[],
      glassBlur: 0,
      glassOpacity: 1,
    );
  }

  BorderRadius get surfaceBorderRadius => BorderRadius.circular(radius);

  BorderRadius get cardBorderRadius => BorderRadius.circular(cardRadius);

  BorderRadius get buttonBorderRadius => BorderRadius.circular(
        switch (style) {
          AppUiStyle.classic => 12.0,
          AppUiStyle.relief => 12.0,
          AppUiStyle.minimal => 0.0,
          AppUiStyle.bold => 0.0,
          AppUiStyle.geometric => 2.0,
          AppUiStyle.retroLight => 4.0,
          AppUiStyle.retroDark => 4.0,
          AppUiStyle.fluorescent => radius,
          AppUiStyle.collage => 0.0,
          AppUiStyle.monochrome => 0.0,
          AppUiStyle.clay => 999.0,
          AppUiStyle.glass => 12.0,
        },
      );

  BorderRadius get inputBorderRadius => BorderRadius.circular(
        switch (style) {
          AppUiStyle.classic => 18.0,
          AppUiStyle.relief => 12.0,
          AppUiStyle.minimal => 0.0,
          AppUiStyle.bold => 0.0,
          AppUiStyle.geometric => 0.0,
          AppUiStyle.retroLight => 4.0,
          AppUiStyle.retroDark => 4.0,
          AppUiStyle.fluorescent => radius,
          AppUiStyle.collage => 0.0,
          AppUiStyle.monochrome => 0.0,
          AppUiStyle.clay => 20.0,
          AppUiStyle.glass => 12.0,
        },
      );

  BoxDecoration decoration({
    GuildSurfaceRole role = GuildSurfaceRole.content,
    BorderRadius? borderRadius,
    Color? backgroundColor,
  }) {
    final resolvedRadius = borderRadius ??
        (role == GuildSurfaceRole.content
            ? cardBorderRadius
            : surfaceBorderRadius);
    final base = backgroundColor ??
        (role == GuildSurfaceRole.inset ? surfaceAlt : surface);
    final border = borderWidth <= 0
        ? null
        : Border.all(color: borderColor, width: borderWidth);
    final roleShadows =
        role == GuildSurfaceRole.chrome ? chromeShadows : shadows;

    final gradient = switch (style) {
      AppUiStyle.clay => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _mix(base, Colors.white, 0.05),
            base,
          ],
        ),
      _ => null,
    };

    return BoxDecoration(
      color: gradient == null
          ? (style == AppUiStyle.glass
              ? Colors.white.withValues(
                  alpha: foreground.computeLuminance() < 0.35 ? 0.55 : 0.04,
                )
              : base)
          : null,
      gradient: gradient,
      borderRadius: resolvedRadius,
      border: border,
      boxShadow: roleShadows,
    );
  }

  @override
  GuildStyleTheme copyWith({
    AppUiStyle? style,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? foreground,
    Color? mutedForeground,
    Color? ink,
    Color? accent2,
    Color? accent3,
    Color? borderColor,
    double? borderWidth,
    double? radius,
    double? cardRadius,
    List<BoxShadow>? shadows,
    List<BoxShadow>? chromeShadows,
    double? glassBlur,
    double? glassOpacity,
  }) {
    return GuildStyleTheme(
      style: style ?? this.style,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      ink: ink ?? this.ink,
      accent2: accent2 ?? this.accent2,
      accent3: accent3 ?? this.accent3,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      radius: radius ?? this.radius,
      cardRadius: cardRadius ?? this.cardRadius,
      shadows: shadows ?? this.shadows,
      chromeShadows: chromeShadows ?? this.chromeShadows,
      glassBlur: glassBlur ?? this.glassBlur,
      glassOpacity: glassOpacity ?? this.glassOpacity,
    );
  }

  @override
  GuildStyleTheme lerp(
    covariant ThemeExtension<GuildStyleTheme>? other,
    double t,
  ) {
    if (other is! GuildStyleTheme) return this;
    return t < 0.5 ? this : other;
  }
}

abstract final class GuildVisualTheme {
  static ThemeData build(
    ColorScheme baseColors, {
    AppUiStyle style = AppUiStyle.classic,
    AppThemeSemanticColors? semanticColors,
  }) {
    if (style == AppUiStyle.classic) {
      return _buildClassic(
        baseColors,
        semanticColors: semanticColors,
      );
    }

    final resolved = _resolve(
      baseColors,
      style,
      semanticColors: semanticColors,
    );
    final colors = resolved.colors;
    final tokens = resolved.tokens;
    final selectedSurface = _mix(tokens.surfaceAlt, colors.primary, 0.20);
    final onPrimary = _contrast(colors.primary);
    final squareOrRounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radius),
      side: BorderSide(
        color: tokens.borderWidth > 0 ? tokens.borderColor : Colors.transparent,
        width: tokens.borderWidth,
      ),
    );
    final inputBorder = _inputBorder(tokens);
    final buttonSide = tokens.borderWidth > 0
        ? BorderSide(color: tokens.borderColor, width: tokens.borderWidth)
        : BorderSide.none;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_buttonRadius(style, tokens.radius)),
      side: buttonSide,
    );
    final filledBackground = _filledButtonBackground(style, tokens, colors);
    final filledForeground = _filledButtonForeground(style, tokens, colors);
    final filledSide = _filledButtonSide(style, tokens, colors);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      extensions: <ThemeExtension<dynamic>>[tokens],
      scaffoldBackgroundColor: tokens.background,
      splashColor: colors.primary.withValues(alpha: 0.12),
      highlightColor: colors.primary.withValues(alpha: 0.08),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: tokens.glassOpacity)
            : tokens.surface,
        foregroundColor: tokens.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: tokens.glassOpacity)
            : tokens.surface,
        indicatorColor: style == AppUiStyle.glass
            ? colors.primary.withValues(
                alpha: colors.brightness == Brightness.dark ? 0.18 : 0.15,
              )
            : selectedSurface,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            style == AppUiStyle.clay || style == AppUiStyle.relief
                ? 18
                : tokens.radius,
          ),
          side: style == AppUiStyle.bold ||
                  style == AppUiStyle.geometric ||
                  style == AppUiStyle.monochrome
              ? BorderSide(
                  color: tokens.borderColor,
                  width: tokens.borderWidth,
                )
              : BorderSide.none,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : tokens.mutedForeground,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? tokens.foreground
                : tokens.mutedForeground,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        height: 70,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor:
            style == AppUiStyle.glass ? Colors.transparent : tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(tokens.cardRadius),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: squareOrRounded,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: 0.72)
            : tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: _overlayElevation(style),
        shadowColor: _overlayShadow(style, tokens, colors),
        shape: squareOrRounded,
        titleTextStyle: TextStyle(
          color: tokens.foreground,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: 0.78)
            : tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: _overlayElevation(style),
        shadowColor: _overlayShadow(style, tokens, colors),
        shape: squareOrRounded,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: 0.76)
            : tokens.surface,
        modalBackgroundColor: style == AppUiStyle.glass
            ? tokens.surface.withValues(alpha: 0.76)
            : tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: _overlayElevation(style),
        modalElevation: _overlayElevation(style),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.cardRadius),
          ),
          side: buttonSide,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(filledBackground),
          foregroundColor: WidgetStatePropertyAll(filledForeground),
          side: WidgetStatePropertyAll(filledSide),
          elevation: WidgetStatePropertyAll(_buttonElevation(style)),
          shadowColor: WidgetStatePropertyAll(
            _buttonShadow(style, tokens, colors),
          ),
          surfaceTintColor:
              const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.surfaceAlt),
          foregroundColor: WidgetStatePropertyAll(tokens.foreground),
          elevation: WidgetStatePropertyAll(_buttonElevation(style)),
          shadowColor: WidgetStatePropertyAll(
            _buttonShadow(style, tokens, colors),
          ),
          surfaceTintColor:
              const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(tokens.foreground),
          side: WidgetStatePropertyAll(
            tokens.borderWidth > 0
                ? BorderSide(
                    color: tokens.borderColor,
                    width: tokens.borderWidth,
                  )
                : BorderSide(
                    color: colors.primary.withValues(alpha: 0.55),
                    width: 1,
                  ),
          ),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.primary),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor:
            style == AppUiStyle.glass ? filledBackground : colors.primary,
        foregroundColor:
            style == AppUiStyle.glass ? filledForeground : onPrimary,
        elevation: style == AppUiStyle.glass ? 0 : _buttonElevation(style),
        shape: style == AppUiStyle.glass
            ? RoundedRectangleBorder(
                borderRadius: tokens.buttonBorderRadius,
                side: filledSide,
              )
            : style == AppUiStyle.bold ||
                    style == AppUiStyle.geometric ||
                    style == AppUiStyle.monochrome
                ? squareOrRounded
                : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: style != AppUiStyle.minimal,
        fillColor: switch (style) {
          AppUiStyle.glass => colors.brightness == Brightness.light
              ? Colors.white.withValues(alpha: 0.50)
              : Colors.white.withValues(alpha: 0.05),
          AppUiStyle.relief => tokens.background,
          AppUiStyle.clay => tokens.background,
          AppUiStyle.collage => tokens.surface,
          _ => tokens.surfaceAlt,
        },
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: _focusedInputBorder(tokens, colors.primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: tokens.mutedForeground),
        labelStyle: TextStyle(color: tokens.mutedForeground),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _contrast(colors.primary)
              : tokens.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : tokens.surfaceAlt,
        ),
        trackOutlineColor: WidgetStatePropertyAll(
          tokens.borderWidth > 0
              ? tokens.borderColor
              : colors.outlineVariant,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onPrimary),
        side: BorderSide(
          color: tokens.borderColor,
          width: tokens.borderWidth <= 0 ? 1.2 : tokens.borderWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            style == AppUiStyle.clay ? 6 : 1,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : tokens.mutedForeground,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: tokens.surfaceAlt,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: tokens.surfaceAlt,
        circularTrackColor: tokens.surfaceAlt,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.borderColor.withValues(
          alpha: style == AppUiStyle.minimal ? 0.55 : 0.72,
        ),
        thickness: style == AppUiStyle.bold ||
                style == AppUiStyle.geometric ||
                style == AppUiStyle.monochrome
            ? 2
            : 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceAlt,
        selectedColor: selectedSurface,
        disabledColor: tokens.surfaceAlt.withValues(alpha: 0.55),
        labelStyle: TextStyle(color: tokens.foreground),
        secondaryLabelStyle: TextStyle(color: tokens.foreground),
        side: BorderSide(
          color: tokens.borderWidth > 0
              ? tokens.borderColor
              : Colors.transparent,
          width: tokens.borderWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: tokens.foreground,
        iconColor: tokens.mutedForeground,
        selectedColor: colors.primary,
        selectedTileColor: selectedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
      ),
      iconTheme: IconThemeData(color: tokens.foreground),
      textTheme: _textThemeFor(
        tokens,
        ThemeData(colorScheme: colors, useMaterial3: true).textTheme,
      ),
    );
  }

  static ThemeData _buildClassic(
    ColorScheme colors, {
    AppThemeSemanticColors? semanticColors,
  }) {
    final dark = colors.brightness == Brightness.dark;
    final outline = semanticColors?.border ??
        colors.outlineVariant.withValues(alpha: dark ? 0.66 : 0.72);
    final innerOutline =
        colors.primary.withValues(alpha: dark ? 0.20 : 0.15);
    final raisedSurface = semanticColors?.surface ??
        Color.alphaBlend(
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
    final tokens = GuildStyleTheme(
      style: AppUiStyle.classic,
      background: semanticColors?.background ??
          Color.alphaBlend(
            colors.primary.withValues(alpha: dark ? 0.025 : 0.018),
            colors.surface,
          ),
      surface: raisedSurface,
      surfaceAlt: semanticColors?.surfaceAlt ?? colors.surfaceContainer,
      foreground: semanticColors?.foreground ?? colors.onSurface,
      mutedForeground:
          semanticColors?.mutedForeground ?? colors.onSurfaceVariant,
      ink: semanticColors?.foreground ?? colors.onSurface,
      accent2: semanticColors?.accent ?? colors.secondary,
      accent3: colors.tertiary,
      borderColor: outline,
      borderWidth: 1,
      radius: 16,
      cardRadius: 20,
      shadows: const <BoxShadow>[],
      chromeShadows: const <BoxShadow>[],
      glassBlur: 0,
      glassOpacity: 1,
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
      extensions: <ThemeExtension<dynamic>>[tokens],
      scaffoldBackgroundColor: tokens.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.primary.withValues(alpha: 0.07),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: semanticColors?.surface ?? colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            semanticColors?.surfaceAlt ?? colors.surfaceContainer,
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
      drawerTheme: const DrawerThemeData(),
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
          side: BorderSide(color: outline, width: 0.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor:
              const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor:
              const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor:
              const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor:
              const WidgetStatePropertyAll(Colors.transparent),
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

  static _GuildResolvedStyle _resolve(
    ColorScheme base,
    AppUiStyle style, {
    AppThemeSemanticColors? semanticColors,
  }) {
    final brightness = style.forcesLight
        ? Brightness.light
        : style.forcesDark
            ? Brightness.dark
            : base.brightness;
    final dark = brightness == Brightness.dark;
    final primary = semanticColors?.primary ?? base.primary;
    final accent2 = semanticColors?.accent ??
        _rotateHue(primary, style == AppUiStyle.geometric ? 120 : 62);
    final accent3 = semanticColors == null
        ? _rotateHue(
            primary,
            style == AppUiStyle.fluorescent ? 180 : -58,
          )
        : _rotateHue(semanticColors.accent, -54);

    late Color background;
    late Color surface;
    late Color surfaceAlt;
    late Color foreground;
    late Color muted;
    late Color ink;
    late Color border;
    late double borderWidth;
    late double radius;
    late double cardRadius;
    late List<BoxShadow> shadows;
    late List<BoxShadow> chromeShadows;
    var glassBlur = 0.0;
    var glassOpacity = 1.0;

    switch (style) {
      case AppUiStyle.classic:
        throw StateError('Classic style is resolved by _buildClassic.');
      case AppUiStyle.relief:
        background = dark
            ? _mix(const Color(0xFF202630), primary, 0.025)
            : _mix(const Color(0xFFE0E5EC), primary, 0.018);
        surface = background;
        surfaceAlt = dark
            ? _mix(background, Colors.white, 0.045)
            : _mix(background, Colors.white, 0.06);
        foreground =
            dark ? const Color(0xFFE3E8F0) : const Color(0xFF5A6E86);
        muted = dark ? const Color(0xFF9AA9BA) : const Color(0xFF8FA3BD);
        ink = foreground;
        border = Colors.transparent;
        borderWidth = 0;
        radius = 16;
        cardRadius = 16;
        final lightShadow = dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.94);
        final darkShadow = dark
            ? Colors.black.withValues(alpha: 0.45)
            : const Color(0xFFA3B1C6).withValues(alpha: 0.82);
        shadows = <BoxShadow>[
          BoxShadow(
            color: darkShadow,
            offset: const Offset(6, 6),
            blurRadius: 12,
          ),
          BoxShadow(
            color: lightShadow,
            offset: const Offset(-6, -6),
            blurRadius: 12,
          ),
        ];
        chromeShadows = shadows;
      case AppUiStyle.minimal:
        background = dark ? const Color(0xFF121212) : const Color(0xFFF7F7F7);
        surface = background;
        surfaceAlt =
            dark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
        foreground =
            dark ? const Color(0xFFECECEC) : const Color(0xFF1A1A1A);
        muted = dark ? const Color(0xFF999999) : const Color(0xFF888888);
        ink = foreground;
        border = dark ? const Color(0xFF383838) : const Color(0xFFE2E2E2);
        // Minimal surfaces stay flat; input underlines and dividers use the
        // border color directly instead of drawing a box around every panel.
        borderWidth = 0;
        radius = 0;
        cardRadius = 0;
        shadows = const <BoxShadow>[];
        chromeShadows = const <BoxShadow>[];
      case AppUiStyle.bold:
        background =
            dark ? const Color(0xFF181818) : const Color(0xFFFFFDF7);
        surface = dark ? const Color(0xFF202020) : const Color(0xFFFFFFFF);
        surfaceAlt = _mix(surface, primary, dark ? 0.12 : 0.08);
        foreground =
            dark ? const Color(0xFFF7F7F7) : const Color(0xFF1A1A2E);
        muted = dark ? const Color(0xFFB0B0B0) : const Color(0xFF555555);
        ink = dark ? const Color(0xFFF4F4F4) : const Color(0xFF000000);
        border = ink;
        borderWidth = 3;
        radius = 0;
        cardRadius = 0;
        shadows = <BoxShadow>[
          BoxShadow(color: ink, offset: const Offset(5, 5)),
        ];
        chromeShadows = shadows;
      case AppUiStyle.geometric:
        background =
            dark ? const Color(0xFF191814) : const Color(0xFFF0EAD6);
        surface = dark ? const Color(0xFF24221C) : const Color(0xFFFFFFFF);
        surfaceAlt = _mix(surface, primary, dark ? 0.10 : 0.06);
        foreground =
            dark ? const Color(0xFFF5F0E4) : const Color(0xFF1A1A1A);
        muted = dark ? const Color(0xFFB0AA9B) : const Color(0xFF666666);
        ink = dark ? const Color(0xFFF5F0E4) : const Color(0xFF000000);
        border = ink;
        borderWidth = 3;
        radius = 0;
        cardRadius = 0;
        shadows = const <BoxShadow>[];
        chromeShadows = const <BoxShadow>[];
      case AppUiStyle.retroLight:
        background = const Color(0xFFF5F0E8);
        surface = const Color(0xFFEDE7DB);
        surfaceAlt = _mix(surface, primary, 0.07);
        foreground = const Color(0xFF1A1A2E);
        muted = const Color(0xFF6B5B7B);
        ink = foreground;
        border = _mix(const Color(0xFFC8BFB0), primary, 0.18);
        borderWidth = 2;
        radius = 8;
        cardRadius = 8;
        shadows = const <BoxShadow>[];
        chromeShadows = const <BoxShadow>[];
      case AppUiStyle.retroDark:
        background = _mix(const Color(0xFF0D0221), primary, 0.06);
        surface = Colors.black.withValues(alpha: 0.58);
        surfaceAlt = _mix(const Color(0xFF130A27), primary, 0.14);
        foreground = _mix(const Color(0xFFFFFFFF), accent2, 0.24);
        muted = _mix(const Color(0xFFBBBBCC), accent3, 0.20);
        ink = foreground;
        border = accent2.withValues(alpha: 0.44);
        borderWidth = 1;
        radius = 8;
        cardRadius = 8;
        shadows = <BoxShadow>[
          BoxShadow(
            color: accent2.withValues(alpha: 0.32),
            blurRadius: 14,
          ),
          BoxShadow(
            color: primary.withValues(alpha: 0.22),
            blurRadius: 28,
          ),
        ];
        chromeShadows = shadows;
      case AppUiStyle.fluorescent:
        // Acid Graphics has deliberately different light/dark component
        // geometry in the supplied references.
        background =
            dark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F0EB);
        surface =
            dark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
        surfaceAlt = dark
            ? _mix(surface, primary, 0.10)
            : const Color(0xFFFAFAF7);
        foreground = dark ? primary : const Color(0xFF1A1A1A);
        muted = dark
            ? _mix(primary, Colors.white, 0.35)
            : const Color(0xFF666666);
        ink = foreground;
        border = dark
            ? primary.withValues(alpha: 0.40)
            : const Color(0xFFD4D0C8);
        borderWidth = dark ? 1 : 2;
        radius = dark ? 1 : 0;
        cardRadius = radius;
        shadows = dark
            ? <BoxShadow>[
                BoxShadow(
                  color: primary.withValues(alpha: 0.30),
                  blurRadius: 12,
                ),
                BoxShadow(
                  color: accent3.withValues(alpha: 0.12),
                  blurRadius: 30,
                ),
              ]
            : const <BoxShadow>[];
        chromeShadows = shadows;
      case AppUiStyle.collage:
        background =
            dark ? const Color(0xFF1A1815) : const Color(0xFFF8F5F0);
        surface = dark ? const Color(0xFF25211E) : const Color(0xFFFFFFFF);
        surfaceAlt = dark
            ? _mix(surface, primary, 0.15)
            : _mix(const Color(0xFFE0DCD5), primary, 0.05);
        foreground =
            dark ? const Color(0xFFF7F1E8) : const Color(0xFF1A1A1A);
        muted = dark ? const Color(0xFFC1B8AD) : const Color(0xFF888888);
        ink = foreground;
        border = dark ? foreground.withValues(alpha: 0.78) : const Color(0xFFE0DCD5);
        borderWidth = 2;
        radius = 0;
        cardRadius = 0;
        shadows = const <BoxShadow>[];
        chromeShadows = <BoxShadow>[
          BoxShadow(color: primary, offset: const Offset(6, 6)),
          BoxShadow(color: accent2, offset: const Offset(-3, -3)),
        ];
      case AppUiStyle.monochrome:
        background =
            dark ? const Color(0xFF171717) : const Color(0xFFE5E5E5);
        surface = dark ? const Color(0xFF222222) : const Color(0xFFD4D4D4);
        surfaceAlt =
            dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5);
        foreground =
            dark ? const Color(0xFFE5E5E5) : const Color(0xFF2D2D2D);
        muted = dark ? const Color(0xFF999999) : const Color(0xFF666666);
        ink = foreground;
        border = foreground;
        borderWidth = 2;
        radius = 0;
        cardRadius = 0;
        shadows = const <BoxShadow>[];
        chromeShadows = const <BoxShadow>[];
      case AppUiStyle.clay:
        background = dark
            ? _mix(const Color(0xFF1C2130), primary, 0.025)
            : const Color(0xFFF0F4FF);
        surface = dark
            ? const Color(0xFF262D40)
            : const Color(0xFFFFFFFF);
        surfaceAlt = dark
            ? _mix(surface, primary, 0.14)
            : _mix(const Color(0xFFE8ECF5), primary, 0.04);
        foreground =
            dark ? const Color(0xFFF0F2FF) : const Color(0xFF3D3D5C);
        muted = dark ? const Color(0xFFA9ADC0) : const Color(0xFF8E8EA0);
        ink = foreground;
        border = Colors.transparent;
        borderWidth = 0;
        radius = 20;
        cardRadius = 24;
        shadows = <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.34 : 0.15),
            offset: const Offset(4, 6),
          ),
        ];
        chromeShadows = shadows;
      case AppUiStyle.glass:
        // Exact material values come from the supplied
        // liquid-glass-components(.light).html references. Theme colour stays
        // an accent; it must not recolour the glass base itself.
        background =
            dark ? const Color(0xFF0E0E1A) : const Color(0xFFF0EFF5);
        surface =
            dark ? const Color(0xFF0E0E1A) : const Color(0xFFFFFFFF);
        surfaceAlt =
            dark ? const Color(0xFF141420) : const Color(0xFFFFFFFF);
        foreground =
            dark ? const Color(0xFFE8E8F0) : const Color(0xFF1E1B3A);
        muted =
            dark ? const Color(0xFF8888A8) : const Color(0xFF7C7893);
        ink = foreground;
        border = dark
            ? Colors.white.withValues(alpha: 0.10)
            : primary.withValues(alpha: 0.12);
        borderWidth = 1;
        radius = 16;
        cardRadius = 16;
        shadows = <BoxShadow>[
          BoxShadow(
            color: primary.withValues(alpha: dark ? 0.16 : 0.08),
            offset: Offset(0, dark ? 0 : 4),
            blurRadius: dark ? 10 : 16,
          ),
        ];
        chromeShadows = shadows;
        glassBlur = dark ? 12 : 16;
        glassOpacity = dark ? 0.04 : 0.55;
    }

    if (semanticColors != null) {
      // Custom palettes choose semantic colours while the selected UI style
      // still owns geometry, blur, shadows and component treatment.
      background = semanticColors.background;
      surface = semanticColors.surface;
      surfaceAlt = semanticColors.surfaceAlt;
      foreground = semanticColors.foreground;
      muted = semanticColors.mutedForeground;
      ink = semanticColors.foreground;
      border = semanticColors.border;
    }

    final colors = base.copyWith(
      brightness: brightness,
      primary: primary,
      onPrimary: _contrast(primary),
      primaryContainer: _mix(surfaceAlt, primary, dark ? 0.28 : 0.18),
      onPrimaryContainer: foreground,
      secondary: accent2,
      onSecondary: _contrast(accent2),
      secondaryContainer: _mix(surfaceAlt, accent2, dark ? 0.24 : 0.15),
      onSecondaryContainer: foreground,
      tertiary: accent3,
      onTertiary: _contrast(accent3),
      tertiaryContainer: _mix(surfaceAlt, accent3, dark ? 0.22 : 0.14),
      onTertiaryContainer: foreground,
      surface: surface,
      onSurface: foreground,
      surfaceContainerLowest: background,
      surfaceContainerLow: _mix(background, surface, 0.45),
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh:
          _mix(surfaceAlt, foreground, dark ? 0.06 : 0.035),
      surfaceContainerHighest:
          _mix(surfaceAlt, foreground, dark ? 0.10 : 0.065),
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: _mix(border, background, 0.35),
      inverseSurface: foreground,
      onInverseSurface: background,
      inversePrimary: primary,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return _GuildResolvedStyle(
      colors: colors,
      tokens: GuildStyleTheme(
        style: style,
        background: background,
        surface: surface,
        surfaceAlt: surfaceAlt,
        foreground: foreground,
        mutedForeground: muted,
        ink: ink,
        accent2: accent2,
        accent3: accent3,
        borderColor: border,
        borderWidth: borderWidth,
        radius: radius,
        cardRadius: cardRadius,
        shadows: shadows,
        chromeShadows: chromeShadows,
        glassBlur: glassBlur,
        glassOpacity: glassOpacity,
      ),
    );
  }

  static InputBorder _inputBorder(GuildStyleTheme tokens) {
    if (tokens.style == AppUiStyle.minimal) {
      return UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.borderColor, width: 1),
      );
    }
    if (tokens.borderWidth <= 0) {
      return OutlineInputBorder(
        borderRadius: tokens.inputBorderRadius,
        borderSide: BorderSide.none,
      );
    }
    return OutlineInputBorder(
      borderRadius: tokens.inputBorderRadius,
      borderSide: BorderSide(
        color: tokens.borderColor,
        width: tokens.borderWidth,
      ),
    );
  }

  static InputBorder _focusedInputBorder(
    GuildStyleTheme tokens,
    Color primary,
  ) {
    if (tokens.style == AppUiStyle.minimal) {
      return UnderlineInputBorder(
        borderSide: BorderSide(color: primary, width: 2),
      );
    }
    if (tokens.style == AppUiStyle.relief ||
        tokens.style == AppUiStyle.clay) {
      return OutlineInputBorder(
        borderRadius: tokens.inputBorderRadius,
        borderSide: BorderSide.none,
      );
    }
    if (tokens.style == AppUiStyle.glass) {
      return OutlineInputBorder(
        borderRadius: tokens.inputBorderRadius,
        borderSide: BorderSide(
          color: primary.withValues(alpha: 0.35),
          width: 1,
        ),
      );
    }
    return OutlineInputBorder(
      borderRadius: tokens.inputBorderRadius,
      borderSide: BorderSide(
        color: primary,
        width: tokens.borderWidth <= 0 ? 1.5 : tokens.borderWidth,
      ),
    );
  }

  static Color _filledButtonBackground(
    AppUiStyle style,
    GuildStyleTheme tokens,
    ColorScheme colors,
  ) {
    return switch (style) {
      AppUiStyle.relief => tokens.background,
      AppUiStyle.minimal => Colors.transparent,
      AppUiStyle.retroLight ||
      AppUiStyle.retroDark ||
      AppUiStyle.fluorescent => Colors.transparent,
      AppUiStyle.monochrome => tokens.foreground,
      AppUiStyle.glass => colors.primary.withValues(
          alpha: colors.brightness == Brightness.dark ? 0.25 : 0.15,
        ),
      _ => colors.primary,
    };
  }

  static Color _filledButtonForeground(
    AppUiStyle style,
    GuildStyleTheme tokens,
    ColorScheme colors,
  ) {
    return switch (style) {
      AppUiStyle.relief ||
      AppUiStyle.minimal ||
      AppUiStyle.retroLight ||
      AppUiStyle.retroDark ||
      AppUiStyle.fluorescent => colors.primary,
      AppUiStyle.monochrome => tokens.background,
      AppUiStyle.glass => tokens.foreground,
      _ => _contrast(colors.primary),
    };
  }

  static BorderSide _filledButtonSide(
    AppUiStyle style,
    GuildStyleTheme tokens,
    ColorScheme colors,
  ) {
    return switch (style) {
      AppUiStyle.bold ||
      AppUiStyle.geometric => BorderSide(
          color: tokens.borderColor,
          width: tokens.borderWidth,
        ),
      AppUiStyle.retroLight => BorderSide(
          color: colors.primary,
          width: 2,
        ),
      AppUiStyle.retroDark => BorderSide(
          color: colors.primary.withValues(alpha: 0.85),
          width: 1,
        ),
      AppUiStyle.fluorescent => BorderSide(
          color: colors.primary,
          width: tokens.borderWidth,
        ),
      AppUiStyle.collage => BorderSide(
          color: colors.primary,
          width: 2,
        ),
      AppUiStyle.monochrome => BorderSide(
          color: tokens.foreground,
          width: 1,
        ),
      AppUiStyle.glass => BorderSide(
          color: colors.primary.withValues(
            alpha: colors.brightness == Brightness.dark ? 0.35 : 0.25,
          ),
          width: 1,
        ),
      _ => BorderSide.none,
    };
  }

  static double _buttonRadius(AppUiStyle style, double fallback) {
    return switch (style) {
      AppUiStyle.relief => 12,
      AppUiStyle.minimal => 0,
      AppUiStyle.bold => 0,
      AppUiStyle.geometric => 2,
      AppUiStyle.retroLight => 4,
      AppUiStyle.retroDark => 4,
      AppUiStyle.fluorescent => fallback,
      AppUiStyle.collage => 0,
      AppUiStyle.monochrome => 0,
      AppUiStyle.clay => 999,
      AppUiStyle.glass => 12,
      AppUiStyle.classic => fallback,
    };
  }

  static double _buttonElevation(AppUiStyle style) {
    return switch (style) {
      AppUiStyle.relief => 5,
      AppUiStyle.bold => 4,
      AppUiStyle.geometric => 0,
      AppUiStyle.collage => 0,
      AppUiStyle.clay => 5,
      AppUiStyle.glass => 0,
      _ => 0,
    };
  }

  static double _overlayElevation(AppUiStyle style) {
    return switch (style) {
      AppUiStyle.relief => 6,
      AppUiStyle.bold => 4,
      AppUiStyle.geometric => 3,
      AppUiStyle.retroDark => 5,
      AppUiStyle.fluorescent => 5,
      AppUiStyle.collage => 4,
      AppUiStyle.clay => 6,
      AppUiStyle.glass => 8,
      _ => 0,
    };
  }

  static Color _buttonShadow(
    AppUiStyle style,
    GuildStyleTheme tokens,
    ColorScheme colors,
  ) {
    return switch (style) {
      AppUiStyle.relief => const Color(0xFFA3B1C6),
      AppUiStyle.bold => tokens.ink,
      AppUiStyle.geometric => tokens.ink,
      AppUiStyle.retroDark => tokens.accent2.withValues(alpha: 0.56),
      AppUiStyle.fluorescent => colors.primary.withValues(alpha: 0.64),
      AppUiStyle.collage => colors.primary,
      AppUiStyle.clay => Colors.black.withValues(alpha: 0.22),
      AppUiStyle.glass => Colors.black.withValues(alpha: 0.24),
      _ => Colors.transparent,
    };
  }

  static Color _overlayShadow(
    AppUiStyle style,
    GuildStyleTheme tokens,
    ColorScheme colors,
  ) {
    return switch (style) {
      AppUiStyle.retroDark => tokens.accent2.withValues(alpha: 0.42),
      AppUiStyle.fluorescent => colors.primary.withValues(alpha: 0.44),
      AppUiStyle.collage => colors.primary.withValues(alpha: 0.50),
      AppUiStyle.glass => Colors.black.withValues(alpha: 0.34),
      _ => Colors.black.withValues(alpha: 0.22),
    };
  }

  static TextTheme _textThemeFor(
    GuildStyleTheme tokens,
    TextTheme base,
  ) {
    final shadows = switch (tokens.style) {
      AppUiStyle.retroDark => <Shadow>[
          Shadow(
            color: tokens.accent2.withValues(alpha: 0.48),
            blurRadius: 7,
          ),
        ],
      // Liquid Glass keeps typography crisp; blur belongs behind the glass.
      // Acid Graphics only glows selected accent labels/controls in the
      // supplied reference, not the entire app text hierarchy.
      AppUiStyle.fluorescent || AppUiStyle.glass => const <Shadow>[],
      _ => const <Shadow>[],
    };

    TextStyle? color(TextStyle? style, {bool muted = false}) =>
        style?.copyWith(
          color: muted ? tokens.mutedForeground : tokens.foreground,
          shadows: shadows,
        );
    return base.copyWith(
      displayLarge: color(base.displayLarge),
      displayMedium: color(base.displayMedium),
      displaySmall: color(base.displaySmall),
      headlineLarge: color(base.headlineLarge),
      headlineMedium: color(base.headlineMedium),
      headlineSmall: color(base.headlineSmall),
      titleLarge: color(base.titleLarge),
      titleMedium: color(base.titleMedium),
      titleSmall: color(base.titleSmall),
      bodyLarge: color(base.bodyLarge),
      bodyMedium: color(base.bodyMedium),
      bodySmall: color(base.bodySmall, muted: true),
      labelLarge: color(base.labelLarge),
      labelMedium: color(base.labelMedium),
      labelSmall: color(base.labelSmall, muted: true),
    );
  }
}

class GuildStyledSurface extends StatelessWidget {
  const GuildStyledSurface({
    required this.child,
    this.role = GuildSurfaceRole.content,
    this.borderRadius,
    this.backgroundColor,
    this.backdropAvailable = false,
    super.key,
  });

  final Widget child;
  final GuildSurfaceRole role;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final bool backdropAvailable;

  @override
  Widget build(BuildContext context) {
    final tokens = GuildStyleTheme.of(context);
    if (tokens.isClassic) return child;

    final colors = Theme.of(context).colorScheme;
    final resolvedRadius = borderRadius ??
        (role == GuildSurfaceRole.content
            ? tokens.cardBorderRadius
            : tokens.surfaceBorderRadius);

    return GuildSurfaceEffect(
      style: tokens.style,
      role: switch (role) {
        GuildSurfaceRole.content => GuildEffectRole.content,
        GuildSurfaceRole.chrome => GuildEffectRole.chrome,
        GuildSurfaceRole.inset => GuildEffectRole.inset,
        GuildSurfaceRole.emphasized => GuildEffectRole.emphasized,
      },
      primary: colors.primary,
      accent2: tokens.accent2,
      accent3: tokens.accent3,
      background: tokens.background,
      surface: backgroundColor ??
          (role == GuildSurfaceRole.inset
              ? tokens.surfaceAlt
              : tokens.surface),
      surfaceAlt: tokens.surfaceAlt,
      foreground: tokens.foreground,
      borderColor: tokens.borderColor,
      borderWidth: tokens.borderWidth,
      borderRadius: resolvedRadius,
      shadows: role == GuildSurfaceRole.chrome
          ? tokens.chromeShadows
          : tokens.shadows,
      glassBlur: tokens.glassBlur,
      glassOpacity: tokens.glassOpacity,
      backdropAvailable: backdropAvailable,
      child: child,
    );
  }
}

class GuildContentPanel extends StatelessWidget {
  const GuildContentPanel({
    required this.child,
    this.role = GuildSurfaceRole.content,
    this.classicRadius = 18,
    this.backgroundColor,
    this.backdropAvailable,
    super.key,
  });

  final Widget child;
  final GuildSurfaceRole role;
  final double classicRadius;
  final Color? backgroundColor;
  final bool? backdropAvailable;

  @override
  Widget build(BuildContext context) {
    final style = GuildStyleTheme.of(context);
    final radius = style.isClassic
        ? BorderRadius.circular(classicRadius)
        : role == GuildSurfaceRole.content
            ? style.cardBorderRadius
            : style.surfaceBorderRadius;
    final color = backgroundColor ?? Theme.of(context).colorScheme.surface;

    return GuildStyledSurface(
      role: role,
      borderRadius: radius,
      backgroundColor: color,
      backdropAvailable: backdropAvailable ?? style.isGlass,
      child: Material(
        color: style.isClassic ? color : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: radius,
        child: child,
      ),
    );
  }
}

class GuildStyleBackdrop extends StatelessWidget {
  const GuildStyleBackdrop({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = GuildStyleTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    if (tokens.isClassic) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[
              Color.alphaBlend(
                colors.primary.withValues(alpha: 0.045),
                Theme.of(context).scaffoldBackgroundColor,
              ),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: child,
      );
    }

    return GuildBackdropEffect(
      style: tokens.style,
      primary: colors.primary,
      accent2: tokens.accent2,
      accent3: tokens.accent3,
      background: tokens.background,
      child: child,
    );
  }
}

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
        radius > inset ? radius - inset : 0.0,
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

class _GuildResolvedStyle {
  const _GuildResolvedStyle({
    required this.colors,
    required this.tokens,
  });

  final ColorScheme colors;
  final GuildStyleTheme tokens;
}

Color _mix(Color base, Color overlay, double amount) {
  return Color.lerp(base, overlay, amount.clamp(0.0, 1.0).toDouble()) ?? base;
}

Color _rotateHue(Color color, double degrees) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withHue((hsl.hue + degrees) % 360)
      .withSaturation((hsl.saturation * 1.04).clamp(0.0, 1.0).toDouble())
      .toColor();
}

Color _contrast(Color color) {
  return color.computeLuminance() > 0.47 ? Colors.black : Colors.white;
}
