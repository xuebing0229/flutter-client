import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../orders/domain/queue_order.dart';
import 'screenshot_import_rules.dart';

/// The lightweight part of one row's import preview that determines which
/// workflow preset and node should be selected. All changes are local to the
/// preview until the user confirms the import.
@immutable
class ImportPresetDraft {
  const ImportPresetDraft({
    required this.id,
    required this.platform,
    required this.title,
    required this.presetId,
    required this.nodeId,
    this.recognizedPercent,
    this.recognizedNodeName,
    this.presetManuallyChanged = false,
    this.nodeManuallyChanged = false,
  });

  final String id;
  final CommissionPlatform platform;
  final String title;
  final int? recognizedPercent;
  final String? recognizedNodeName;
  final String presetId;
  final String nodeId;

  /// An explicit choice in this row takes priority over same-batch suggestions.
  final bool presetManuallyChanged;
  final bool nodeManuallyChanged;

  ImportPresetDraft copyWith({
    String? presetId,
    String? nodeId,
    bool? presetManuallyChanged,
    bool? nodeManuallyChanged,
  }) {
    return ImportPresetDraft(
      id: id,
      platform: platform,
      title: title,
      recognizedPercent: recognizedPercent,
      recognizedNodeName: recognizedNodeName,
      presetId: presetId ?? this.presetId,
      nodeId: nodeId ?? this.nodeId,
      presetManuallyChanged:
          presetManuallyChanged ?? this.presetManuallyChanged,
      nodeManuallyChanged: nodeManuallyChanged ?? this.nodeManuallyChanged,
    );
  }
}

/// Remembers changes made inside a single OCR preview session. Unlike the
/// account's long-term preset memory this controller does not write anything
/// to disk/sync and can be discarded safely when import is cancelled.
class ImportBatchPresetState extends ChangeNotifier {
  ImportBatchPresetState({
    required Iterable<NodePreset> presets,
    required Iterable<ImportPresetDraft> rows,
  }) : _presets = {for (final preset in presets) preset.id: preset},
       _rows = List<ImportPresetDraft>.of(rows) {
    if (_presets.isEmpty) {
      throw ArgumentError('至少需要一个节点预设');
    }
    final ids = <String>{};
    for (final row in _rows) {
      if (!ids.add(row.id)) {
        throw ArgumentError('导入预览中的记录 ID 不可重复');
      }
      _validateRow(row);
    }
  }

  final Map<String, NodePreset> _presets;
  final List<ImportPresetDraft> _rows;

  /// The most recent *explicit* choice per platform + complete order title.
  /// This is never persisted before the final import is confirmed.
  final Map<String, String> _batchChoices = <String, String>{};

  UnmodifiableListView<ImportPresetDraft> get rows =>
      UnmodifiableListView<ImportPresetDraft>(_rows);

  Map<String, String> get pendingPresetChoices =>
      Map<String, String>.unmodifiable(_batchChoices);

  void _validateRow(ImportPresetDraft row) {
    final preset = _presets[row.presetId];
    if (preset == null || !preset.nodes.any((node) => node.id == row.nodeId)) {
      throw ArgumentError('导入预览的节点不属于所选预设');
    }
  }

  ImportPresetDraft byId(String id) =>
      _rows.firstWhere((row) => row.id == id);

  /// Editing ANY row immediately proposes the chosen preset to every other
  /// row with the same platform + complete title, regardless of list position.
  /// Explicit per-row preset/node overrides are never silently overwritten.
  /// Each eligible row independently matches its own OCR percentage.
  void selectPreset(String rowId, String presetId) {
    final preset = _presets[presetId];
    if (preset == null || preset.nodes.isEmpty) {
      throw ArgumentError.value(presetId, 'presetId', '节点预设不存在');
    }
    final index = _rows.indexWhere((row) => row.id == rowId);
    if (index < 0) {
      throw ArgumentError.value(rowId, 'rowId', '记录不存在');
    }

    final source = _rows[index];
    final key = orderPresetMemoryKey(source.platform, source.title);
    _batchChoices[key] = presetId;
    _rows[index] = _withPreset(source, preset, manuallyChanged: true);

    for (var i = 0; i < _rows.length; i++) {
      if (i == index) continue;
      final candidate = _rows[i];
      if (orderPresetMemoryKey(candidate.platform, candidate.title) != key ||
          candidate.presetManuallyChanged ||
          candidate.nodeManuallyChanged) {
        continue;
      }
      _rows[i] = _withPreset(candidate, preset, manuallyChanged: false);
    }
    notifyListeners();
  }

  /// A row's manually selected node is not overwritten by later batch
  /// suggestions from another same-title row.
  void selectNode(String rowId, String nodeId) {
    final index = _rows.indexWhere((row) => row.id == rowId);
    if (index < 0) {
      throw ArgumentError.value(rowId, 'rowId', '记录不存在');
    }
    final row = _rows[index];
    if (!_presets[row.presetId]!.nodes.any((node) => node.id == nodeId)) {
      throw ArgumentError.value(nodeId, 'nodeId', '节点不属于当前预设');
    }
    _rows[index] = row.copyWith(
      nodeId: nodeId,
      nodeManuallyChanged: true,
    );
    notifyListeners();
  }

  /// Additional OCR pages opened in the same preview inherit the batch's
  /// current choice without writing any account-level memory.
  void appendRow(ImportPresetDraft row) {
    if (_rows.any((item) => item.id == row.id)) {
      throw ArgumentError.value(row.id, 'id', '重复记录 ID');
    }
    _validateRow(row);
    final remembered = _batchChoices[orderPresetMemoryKey(
      row.platform,
      row.title,
    )];
    final preset = _presets[remembered];
    _rows.add(
      preset != null && !row.presetManuallyChanged && !row.nodeManuallyChanged
          ? _withPreset(row, preset, manuallyChanged: false)
          : row,
    );
    notifyListeners();
  }

  void removeRow(String id) {
    final before = _rows.length;
    _rows.removeWhere((row) => row.id == id);
    if (before != _rows.length) notifyListeners();
  }

  ImportPresetDraft _withPreset(
    ImportPresetDraft row,
    NodePreset preset, {
    required bool manuallyChanged,
  }) {
    final node = resolveImportNode(
      preset: preset,
      recognizedPercent: row.recognizedPercent,
      recognizedNodeName: row.recognizedNodeName,
    );
    return row.copyWith(
      presetId: preset.id,
      nodeId: node.id,
      presetManuallyChanged: manuallyChanged,
      nodeManuallyChanged: false,
    );
  }
}
