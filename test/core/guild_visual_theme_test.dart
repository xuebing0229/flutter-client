import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/features/shared/presentation/summary_card_widgets.dart';

void main() {
  test('refined borders do not consume dialog or menu layout space', () {
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

  testWidgets('compact card keeps its original 12 px content insets', (tester) async {
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
    expect(inner.left - card.left, 12);
    expect(inner.top - card.top, 12);
    expect(card.size, const Size(96, 50));
  });

  test('all existing palette definitions remain available', () {
    expect(AppThemePalettes.all.length, 17);
    for (final palette in AppThemePalettes.all) {
      final scheme = ColorScheme.fromSeed(seedColor: palette.lightSeed);
      expect(GuildVisualTheme.build(scheme).colorScheme.primary, scheme.primary);
    }
  });

  for (final brightness in Brightness.values) {
    test('visual tokens preserve controls for ${brightness.name}', () {
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
    });
  }
}
