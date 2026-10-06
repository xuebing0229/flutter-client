import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppFeature {
  clientInfo,
  nodeProgress,
  referenceImages,
  search,
  sorting,
  viewSwitch,
  products,
  schedule,
  statistics,
  deadlineReminders,
  abstractMode,
}

class AppFeatureStore extends ChangeNotifier {
  Future<void> _persistTail = Future<void>.value();

  final Map<AppFeature, bool> _values = {
    for (final feature in AppFeature.values)
      feature: feature == AppFeature.abstractMode ? false : true,
  };

  bool enabled(AppFeature feature) => _values[feature]!;

  bool get clientInfo => enabled(AppFeature.clientInfo);
  bool get nodeProgress => enabled(AppFeature.nodeProgress);
  bool get referenceImages => enabled(AppFeature.referenceImages);
  bool get search => enabled(AppFeature.search);
  bool get sorting => enabled(AppFeature.sorting);
  bool get viewSwitch => enabled(AppFeature.viewSwitch);
  bool get products => enabled(AppFeature.products);
  bool get schedule => enabled(AppFeature.schedule);
  bool get statistics => enabled(AppFeature.statistics);
  bool get deadlineReminders => enabled(AppFeature.deadlineReminders);
  bool get abstractMode => enabled(AppFeature.abstractMode);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/feature-settings.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _applyMap(decoded, notify: true);
    } catch (_) {
      // Keep the current in-memory defaults when the settings file is unreadable.
    }
  }

  Future<void> resetToDefaults() {
    return applyJson(<String, dynamic>{
      for (final feature in AppFeature.values)
        feature.name: feature != AppFeature.abstractMode,
    });
  }

  Future<void> setEnabled(AppFeature feature, bool value) async {
    if (_values[feature] == value) return;
    _values[feature] = value;
    notifyListeners();
    await _persist();
  }

  Map<String, dynamic> toJson() {
    return {
      for (final feature in AppFeature.values)
        feature.name: enabled(feature),
    };
  }

  Future<void> applyJson(Object? raw) async {
    if (raw is! Map) {
      throw const FormatException('功能开关设置格式无效。');
    }
    // Missing keys keep their current/default value. This keeps saved
    // settings readable when a new optional feature is added later.
    for (final feature in AppFeature.values) {
      if (!raw.containsKey(feature.name)) continue;
      if (raw[feature.name] is! bool) {
        throw FormatException('功能开关 ${feature.name} 格式无效。');
      }
    }
    _applyMap(raw, notify: true);
    await _persist();
  }

  void _applyMap(Map raw, {required bool notify}) {
    var changed = false;

    for (final feature in AppFeature.values) {
      final value = raw[feature.name];
      if (value is bool && _values[feature] != value) {
        _values[feature] = value;
        changed = true;
      }
    }
    if (changed && notify) notifyListeners();
  }

  Future<void> _persist() {
    final operation = _persistTail.then<void>((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(toJson()), flush: true);
      } catch (_) {
        // Feature visibility still works for the current session.
      }
    });
    _persistTail = operation;
    return operation;
  }

}
