import 'dart:convert';

import '../web/web_platform_bridge.dart';
import 'app_theme_store_core.dart';

class AppThemeStore extends AppThemeStoreCore {
  static const String _storageKey = 'adventurers-guild.pwa.theme.v2';

  @override
  Future<Map<String, dynamic>?> readPersistedTheme() async {
    try {
      final source = webStorageGet(_storageKey);
      if (source == null || source.trim().isEmpty) return null;
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return <String, dynamic>{
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persistTheme(Map<String, dynamic> value) async {
    try {
      webStorageSet(_storageKey, jsonEncode(value));
    } catch (_) {
      // Appearance changes remain usable for the current browser session.
    }
  }
}
