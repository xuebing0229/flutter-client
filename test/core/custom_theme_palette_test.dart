import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/core/theme/app_ui_style.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';
import 'package:flutter_app/core/theme/theme_palette_transfer.dart';

void main() {
  test('custom semantic palette survives json round trip', () {
    const light = AppThemeSemanticColors(
      primary: Color(0xff336699),
      accent: Color(0xffcc6688),
      background: Color(0xfff6f4ef),
      surface: Color(0xffffffff),
      surfaceAlt: Color(0xffeeeae1),
      foreground: Color(0xff202124),
      mutedForeground: Color(0xff6b6f76),
      border: Color(0xffc8c4ba),
    );
    const dark = AppThemeSemanticColors(
      primary: Color(0xff7bb7ff),
      accent: Color(0xffff8fb0),
      background: Color(0xff111318),
      surface: Color(0xff1b1d23),
      surfaceAlt: Color(0xff272a31),
      foreground: Color(0xfff0f1f4),
      mutedForeground: Color(0xffa9adb7),
      border: Color(0xff454954),
    );

    final palette = AppThemePalette.custom(
      id: 'custom:test',
      name: '测试配色',
      seed: const Color(0xff336699),
      light: light,
      dark: dark,
      advanced: true,
    );

    final decoded = AppThemePalette.fromCustomJson(palette.toCustomJson());
    expect(decoded, isNotNull);
    expect(decoded!.id, 'custom:test');
    expect(decoded.name, '测试配色');
    expect(decoded.customAdvanced, isTrue);
    expect(decoded.lightSemanticColors?.primary, light.primary);
    expect(decoded.lightSemanticColors?.surfaceAlt, light.surfaceAlt);
    expect(decoded.darkSemanticColors?.background, dark.background);
    expect(decoded.darkSemanticColors?.border, dark.border);
  });

  test('custom semantic colors feed styles without replacing geometry', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    const semantic = AppThemeSemanticColors(
      primary: Color(0xff805ad5),
      accent: Color(0xffd95f9f),
      background: Color(0xfff8f2ff),
      surface: Color(0xfffffbff),
      surfaceAlt: Color(0xffeee3f7),
      foreground: Color(0xff24172f),
      mutedForeground: Color(0xff76677f),
      border: Color(0xffcbbbd4),
    );

    final theme = GuildVisualTheme.build(
      scheme.copyWith(primary: semantic.primary),
      style: AppUiStyle.glass,
      semanticColors: semantic,
    );
    final tokens = theme.extension<GuildStyleTheme>()!;

    expect(theme.colorScheme.primary, semantic.primary);
    expect(theme.colorScheme.secondary, semantic.accent);
    expect(tokens.background, semantic.background);
    expect(tokens.surface, semantic.surface);
    expect(tokens.surfaceAlt, semantic.surfaceAlt);
    expect(tokens.foreground, semantic.foreground);
    expect(tokens.mutedForeground, semantic.mutedForeground);
    expect(tokens.borderColor, semantic.border);

    // Geometry/material still belongs to the selected style.
    expect(tokens.cardRadius, 16);
    expect(tokens.glassBlur, 16);
  });

  test('basic custom colors generate separate light and dark semantics', () {
    const seed = Color(0xff4f7ac8);
    final light = AppThemeSemanticColors.fromSeed(seed, Brightness.light);
    final dark = AppThemeSemanticColors.fromSeed(seed, Brightness.dark);

    expect(light.primary, isNot(equals(dark.primary)));
    expect(
      light.background.computeLuminance(),
      greaterThan(dark.background.computeLuminance()),
    );
    expect(
      light.foreground.computeLuminance(),
      lessThan(dark.foreground.computeLuminance()),
    );
  });

  test('shared theme file omits local id and round trips colors', () {
    const light = AppThemeSemanticColors(
      primary: Color(0xff336699),
      accent: Color(0xffcc6688),
      background: Color(0xfff6f4ef),
      surface: Color(0xffffffff),
      surfaceAlt: Color(0xffeeeae1),
      foreground: Color(0xff202124),
      mutedForeground: Color(0xff6b6f76),
      border: Color(0xffc8c4ba),
    );
    const dark = AppThemeSemanticColors(
      primary: Color(0xff7bb7ff),
      accent: Color(0xffff8fb0),
      background: Color(0xff111318),
      surface: Color(0xff1b1d23),
      surfaceAlt: Color(0xff272a31),
      foreground: Color(0xfff0f1f4),
      mutedForeground: Color(0xffa9adb7),
      border: Color(0xff454954),
    );
    final palette = AppThemePalette.custom(
      id: 'custom:private-device-id',
      name: '分享测试',
      seed: const Color(0xff336699),
      light: light,
      dark: dark,
      advanced: true,
    );

    const codec = ThemePaletteTransferCodec();
    final fileText = codec.encodeFile(palette);
    expect(fileText, contains('adventurers-guild-theme'));
    expect(fileText, isNot(contains('private-device-id')));

    final decoded = codec.decode(fileText);
    expect(decoded.name, '分享测试');
    expect(decoded.advanced, isTrue);
    expect(decoded.light.primary, light.primary);
    expect(decoded.dark.border, dark.border);
  });

  test('theme share code round trips and rejects unrelated json', () {
    final light = AppThemeSemanticColors.fromSeed(
      const Color(0xff4f7ac8),
      Brightness.light,
    );
    final dark = AppThemeSemanticColors.fromSeed(
      const Color(0xff4f7ac8),
      Brightness.dark,
    );
    final palette = AppThemePalette.custom(
      id: 'custom:share-code',
      name: '蓝色分享',
      seed: const Color(0xff4f7ac8),
      light: light,
      dark: dark,
      advanced: false,
    );

    const codec = ThemePaletteTransferCodec();
    final code = codec.encodeShareCode(palette);
    expect(code, startsWith(ThemePaletteTransferCodec.sharePrefix));

    final decoded = codec.decode(code);
    expect(decoded.name, '蓝色分享');
    expect(decoded.seed, const Color(0xff4f7ac8));

    expect(
      () => codec.decode('{"schema":1,"kind":"other"}'),
      throwsFormatException,
    );
  });
}
