import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/app/app_theme.dart';
import 'package:flutter_app/core/theme/app_theme_background.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/core/theme/app_theme_store_core.dart';
import 'package:flutter_app/core/theme/app_ui_style.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';

class _MemoryThemeStore extends AppThemeStoreCore {
  Map<String, dynamic>? initial;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>?> readPersistedTheme() async => initial;

  @override
  Future<void> persistTheme(Map<String, dynamic> value) async {
    saved = Map<String, dynamic>.from(value);
  }
}

void main() {
  test('image theme keeps the color theme settings intact', () async {
    final store = _MemoryThemeStore();
    await store.load();

    await store.setMode(ThemeMode.dark);
    await store.setPaletteId(AppThemePalettes.deepBlueVow.id);
    await store.setStyle(AppUiStyle.bold);

    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setImageBackgroundMode(AppImageBackgroundMode.cover);
    await store.setImageFitMode(AppImageFitMode.fill);
    await store.setImageFontColorValue(0xFF123456);
    await store.setAppearanceMode(AppAppearanceMode.image);

    expect(store.isImageThemeActive, isTrue);
    expect(store.imageBackgroundMode, AppImageBackgroundMode.cover);
    expect(store.imageFitMode, AppImageFitMode.fill);
    expect(store.imageFontColorValue, 0xFF123456);
    expect(store.saved?['appearanceMode'], 'image');
    expect(store.saved?['imageBackgroundMode'], 'cover');
    expect(store.saved?['imageFitMode'], 'fill');

    await store.setAppearanceMode(AppAppearanceMode.color);

    expect(store.mode, ThemeMode.dark);
    expect(store.paletteId, AppThemePalettes.deepBlueVow.id);
    expect(store.style, AppUiStyle.bold);
    expect(store.imageBackgroundBase64, 'aW1hZ2U=');
    expect(store.imageBackgroundName, 'background.png');

    await store.setAppearanceMode(AppAppearanceMode.image);
    expect(store.isImageThemeActive, isTrue);
    expect(store.paletteId, AppThemePalettes.deepBlueVow.id);
    expect(store.style, AppUiStyle.bold);
  });

  test('legacy image theme defaults to complete screen fit', () async {
    final store = _MemoryThemeStore()
      ..initial = <String, dynamic>{
        'appearanceMode': 'image',
        'imageBackgroundMode': 'glass',
        'imageBackgroundBase64': 'aW1hZ2U=',
        'imageBackgroundName': 'legacy.png',
      };

    await store.load();

    expect(store.imageFitMode, AppImageFitMode.fit);
  });

  test('full-cover image theme keeps raised outlined controls', () async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setImageBackgroundMode(AppImageBackgroundMode.cover);
    await store.setAppearanceMode(AppAppearanceMode.image);

    final theme = GuildAppTheme.light(store);
    final tokens = theme.extension<GuildStyleTheme>()!;
    final button = theme.filledButtonTheme.style!;

    expect(tokens.style, AppUiStyle.relief);
    expect(theme.cardTheme.color, Colors.transparent);
    expect(theme.cardTheme.elevation, greaterThan(0));
    expect(
      button.backgroundColor!.resolve(const <WidgetState>{}),
      Colors.transparent,
    );
    expect(
      button.side!.resolve(const <WidgetState>{})!.width,
      greaterThan(0),
    );
    expect(
      button.elevation!.resolve(const <WidgetState>{}),
      greaterThan(0),
    );
  });

  test('reset returns to color theme without deleting image theme data', () async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setImageFitMode(AppImageFitMode.fill);
    await store.setImageFontColorValue(0xFFABCDEF);
    await store.setAppearanceMode(AppAppearanceMode.image);

    await store.resetToDefaults();

    expect(store.appearanceMode, AppAppearanceMode.color);
    expect(store.imageBackgroundBase64, 'aW1hZ2U=');
    expect(store.imageFitMode, AppImageFitMode.fill);
    expect(store.imageFontColorValue, 0xFFABCDEF);
  });
}
