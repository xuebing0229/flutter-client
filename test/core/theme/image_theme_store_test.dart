import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/app/app_theme.dart';
import 'package:flutter_app/core/theme/app_theme_background.dart';
import 'package:flutter_app/core/theme/app_theme_palette.dart';
import 'package:flutter_app/core/theme/app_theme_store.dart';
import 'package:flutter_app/core/theme/app_ui_style.dart';
import 'package:flutter_app/core/theme/guild_visual_theme.dart';
import 'package:flutter_app/core/theme/guild_style_effects.dart';
import 'package:flutter_app/features/home/presentation/workspace_shell.dart';

class _MemoryThemeStore extends AppThemeStore {
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


  test('image theme surface channels always keep the background visible', () async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setAppearanceMode(AppAppearanceMode.image);

    await store.setImageBackgroundMode(AppImageBackgroundMode.cover);
    final cover = GuildAppTheme.light(store);
    expect(cover.colorScheme.surface.a, 0);
    expect(cover.colorScheme.surfaceContainer.a, 0);
    expect(cover.extension<GuildStyleTheme>()!.surface.a, 0);

    await store.setImageBackgroundMode(AppImageBackgroundMode.glass);
    final glass = GuildAppTheme.light(store);
    expect(glass.colorScheme.surface.a, greaterThan(0));
    expect(glass.colorScheme.surface.a, lessThan(1));
    expect(glass.colorScheme.surfaceContainer.a, greaterThan(0));
    expect(glass.colorScheme.surfaceContainer.a, lessThan(1));
    expect(glass.extension<GuildStyleTheme>()!.surface.a, lessThan(1));
  });

  testWidgets('image theme keeps the four-tab bottom navigation on the image', (
    tester,
  ) async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setImageBackgroundMode(AppImageBackgroundMode.cover);
    await store.setAppearanceMode(AppAppearanceMode.image);
    final theme = GuildAppTheme.light(store);

    final tabs = <GuildWorkspaceTab>[
      for (var index = 0; index < 4; index++)
        GuildWorkspaceTab(
          id: 'tab$index',
          label: 'Tab $index',
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
          page: const SizedBox.expand(),
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: GuildWorkspaceShell(
          tabs: tabs,
          selectedIndex: 0,
          onTabSelected: (_) {},
          title: '排单',
          ready: true,
          contentAvailable: true,
          mobileBody: const SizedBox.expand(),
          desktopBody: const SizedBox.expand(),
          drawer: const SizedBox.shrink(),
          desktopToolMenu: const SizedBox.shrink(),
          desktopNavigationOpen: false,
          onDesktopNavigationChanged: (_) {},
          toolSelected: false,
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(scaffold.extendBody, isTrue);
    expect(navigation.backgroundColor, Colors.transparent);

    final effects = tester.widgetList<GuildSurfaceEffect>(
      find.byType(GuildSurfaceEffect),
    );
    expect(
      effects.any(
        (effect) =>
            effect.role == GuildEffectRole.chrome &&
            effect.surface.a == 0,
      ),
      isTrue,
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
