import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

enum AppFeature {
  clientInfo,
  nodeProgress,
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
  static const String _storageKey = 'adventurers-guild.web.features.v1';

  final Map<AppFeature, bool> _values = <AppFeature, bool>{
    for (final feature in AppFeature.values)
      feature: feature == AppFeature.abstractMode ? false : true,
  };

  bool enabled(AppFeature feature) => _values[feature]!;

  bool get clientInfo => enabled(AppFeature.clientInfo);
  bool get nodeProgress => enabled(AppFeature.nodeProgress);
  bool get search => enabled(AppFeature.search);
  bool get sorting => enabled(AppFeature.sorting);
  bool get viewSwitch => enabled(AppFeature.viewSwitch);
  bool get products => enabled(AppFeature.products);
  bool get schedule => enabled(AppFeature.schedule);
  bool get statistics => enabled(AppFeature.statistics);
  bool get deadlineReminders => enabled(AppFeature.deadlineReminders);
  bool get abstractMode => enabled(AppFeature.abstractMode);

  Future<void> load() async {
    try {
      final source = html.window.localStorage[_storageKey];
      if (source == null || source.trim().isEmpty) return;
      final decoded = jsonDecode(source);
      if (decoded is Map) _applyMap(decoded, notify: true);
    } catch (_) {
      // Keep in-memory defaults if Safari storage is unavailable.
    }
  }

  Future<void> resetToDefaults() {
    return applyJson(<String, dynamic>{
      for (final feature in AppFeature.values)
        feature.name: feature != AppFeature.abstractMode,
    });
  }

  Future<void> setEnabled(AppFeature feature, bool value) async {
    if (feature == AppFeature.deadlineReminders) {
      // Web build has no reliable background deadline notification service.
      value = false;
    }
    if (_values[feature] == value) return;
    _values[feature] = value;
    notifyListeners();
    await _persist();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final feature in AppFeature.values)
          feature.name: enabled(feature),
      };

  Future<void> applyJson(Object? raw) async {
    if (raw is! Map) {
      throw const FormatException('功能开关设置格式无效。');
    }
    for (final feature in AppFeature.values) {
      if (raw[feature.name] is! bool) {
        throw FormatException('功能开关 ${feature.name} 格式无效。');
      }
    }
    _applyMap(raw, notify: true);
    _values[AppFeature.deadlineReminders] = false;
    await _persist();
  }

  void _applyMap(Map raw, {required bool notify}) {
    var changed = false;
    for (final feature in AppFeature.values) {
      var value = raw[feature.name];
      if (feature == AppFeature.deadlineReminders) value = false;
      if (value is bool && _values[feature] != value) {
        _values[feature] = value;
        changed = true;
      }
    }
    if (changed && notify) notifyListeners();
  }

  Future<void> _persist() async {
    try {
      html.window.localStorage[_storageKey] = jsonEncode(toJson());
    } catch (_) {
      // The current session still keeps the selection.
    }
  }
}
