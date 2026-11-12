import 'dart:convert';

import 'package:flutter/material.dart';
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
        if (!themeStore.isImageThemeActive ||
            encoded == null ||
            encoded.isEmpty) {
          return child ?? const SizedBox.shrink();
        }
        try {
          final bytes = base64Decode(encoded);
          return Stack(
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
              Positioned.fill(
                child: child ?? const SizedBox.shrink(),
              ),
            ],
          );
        } catch (_) {
          return child ?? const SizedBox.shrink();
        }
      },
      home: home,
    );
  }
}
