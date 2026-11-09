import 'dart:convert';

import '../web/web_platform_bridge.dart';
import 'app_theme_store_core.dart';

class AppThemeStore extends AppThemeStoreCore {
  static const String _storageKey = 'adventurers-guild.pwa.theme.v2';
  static const String _imageAssetKey = 'appearance/theme-background-v1';

  String? _cachedImageBase64;

  @override
  Future<Map<String, dynamic>?> readPersistedTheme() async {
    try {
      final source = webStorageGet(_storageKey);
      if (source == null || source.trim().isEmpty) return null;
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final result = <String, dynamic>{
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value,
      };
      final imageBytes = await webAssetRead(_imageAssetKey);
      if (imageBytes != null && imageBytes.isNotEmpty) {
        _cachedImageBase64 = base64Encode(imageBytes);
        result['imageBackgroundBase64'] = _cachedImageBase64;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persistTheme(Map<String, dynamic> value) async {
    try {
      final imageBase64 = value['imageBackgroundBase64'];
      final normalizedImage =
          imageBase64 is String && imageBase64.isNotEmpty ? imageBase64 : null;
      if (normalizedImage != _cachedImageBase64) {
        if (normalizedImage == null) {
          await webAssetDelete(_imageAssetKey);
        } else {
          await webAssetWrite(_imageAssetKey, base64Decode(normalizedImage));
        }
        _cachedImageBase64 = normalizedImage;
      }

      final settings = Map<String, dynamic>.from(value)
        ..remove('imageBackgroundBase64');
      webStorageSet(_storageKey, jsonEncode(settings));
    } catch (_) {
      // Appearance changes remain usable for the current browser session.
    }
  }
}
