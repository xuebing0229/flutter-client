import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/queue_order.dart';

const NodePreset defaultNodePreset = NodePreset(
  id: 'default-workflow',
  name: '默认节点',
  nodes: [
    NodeDefinition(
      id: 'draft',
      name: '草稿',
      iconKey: 'edit',
      colorValue: 0xFF8D8D8D,
      progressPercent: 0,
      builtIn: true,
    ),
    NodeDefinition(
      id: 'line-art',
      name: '线稿',
      iconKey: 'gesture',
      colorValue: 0xFF6F7FA8,
      progressPercent: 30,
      builtIn: true,
    ),
    NodeDefinition(
      id: 'coloring',
      name: '上色',
      iconKey: 'palette',
      colorValue: 0xFFC28B63,
      progressPercent: 60,
      builtIn: true,
    ),
    NodeDefinition(
      id: 'finished-art',
      name: '成稿',
      iconKey: 'image',
      colorValue: 0xFF7F9A78,
      progressPercent: 100,
      builtIn: true,
    ),
  ],
);

class NodePresetStore extends ChangeNotifier {
  NodePresetStore() : _presets = [defaultNodePreset];

  final List<NodePreset> _presets;

  UnmodifiableListView<NodePreset> get presets =>
      UnmodifiableListView(_presets);

  NodePreset byId(String id) {
    return _presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => defaultNodePreset,
    );
  }

  void replaceAll(Iterable<NodePreset> presets) {
    final restored = [for (final preset in presets) preset.snapshot()];
    if (!restored.any((preset) => preset.id == defaultNodePreset.id)) {
      restored.insert(0, defaultNodePreset);
    }

    _presets
      ..clear()
      ..addAll(restored);
    notifyListeners();
  }

  void upsert(NodePreset preset) {
    final index = _presets.indexWhere((item) => item.id == preset.id);
    if (index == -1) {
      _presets.add(preset);
    } else {
      _presets[index] = preset;
    }
    notifyListeners();
  }

  void remove(String id) {
    if (id == defaultNodePreset.id) {
      return;
    }
    _presets.removeWhere((preset) => preset.id == id);
    notifyListeners();
  }
}
