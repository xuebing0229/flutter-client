import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum DesktopPetAssetSlot { idleA, keyB }

enum DesktopPetTextMode {
  currentOrder,
  custom;

  String get label => switch (this) {
        DesktopPetTextMode.currentOrder => '当前在画订单',
        DesktopPetTextMode.custom => '自定义文字',
      };
}

class DesktopPetPreset {
  const DesktopPetPreset({
    required this.id,
    required this.name,
    this.imageA,
    this.imageB,
  });

  final String id;
  final String name;
  final String? imageA;
  final String? imageB;

  DesktopPetPreset copyWith({
    String? name,
    String? imageA,
    String? imageB,
    bool clearImageA = false,
    bool clearImageB = false,
  }) {
    return DesktopPetPreset(
      id: id,
      name: name ?? this.name,
      imageA: clearImageA ? null : (imageA ?? this.imageA),
      imageB: clearImageB ? null : (imageB ?? this.imageB),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'imageA': imageA,
        'imageB': imageB,
      };

  static DesktopPetPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.trim().isEmpty || name is! String) return null;
    return DesktopPetPreset(
      id: id,
      name: name.trim().isEmpty ? '未命名桌宠' : name.trim(),
      imageA: raw['imageA'] is String ? raw['imageA'] as String : null,
      imageB: raw['imageB'] is String ? raw['imageB'] as String : null,
    );
  }
}

class DesktopPetSettings extends ChangeNotifier {
  DesktopPetSettings();

  bool _loaded = false;
  bool _enabled = false;
  String? _selectedPresetId;
  DesktopPetTextMode _textMode = DesktopPetTextMode.currentOrder;
  String _customText = '';
  String? _currentOrderId;
  String? _currentOrderTitle;
  String? _currentOrderNode;
  DateTime? _currentOrderDeadline;
  final List<DesktopPetPreset> _presets = <DesktopPetPreset>[];

  bool get loaded => _loaded;
  bool get enabled => _enabled;
  List<DesktopPetPreset> get presets => List<DesktopPetPreset>.unmodifiable(_presets);
  String? get selectedPresetId => _selectedPresetId;
  DesktopPetTextMode get textMode => _textMode;
  String get customText => _customText;
  String? get currentOrderId => _currentOrderId;

  DesktopPetPreset? get selectedPreset {
    final selectedId = _selectedPresetId;
    if (selectedId == null) return null;
    for (final preset in _presets) {
      if (preset.id == selectedId) return preset;
    }
    return null;
  }

