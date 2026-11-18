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
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '冒险者公会',
      debugShowCheckedModeBanner: false,
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
        final encoded = themeStore.imageBackgroundBase64;
        final imageThemeActive = themeStore.isImageThemeActive &&
            encoded != null &&
            encoded.isNotEmpty;
        final navIconBrightness =
            themeStore.imageFontColor.computeLuminance() < 0.55
                ? Brightness.dark
                : Brightness.light;

        Widget content = child ?? const SizedBox.shrink();
        if (imageThemeActive) {
          try {
            final bytes = base64Decode(encoded);
            content = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
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
                Positioned.fill(child: content),
              ],
            );
          } catch (_) {
            // Keep the app usable when a stored image is damaged.
          }
        }

        return _SystemUiBoundary(
          imageThemeActive: imageThemeActive,
          navIconBrightness: imageThemeActive
              ? navIconBrightness
              : Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
          normalNavigationBarColor: Theme.of(context).colorScheme.surface,
          child: content,
        );
      },
      home: home,
    );
  }
}


class _SystemUiBoundary extends StatefulWidget {
  const _SystemUiBoundary({
    required this.imageThemeActive,
    required this.navIconBrightness,
    required this.normalNavigationBarColor,
    required this.child,
  });

  final bool imageThemeActive;
  final Brightness navIconBrightness;
  final Color normalNavigationBarColor;
  final Widget child;

  @override
  State<_SystemUiBoundary> createState() => _SystemUiBoundaryState();
}

class _SystemUiBoundaryState extends State<_SystemUiBoundary> {
  @override
  void initState() {
    super.initState();
    _ensureEdgeToEdge();
  }

  @override
  void didUpdateWidget(covariant _SystemUiBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageThemeActive != widget.imageThemeActive) {
      _ensureEdgeToEdge();
    }
  }

  void _ensureEdgeToEdge() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: widget.imageThemeActive
            ? Colors.transparent
            : widget.normalNavigationBarColor,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: widget.navIconBrightness,
        systemNavigationBarContrastEnforced: false,
      ),
      child: widget.child,
    );
  }
}
