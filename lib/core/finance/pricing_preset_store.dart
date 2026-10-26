import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'pricing_adjustments.dart';

class PricingPresetStore extends ChangeNotifier {
  final List<PricingAdjustment> _presets = <PricingAdjustment>[];

  UnmodifiableListView<PricingAdjustment> get presets =>
      UnmodifiableListView(_presets);

  void replaceAll(Iterable<PricingAdjustment> presets) {
    _presets
      ..clear()
      ..addAll(presets.map((item) => item.snapshot()));
    notifyListeners();
  }

  void upsert(PricingAdjustment preset) {
    final index = _presets.indexWhere((item) => item.id == preset.id);
    if (index == -1) {
      _presets.add(preset.snapshot());
    } else {
      _presets[index] = preset.snapshot();
    }
    notifyListeners();
  }

  void remove(String id) {
    _presets.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  PricingAdjustment? byId(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  List<Map<String, dynamic>> toJson() =>
      <Map<String, dynamic>>[for (final preset in _presets) preset.toJson()];

  void applyJson(Object? raw) {
    if (raw == null) {
      replaceAll(const <PricingAdjustment>[]);
      return;
    }
    if (raw is! List) {
      throw const FormatException('同步加价预设格式无效。');
    }
    final restored = <PricingAdjustment>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException('同步加价预设条目格式无效。');
      }
      final preset = PricingAdjustment.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (seen.add(preset.id)) restored.add(preset);
    }
    replaceAll(restored);
  }
}
