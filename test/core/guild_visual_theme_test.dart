import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';

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
