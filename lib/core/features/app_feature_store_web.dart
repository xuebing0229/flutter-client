import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../web/web_platform_bridge.dart';

enum AppFeature {
  clientInfo,
  nodeProgress,
  customTags,
  referenceImages,
  search,
  sorting,
  viewSwitch,
  products,
  schedule,
  statistics,
  deadlineReminders,
  abstractMode,
  abstractEffects,
  desktopPet,
  focus,
}

class AppFeatureStore extends ChangeNotifier {
  static const String _storageKey = 'adventurers-guild.pwa.features.v1';

  final Map<AppFeature, bool> _values = {
    for (final feature in AppFeature.values) feature: _defaultValue(feature),
  };

  static bool _defaultValue(AppFeature feature) {
    return switch (feature) {
      AppFeature.abstractMode ||
      AppFeature.desktopPet ||
      AppFeature.deadlineReminders => false,
      _ => true,
    };
  }

  bool enabled(AppFeature feature) => _values[feature] ?? _defaultValue(feature);

  bool get clientInfo => enabled(AppFeature.clientInfo);
  bool get nodeProgress => enabled(AppFeature.nodeProgress);
  bool get customTags => enabled(AppFeature.customTags);
  bool get referenceImages => enabled(AppFeature.referenceImages);
  bool get search => enabled(AppFeature.search);
  bool get sorting => enabled(AppFeature.sorting);
  bool get viewSwitch => enabled(AppFeature.viewSwitch);
  bool get products => enabled(AppFeature.products);
  bool get schedule => enabled(AppFeature.schedule);
  bool get statistics => enabled(AppFeature.statistics);
  bool get deadlineReminders => false;
  bool get abstractMode => enabled(AppFeature.abstractMode);
  bool get focus => enabled(AppFeature.focus);
  bool get abstractEffects =>
      abstractMode && enabled(AppFeature.abstractEffects);

  Future<void> load() async {
    try {
      final source = webStorageGet(_storageKey);
      if (source == null || source.trim().isEmpty) return;
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        _applyMap(decoded, notify: false);
      }
    } catch (_) {
      // Browser settings are best-effort; keep safe defaults.
    }
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    for (final feature in AppFeature.values) {
      _values[feature] = _defaultValue(feature);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(AppFeature feature, bool value) async {
    final next = (feature == AppFeature.deadlineReminders ||
            feature == AppFeature.desktopPet)
        ? false
        : value;
    if (_values[feature] == next) return;
    _values[feature] = next;
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
    final normalized = <String, dynamic>{
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
    for (final feature in AppFeature.values) {
      normalized.putIfAbsent(feature.name, () => _defaultValue(feature));
    }
    normalized[AppFeature.deadlineReminders.name] = false;
    normalized[AppFeature.desktopPet.name] = false;
    for (final feature in AppFeature.values) {
      if (normalized[feature.name] is! bool) {
        throw FormatException('功能开关 ${feature.name} 格式无效。');
      }
    }
    _applyMap(normalized, notify: true);
    await _persist();
  }

  void _applyMap(Map raw, {required bool notify}) {
    var changed = false;
    for (final feature in AppFeature.values) {
      var value = raw[feature.name];
      if (feature == AppFeature.deadlineReminders ||
          feature == AppFeature.desktopPet) {
        value = false;
      }
      if (value is bool && _values[feature] != value) {
        _values[feature] = value;
        changed = true;
      }
    }
    if (changed && notify) notifyListeners();
  }

  Future<void> _persist() async {
    try {
      webStorageSet(_storageKey, jsonEncode(toJson()));
    } catch (_) {
      // Keep the in-memory choice if browser storage is unavailable.
    }
  }
}
