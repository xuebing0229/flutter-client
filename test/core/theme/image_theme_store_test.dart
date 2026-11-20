import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/app/app_shell.dart';
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

  test('full-cover image theme keeps outlined controls without shadow wash', () async {
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
    expect(theme.cardTheme.elevation, 0);
    expect(theme.cardTheme.shadowColor, Colors.transparent);
    expect(theme.dialogTheme.elevation, 0);
    expect(theme.dialogTheme.shadowColor, Colors.transparent);
    expect(theme.popupMenuTheme.elevation, 0);
    expect(theme.popupMenuTheme.shadowColor, Colors.transparent);
    expect(theme.bottomSheetTheme.elevation, 0);
    expect(theme.bottomSheetTheme.modalElevation, 0);
    expect(theme.bottomSheetTheme.shadowColor, Colors.transparent);
    expect(theme.floatingActionButtonTheme.elevation, 0);
    expect(theme.floatingActionButtonTheme.shadowColor, Colors.transparent);
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
      0,
    );
    expect(
      button.shadowColor!.resolve(const <WidgetState>{}),
      Colors.transparent,
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

  testWidgets(
    'transparent relief surface never paints neumorphic shadow through image',
    (tester) async {
      const legacyShadows = <BoxShadow>[
        BoxShadow(
          color: Color(0xFFFDFDFD),
          offset: Offset(-6, -6),
          blurRadius: 12,
        ),
        BoxShadow(
          color: Color(0xFFA3B1C6),
          offset: Offset(6, 6),
          blurRadius: 12,
        ),
      ];

      Future<List<BoxDecoration>> pumpSurface(Color background) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GuildSurfaceEffect(
                style: AppUiStyle.relief,
                role: GuildEffectRole.chrome,
                primary: Colors.blue,
                accent2: Colors.purple,
                accent3: Colors.orange,
                background: background,
                surface: Colors.transparent,
                surfaceAlt: Colors.transparent,
                foreground: Colors.blueGrey,
                borderColor: Colors.blue,
                borderWidth: 1,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                shadows: legacyShadows,
                glassBlur: 0,
                glassOpacity: 1,
                backdropAvailable: false,
                child: const SizedBox(width: 180, height: 72),
              ),
            ),
          ),
        );
        return tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .toList();
      }

      final imageCover = await pumpSurface(Colors.transparent);
      expect(
        imageCover.expand((decoration) => decoration.boxShadow ?? const []),
        isEmpty,
      );

      final normalRelief = await pumpSurface(const Color(0xFFE0E5EC));
      expect(
        normalRelief
            .expand((decoration) => decoration.boxShadow ?? const [])
            .isNotEmpty,
        isTrue,
        reason: '普通浮雕模式必须保持原来的阴影',
      );
    },
  );

  testWidgets('image themes do not repaint a synthetic backdrop over the image', (
    tester,
  ) async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setAppearanceMode(AppAppearanceMode.image);

    for (final mode in AppImageBackgroundMode.values) {
      await store.setImageBackgroundMode(mode);
      await tester.pumpWidget(
        MaterialApp(
          theme: GuildAppTheme.light(store),
          home: const Scaffold(
            body: GuildStyleBackdrop(
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(
        find.byType(GuildBackdropEffect),
        findsNothing,
        reason: '${mode.label} must show the imported image directly',
      );
    }
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



  test('image theme component surfaces preserve the image surface alpha', () async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64: 'aW1hZ2U=',
      name: 'background.png',
    );
    await store.setAppearanceMode(AppAppearanceMode.image);

    for (final mode in AppImageBackgroundMode.values) {
      await store.setImageBackgroundMode(mode);
      final theme = GuildAppTheme.light(store);
      final tokens = theme.extension<GuildStyleTheme>()!;
      final expectedSurface = tokens.surface;
      final expectedAlt = tokens.surfaceAlt;

      expect(theme.appBarTheme.backgroundColor, expectedSurface);
      expect(theme.navigationBarTheme.backgroundColor, expectedSurface);
      expect(theme.dialogTheme.backgroundColor, expectedSurface);
      expect(theme.popupMenuTheme.color, expectedSurface);
      expect(theme.bottomSheetTheme.backgroundColor, expectedSurface);
      expect(theme.bottomSheetTheme.modalBackgroundColor, expectedSurface);
      expect(theme.inputDecorationTheme.fillColor, expectedAlt);
      expect(theme.snackBarTheme.backgroundColor, expectedAlt);

      final menuBackground =
          theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve({});
      expect(menuBackground, expectedAlt);

      if (mode == AppImageBackgroundMode.cover) {
        expect(expectedSurface.a, 0);
        expect(expectedAlt.a, 0);
      } else {
        expect(expectedSurface.a, greaterThan(0));
        expect(expectedSurface.a, lessThan(1));
        expect(expectedAlt.a, greaterThan(0));
        expect(expectedAlt.a, lessThan(1));
      }
    }
  });

  testWidgets('image glass uses the supplied translucent surface instead of generic white fill', (
    tester,
  ) async {
    const suppliedSurface = Color(0x33777777);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuildSurfaceEffect(
            style: AppUiStyle.glass,
            role: GuildEffectRole.chrome,
            primary: Colors.blue,
            accent2: Colors.purple,
            accent3: Colors.orange,
            background: Colors.transparent,
            surface: suppliedSurface,
            surfaceAlt: suppliedSurface,
            foreground: Colors.black,
            borderColor: Colors.blue,
            borderWidth: 1,
            borderRadius: BorderRadius.all(Radius.circular(16)),
            shadows: const <BoxShadow>[],
            glassBlur: 16,
            glassOpacity: 0.55,
            backdropAvailable: true,
            child: SizedBox(width: 120, height: 60),
          ),
        ),
      ),
    );

    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.any((decoration) => decoration.color == suppliedSurface),
      isTrue,
    );
    expect(
      decorations.any(
        (decoration) => decoration.color == Colors.white.withValues(alpha: 0.60),
      ),
      isFalse,
    );
  });

  testWidgets('Android edge-to-edge is scoped to image theme only', (
    tester,
  ) async {
    const channel = MethodChannel('app.image_theme_system_ui');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    try {
      final store = _MemoryThemeStore();
      await store.load();

      Widget app() => GuildMaterialApp(
            themeStore: store,
            home: const Scaffold(body: SizedBox.expand()),
          );

      await tester.pumpWidget(app());
      await tester.pump();
      expect(
        calls,
        isEmpty,
        reason: '普通主题启动时不应主动接管 Android 系统栏',
      );

      await store.setImageBackground(
        base64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        name: 'background.png',
      );
      await store.setAppearanceMode(AppAppearanceMode.image);
      await tester.pumpWidget(app());
      await tester.pump();
      expect(calls, <String>['enterImageTheme']);

      await store.setAppearanceMode(AppAppearanceMode.color);
      await tester.pumpWidget(app());
      await tester.pump();
      expect(
        calls,
        <String>['enterImageTheme', 'exitImageTheme'],
        reason: '退出图片主题后必须恢复进入前的 Android window 状态',
      );
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('image theme makes Android system bars transparent', (
    tester,
  ) async {
    final store = _MemoryThemeStore();
    await store.load();
    await store.setImageBackground(
      base64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      name: 'background.png',
    );
    await store.setAppearanceMode(AppAppearanceMode.image);

    await tester.pumpWidget(
      GuildMaterialApp(
        themeStore: store,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pump();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarDividerColor, Colors.transparent);
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
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