  Future<Directory> _rootDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/desktop-pet');
  }

  Future<File> _configFile() async {
    final root = await _rootDirectory();
    return File('${root.path}/config.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    await _readFromDisk();
    _loaded = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _readFromDisk();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _readFromDisk() async {
    final file = await _configFile();
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;

      _enabled = raw['enabled'] == true;
      _selectedPresetId =
          raw['selectedPresetId'] is String ? raw['selectedPresetId'] as String : null;
      _customText = raw['customText'] is String ? raw['customText'] as String : '';
      _currentOrderId =
          raw['currentOrderId'] is String ? raw['currentOrderId'] as String : null;

      final modeName = raw['textMode'];
      _textMode = modeName == DesktopPetTextMode.custom.name
          ? DesktopPetTextMode.custom
          : DesktopPetTextMode.currentOrder;

      _currentOrderTitle = raw['currentOrderTitle'] is String
          ? raw['currentOrderTitle'] as String
          : null;
      _currentOrderNode = raw['currentOrderNode'] is String
          ? raw['currentOrderNode'] as String
          : null;
      _currentOrderDeadline = raw['currentOrderDeadline'] is String
          ? DateTime.tryParse(raw['currentOrderDeadline'] as String)
          : null;

      _presets
        ..clear()
        ..addAll(
          (raw['presets'] is List ? raw['presets'] as List : const <Object?>[])
              .map(DesktopPetPreset.fromJson)
              .whereType<DesktopPetPreset>(),
        );

      if (_selectedPresetId == null ||
          !_presets.any((preset) => preset.id == _selectedPresetId)) {
        _selectedPresetId = _presets.isEmpty ? null : _presets.first.id;
      }
    } catch (_) {
      // The desktop pet is optional. A bad config must not affect work data.
    }
  }

  Future<DesktopPetPreset> createPreset(String rawName) async {
    await load();
    final name = rawName.trim().isEmpty ? '未命名桌宠' : rawName.trim();
    final preset = DesktopPetPreset(
      id: 'pet_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    _presets.add(preset);
    _selectedPresetId = preset.id;
    await _persist();
    notifyListeners();
    return preset;
  }

  Future<void> renamePreset(String id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;
    _presets[index] = _presets[index].copyWith(name: name);
    await _persist();
    notifyListeners();
  }

  Future<void> selectPreset(String id) async {
    if (_selectedPresetId == id) return;
    if (!_presets.any((preset) => preset.id == id)) return;
    _selectedPresetId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> deletePreset(String id) async {
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;

    final root = await _rootDirectory();
    final folder = Directory('${root.path}/presets/$id');
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}

    _presets.removeAt(index);
    if (_selectedPresetId == id) {
      _selectedPresetId = _presets.isEmpty ? null : _presets.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<String?> importAsset(
    String presetId,
    DesktopPetAssetSlot slot,
  ) async {
    if (!Platform.isWindows) return null;
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0) return null;

    const typeGroup = XTypeGroup(
      label: '桌宠图片',
      extensions: <String>['png', 'jpg', 'jpeg'],
    );
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (selected == null) return null;

    final root = await _rootDirectory();
    final folder = Directory('${root.path}/presets/$presetId');
    await folder.create(recursive: true);

    final ext = selected.path.split('.').last.toLowerCase();
    final baseName = slot == DesktopPetAssetSlot.idleA ? 'imageA' : 'imageB';
    final destination = File('${folder.path}/$baseName.$ext');
    await File(selected.path).copy(destination.path);

    _presets[index] = switch (slot) {
      DesktopPetAssetSlot.idleA =>
        _presets[index].copyWith(imageA: destination.path),
      DesktopPetAssetSlot.keyB =>
        _presets[index].copyWith(imageB: destination.path),
    };
    await _persist();
    notifyListeners();
    return destination.path;
  }

  Future<void> clearAsset(
    String presetId,
    DesktopPetAssetSlot slot,
  ) async {
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0) return;
    _presets[index] = switch (slot) {
      DesktopPetAssetSlot.idleA =>
        _presets[index].copyWith(clearImageA: true),
      DesktopPetAssetSlot.keyB =>
        _presets[index].copyWith(clearImageB: true),
    };
    await _persist();
    notifyListeners();
  }

  Future<void> setTextMode(DesktopPetTextMode mode) async {
    if (_textMode == mode) return;
    _textMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setCustomText(String value) async {
    if (_customText == value) return;
    _customText = value;
    await _persist();
    notifyListeners();
  }

  Future<void> selectCurrentOrder({
    required String orderId,
    required String title,
    required String node,
    required DateTime? deadline,
  }) async {
    _currentOrderId = orderId;
    _currentOrderTitle = title;
    _currentOrderNode = node;
    _currentOrderDeadline = deadline;
    await _persist();
    notifyListeners();
  }

  Future<void> clearCurrentOrderSelection() async {
    if (_currentOrderId == null &&
        _currentOrderTitle == null &&
        _currentOrderNode == null &&
        _currentOrderDeadline == null) {
      return;
    }
    _currentOrderId = null;
    _currentOrderTitle = null;
    _currentOrderNode = null;
    _currentOrderDeadline = null;
    await _persist();
    notifyListeners();
  }

  Future<void> setRuntimeState({
    required bool enabled,
    required String? currentOrderTitle,
    required String? currentOrderNode,
    required DateTime? currentOrderDeadline,
  }) async {
    await _readFromDisk();
    _loaded = true;
    _enabled = enabled;
    _currentOrderTitle = currentOrderTitle;
    _currentOrderNode = currentOrderNode;
    _currentOrderDeadline = currentOrderDeadline;
    await _persist();
  }

  Future<void> _persist() async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    final active = selectedPreset;
    final payload = <String, dynamic>{
      'schema': 4,
      'enabled': _enabled,
      'selectedPresetId': _selectedPresetId,
      'imageA': active?.imageA,
      'imageB': active?.imageB,
      'textMode': _textMode.name,
      'customText': _customText,
      'currentOrderId': _currentOrderId,
      'currentOrderTitle': _currentOrderTitle,
      'currentOrderNode': _currentOrderNode,
      'currentOrderDeadline': _currentOrderDeadline?.toIso8601String(),
      'presets': <Map<String, dynamic>>[
        for (final preset in _presets) preset.toJson(),
      ],
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }
}

class DesktopPetService {
  DesktopPetService({DesktopPetSettings? settings})
      : settings = settings ?? DesktopPetSettings();

  final DesktopPetSettings settings;
  Process? _process;

  Future<void> sync({
    required bool enabled,
    String? currentOrderTitle,
    String? currentOrderNode,
    DateTime? currentOrderDeadline,
  }) async {
    if (!Platform.isWindows) return;

    await settings.setRuntimeState(
      enabled: enabled,
      currentOrderTitle: currentOrderTitle,
      currentOrderNode: currentOrderNode,
      currentOrderDeadline: currentOrderDeadline,
    );

    if (!enabled) {
      await stop();
      return;
    }
    if (_process != null) return;

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final host = File(
      '${executableDirectory.path}/desktop_pet/AdventurersGuild.DesktopPet.exe',
    );
    if (!await host.exists()) return;

    final config = await settings._configFile();
    try {
      _process = await Process.start(
        host.path,
        <String>[
          '--config',
          config.path,
          '--parent-pid',
          pid.toString(),
        ],
        mode: ProcessStartMode.detachedWithStdio,
      );
      unawaited(_process!.exitCode.then((_) {
        _process = null;
      }));
    } catch (_) {
      _process = null;
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      process.kill();
    } catch (_) {}
  }

  void dispose() {
    unawaited(stop());
    settings.dispose();
  }
}
