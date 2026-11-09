import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/app_theme_background.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/core/theme/app_theme_store_core.dart';
import 'package:flutter_app/core/theme/app_ui_style.dart';

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
    await store.setImageFontColorValue(0xFF123456);
    await store.setAppearanceMode(AppAppearanceMode.image);

    expect(store.isImageThemeActive, isTrue);
    expect(store.imageBackgroundMode, AppImageBackgroundMode.cover);
    expect(store.imageFontColorValue, 0xFF123456);
    expect(store.saved?['appearanceMode'], 'image');
    expect(store.saved?['imageBackgroundMode'], 'cover');

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

  test('reset returns to color theme without deleting image theme data', () async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setImageFontColorValue(0xFFABCDEF);
    await store.setAppearanceMode(AppAppearanceMode.image);

    await store.resetToDefaults();

    expect(store.appearanceMode, AppAppearanceMode.color);
    expect(store.imageBackgroundBase64, 'aW1hZ2U=');
    expect(store.imageFontColorValue, 0xFFABCDEF);
  });
}
