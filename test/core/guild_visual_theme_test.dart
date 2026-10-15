import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/core/theme/app_ui_style.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';
import 'package:flutter_app/features/shared/presentation/summary_card_widgets.dart';

void main() {
  test('refined classic borders do not consume layout space', () {
    const border = GuildDoubleOutline(
      outerColor: Colors.green,
      innerColor: Colors.grey,
      radius: 18,
    );
    expect(border.dimensions, EdgeInsets.zero);
    expect(
      border.getOuterPath(const Rect.fromLTWH(0, 0, 200, 100)).getBounds(),
      const Rect.fromLTWH(0, 0, 200, 100),
    );
  });

  testWidgets('classic compact card keeps its original geometry', (
    tester,
  ) async {
    final childKey = GlobalKey();
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    await tester.pumpWidget(
      MaterialApp(
        theme: GuildVisualTheme.build(scheme),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SummaryCardSurface(
              compact: true,
              onTap: () {},
              child: SizedBox(key: childKey, width: 72, height: 26),
            ),
          ),
        ),
      ),
    );

    final card = tester.getRect(find.byType(SummaryCardSurface));
    final inner = tester.getRect(find.byKey(childKey));
    expect(inner.left - card.left, 13);
    expect(inner.top - card.top, 13);
    expect(card.size, const Size(98, 52));
  });

  test('twelve UI style presets are available with the agreed labels', () {
    expect(
      AppUiStyle.values.map((style) => style.label).toList(),
      <String>[
        '经典',
        '浮雕',
        '极简',
        '粗边',
        '几何',
        '复古浅色',
        '复古深色',
        '荧光',
        '拼贴',
        '黑白',
        '黏土',
        '玻璃',
      ],
    );
  });

  test('every UI style keeps the selected theme color as primary', () {
    expect(AppThemePalettes.all.length, 17);
    for (final palette in AppThemePalettes.all) {
      final scheme = ColorScheme.fromSeed(seedColor: palette.lightSeed);
      for (final style in AppUiStyle.values) {
        final theme = GuildVisualTheme.build(scheme, style: style);
        expect(
          theme.colorScheme.primary,
          scheme.primary,
          reason: 'UI style must keep the selected theme color',
        );
      }
    }
  });

  test('document-backed presets expose visibly different surface tokens', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final relief = GuildVisualTheme.build(
      scheme,
      style: AppUiStyle.relief,
    ).extension<GuildStyleTheme>()!;
    final bold = GuildVisualTheme.build(
      scheme,
      style: AppUiStyle.bold,
    ).extension<GuildStyleTheme>()!;
    final clay = GuildVisualTheme.build(
      scheme,
      style: AppUiStyle.clay,
    ).extension<GuildStyleTheme>()!;
    final glass = GuildVisualTheme.build(
      scheme,
      style: AppUiStyle.glass,
    ).extension<GuildStyleTheme>()!;

    expect(relief.shadows.length, 2);
    expect(bold.borderWidth, greaterThanOrEqualTo(3));
    expect(bold.cardRadius, 0);
    expect(clay.cardRadius, greaterThanOrEqualTo(20));
    expect(glass.glassBlur, greaterThanOrEqualTo(16));
    expect(glass.glassOpacity, lessThan(0.8));
  });

  test('named retro variants keep their intended light and dark bases', () {
    final lightInput = ColorScheme.fromSeed(seedColor: Colors.teal);
    final darkInput = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );

    expect(
      GuildVisualTheme.build(
        darkInput,
        style: AppUiStyle.retroLight,
      ).brightness,
      Brightness.light,
    );
    expect(
      GuildVisualTheme.build(
        lightInput,
        style: AppUiStyle.retroDark,
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('glass surface blurs only when a backdrop is available', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    await tester.pumpWidget(
      MaterialApp(
        theme: GuildVisualTheme.build(scheme, style: AppUiStyle.glass),
        home: const Scaffold(
          body: GuildStyledSurface(
            backdropAvailable: false,
            child: SizedBox(width: 100, height: 50),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: GuildVisualTheme.build(scheme, style: AppUiStyle.glass),
        home: const Scaffold(
          body: GuildStyledSurface(
            backdropAvailable: true,
            child: SizedBox(width: 100, height: 50),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    test('classic controls remain unchanged for brightness mode', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      );
      final theme = GuildVisualTheme.build(scheme);
      expect(theme.navigationBarTheme.height, 70);
      expect(theme.dialogTheme.shape, isA<GuildDoubleOutline>());
      expect(theme.popupMenuTheme.shape, isA<GuildDoubleOutline>());
      expect(theme.filledButtonTheme.style!.elevation!.resolve({}), 0);
      expect(theme.elevatedButtonTheme.style!.elevation!.resolve({}), 0);
      expect(theme.colorScheme.primary, scheme.primary);
      expect(
        theme.extension<GuildStyleTheme>()!.style,
        AppUiStyle.classic,
      );
    });
  }
}
