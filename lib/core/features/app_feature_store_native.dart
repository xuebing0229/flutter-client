import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_feature_store_core.dart';

export 'app_feature_store_core.dart' show AppFeature;

class AppFeatureStore extends AppFeatureStoreCore {
  AppFeatureStore();

  Future<void> _persistTail = Future<void>.value();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/feature-settings.json');
  }

  @override
  Future<Map<String, dynamic>?> readPersistedJson() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
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
  Future<void> persistJson(Map<String, dynamic> value) {
    final operation = _persistTail.then<void>((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(value), flush: true);
      } catch (_) {
        // Feature visibility remains usable for the current session.
      }
    });
    _persistTail = operation;
    return operation;
  }
}
