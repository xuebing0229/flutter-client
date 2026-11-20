import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme_background.dart';
import '../core/theme/app_theme_store.dart';
import 'app_theme.dart';

class GuildMaterialApp extends StatelessWidget {
  const GuildMaterialApp({
    required this.themeStore,
    required this.home,
    this.navigatorKey,
    super.key,
  });

  final AppThemeStore themeStore;
  final Widget home;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final encoded = themeStore.imageBackgroundBase64;
    final imageSystemUiActive =
        themeStore.isImageThemeActive &&
        encoded != null &&
        encoded.isNotEmpty;
    // Android's default stretching overscroll can temporarily suppress a
    // BackdropFilter while a short list is pulled past its edge (Flutter
    // issue #138940). Only image-glass mode disables that decoration;
    // standard scrolling and every other appearance mode remain unchanged.
    final disableImageGlassStretch =
        imageSystemUiActive &&
        themeStore.imageBackgroundMode == AppImageBackgroundMode.glass &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    return _ImageThemeSystemUiScope(
      active: imageSystemUiActive,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: '冒险者公会',
        debugShowCheckedModeBanner: false,
        scrollBehavior: disableImageGlassStretch
            ? const MaterialScrollBehavior().copyWith(overscroll: false)
            : null,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[
          Locale('zh', 'CN'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: themeStore.mode,
        theme: GuildAppTheme.light(themeStore),
        darkTheme: GuildAppTheme.dark(themeStore),
        builder: (context, child) {
          if (!imageSystemUiActive) {
            // Preserve the original color-theme behavior. In particular, do
            // not install any system-bar overlay style when image mode is off.
            return child ?? const SizedBox.shrink();
          }

          Widget content;
          try {
            final bytes = base64Decode(encoded);
            content = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ColoredBox(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF121212)
                          : const Color(0xFFF4F4F4),
                      child: Image.memory(
                        bytes,
                        fit: switch (themeStore.imageFitMode) {
                          AppImageFitMode.fit => BoxFit.contain,
                          AppImageFitMode.fill => BoxFit.cover,
                        },
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: child ?? const SizedBox.shrink(),
                ),
              ],
            );
          } catch (_) {
            content = child ?? const SizedBox.shrink();
          }

          final font = themeStore.imageFontColor;
          final iconBrightness = font.computeLuminance() > 0.55
              ? Brightness.light
              : Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: iconBrightness,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: iconBrightness,
              systemNavigationBarContrastEnforced: false,
            ),
            child: content,
          );
        },
        home: home,
      ),
    );
  }
}

class _ImageThemeSystemUiScope extends StatefulWidget {
  const _ImageThemeSystemUiScope({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_ImageThemeSystemUiScope> createState() =>
      _ImageThemeSystemUiScopeState();
}

class _ImageThemeSystemUiScopeState extends State<_ImageThemeSystemUiScope> {
  static const MethodChannel _channel =
      MethodChannel('app.image_theme_system_ui');

  var _enteredImageMode = false;

  bool get _supportsNativeBridge =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _enterImageMode();
    }
  }

  @override
  void didUpdateWidget(covariant _ImageThemeSystemUiScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _enterImageMode();
    } else {
      _exitImageMode();
    }
  }

  @override
  void dispose() {
    if (_enteredImageMode) {
      _exitImageMode();
    }
    super.dispose();
  }

  void _enterImageMode() {
    if (!_supportsNativeBridge || _enteredImageMode) return;
    _enteredImageMode = true;
    unawaited(_invokeNative('enterImageTheme'));
  }

  void _exitImageMode() {
    if (!_supportsNativeBridge || !_enteredImageMode) return;
    _enteredImageMode = false;
    unawaited(_invokeNative('exitImageTheme'));
  }

  Future<void> _invokeNative(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // System-bar styling must never block the app or theme switching.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
