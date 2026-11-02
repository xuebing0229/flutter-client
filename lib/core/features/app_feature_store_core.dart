import 'package:flutter/foundation.dart';

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

abstract class AppFeatureStoreCore extends ChangeNotifier {
  AppFeatureStoreCore({
    Set<AppFeature> unsupported = const <AppFeature>{},
  }) : _unsupported = Set<AppFeature>.unmodifiable(unsupported) {
    for (final feature in AppFeature.values) {
      _values[feature] = _defaultValue(feature);
    }
  }

  final Set<AppFeature> _unsupported;
  final Map<AppFeature, bool> _values = <AppFeature, bool>{};

  static bool _baseDefaultValue(AppFeature feature) {
    return switch (feature) {
      AppFeature.abstractMode || AppFeature.desktopPet => false,
      _ => true,
    };
  }

  bool _defaultValue(AppFeature feature) =>
      !_unsupported.contains(feature) && _baseDefaultValue(feature);

  bool enabled(AppFeature feature) =>
      _unsupported.contains(feature) ? false : (_values[feature] ?? _defaultValue(feature));

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
  bool get deadlineReminders => enabled(AppFeature.deadlineReminders);
  bool get abstractMode => enabled(AppFeature.abstractMode);
  bool get focus => enabled(AppFeature.focus);

  bool get abstractEffects =>
      abstractMode && enabled(AppFeature.abstractEffects);

  Future<void> load() async {
    final raw = await readPersistedJson();
    if (raw != null) {
      applyMap(raw, notify: false);
    }
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    var changed = false;
    for (final feature in AppFeature.values) {
      final next = _defaultValue(feature);
      if (_values[feature] != next) {
        _values[feature] = next;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    await persistJson(toJson());
  }

  Future<void> setEnabled(AppFeature feature, bool value) async {
    final next = _unsupported.contains(feature) ? false : value;
    if (_values[feature] == next) return;
    _values[feature] = next;
    notifyListeners();
    await persistJson(toJson());
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

    // Preserve historical defaults when reading older backups.
    normalized.putIfAbsent(AppFeature.abstractEffects.name, () => true);
    normalized.putIfAbsent(AppFeature.customTags.name, () => true);
    normalized.putIfAbsent(AppFeature.referenceImages.name, () => true);
    normalized.putIfAbsent(AppFeature.desktopPet.name, () => false);
    normalized.putIfAbsent(AppFeature.focus.name, () => true);

    for (final feature in AppFeature.values) {
      normalized.putIfAbsent(feature.name, () => _defaultValue(feature));
      if (normalized[feature.name] is! bool) {
        throw FormatException('功能开关 ${feature.name} 格式无效。');
      }
      if (_unsupported.contains(feature)) {
        normalized[feature.name] = false;
      }
    }

    applyMap(normalized, notify: true);
    await persistJson(toJson());
  }

  @protected
  void applyMap(Map raw, {required bool notify}) {
    var changed = false;
    for (final feature in AppFeature.values) {
      var value = raw[feature.name];
      if (_unsupported.contains(feature)) value = false;
      if (value is bool && _values[feature] != value) {
        _values[feature] = value;
        changed = true;
      }
    }
    if (changed && notify) notifyListeners();
  }

  @protected
  Future<Map<String, dynamic>?> readPersistedJson();

  @protected
  Future<void> persistJson(Map<String, dynamic> value);
}
