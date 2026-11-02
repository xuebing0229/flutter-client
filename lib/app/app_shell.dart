import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
      home: home,
    );
  }
}
