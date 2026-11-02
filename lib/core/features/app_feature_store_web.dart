import 'dart:convert';

import '../web/web_platform_bridge.dart';
import 'app_feature_store_core.dart';

export 'app_feature_store_core.dart' show AppFeature;

class AppFeatureStore extends AppFeatureStoreCore {
  AppFeatureStore()
      : super(
          unsupported: const <AppFeature>{
            AppFeature.deadlineReminders,
            AppFeature.desktopPet,
          },
        );

  static const String _storageKey = 'adventurers-guild.pwa.features.v1';

  @override
  Future<Map<String, dynamic>?> readPersistedJson() async {
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
  Future<void> persistJson(Map<String, dynamic> value) async {
    try {
      webStorageSet(_storageKey, jsonEncode(value));
    } catch (_) {
      // Keep the in-memory choice if browser storage is unavailable.
    }
  }
}
