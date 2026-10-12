import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';

enum DesktopPetAssetSlot { idleA, keyB }

class DesktopPetPlacement {
  const DesktopPetPlacement({
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  final double scale;
  final double offsetX;
  final double offsetY;

  DesktopPetPlacement copyWith({
    double? scale,
    double? offsetX,
    double? offsetY,
  }) {
    return DesktopPetPlacement(
      scale: (scale ?? this.scale).clamp(0.35, 3.0).toDouble(),
      offsetX: (offsetX ?? this.offsetX).clamp(-1.0, 1.0).toDouble(),
      offsetY: (offsetY ?? this.offsetY).clamp(-1.0, 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scale': scale,
        'offsetX': offsetX,
        'offsetY': offsetY,
      };

  static DesktopPetPlacement fromJson(Object? raw) {
    if (raw is! Map) return const DesktopPetPlacement();
    return DesktopPetPlacement(
      scale: ((raw['scale'] as num?)?.toDouble() ?? 1)
          .clamp(0.35, 3.0)
          .toDouble(),
      offsetX: ((raw['offsetX'] as num?)?.toDouble() ?? 0)
          .clamp(-1.0, 1.0)
          .toDouble(),
      offsetY: ((raw['offsetY'] as num?)?.toDouble() ?? 0)
          .clamp(-1.0, 1.0)
          .toDouble(),
    );
  }
}

class DesktopPetOverlayOffset {
  const DesktopPetOverlayOffset({
    this.x = 0,
    this.y = 0,
  });

  final double x;
  final double y;

  DesktopPetOverlayOffset copyWith({
    double? x,
    double? y,
  }) {
    return DesktopPetOverlayOffset(
      x: (x ?? this.x).clamp(-0.85, 0.85).toDouble(),
      y: (y ?? this.y).clamp(-0.85, 0.85).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
      };

  static DesktopPetOverlayOffset fromJson(Object? raw) {
    if (raw is! Map) return const DesktopPetOverlayOffset();
    return DesktopPetOverlayOffset(
      x: ((raw['x'] as num?)?.toDouble() ?? 0).clamp(-0.85, 0.85).toDouble(),
      y: ((raw['y'] as num?)?.toDouble() ?? 0).clamp(-0.85, 0.85).toDouble(),
    );
  }
}

enum DesktopPetBubblePosition {
  above,
  side;

  String get label => switch (this) {
        DesktopPetBubblePosition.above => '头顶',
        DesktopPetBubblePosition.side => '旁边',
      };
}

enum DesktopPetBubbleStyle {
  speech,
  thought;

  String get label => switch (this) {
        DesktopPetBubbleStyle.speech => '说话气泡',
        DesktopPetBubbleStyle.thought => '思考气泡',
      };
}

enum DesktopPetBubbleContentMode {
  text,
  image;

  String get label => switch (this) {
        DesktopPetBubbleContentMode.text => '文字',
        DesktopPetBubbleContentMode.image => '图片',
      };
}

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
    this.bubbleImage,
    this.placementA = const DesktopPetPlacement(),
    this.placementB = const DesktopPetPlacement(),
    this.importPlacementA,
    this.importPlacementB,
    this.bubbleAboveOffset = const DesktopPetOverlayOffset(),
    this.bubbleSideOffset = const DesktopPetOverlayOffset(),
    this.focusClockOffset = const DesktopPetOverlayOffset(),
  });

  final String id;
  final String name;
  final String? imageA;
  final String? imageB;
  final String? bubbleImage;
  final DesktopPetPlacement placementA;
  final DesktopPetPlacement placementB;
  final DesktopPetPlacement? importPlacementA;
  final DesktopPetPlacement? importPlacementB;
  final DesktopPetOverlayOffset bubbleAboveOffset;
  final DesktopPetOverlayOffset bubbleSideOffset;
  final DesktopPetOverlayOffset focusClockOffset;

  DesktopPetPreset copyWith({
    String? name,
    String? imageA,
    String? imageB,
    String? bubbleImage,
    DesktopPetPlacement? placementA,
    DesktopPetPlacement? placementB,
    DesktopPetPlacement? importPlacementA,
    DesktopPetPlacement? importPlacementB,
    DesktopPetOverlayOffset? bubbleAboveOffset,
    DesktopPetOverlayOffset? bubbleSideOffset,
    DesktopPetOverlayOffset? focusClockOffset,
    bool clearImageA = false,
    bool clearImageB = false,
    bool clearBubbleImage = false,
  }) {
    return DesktopPetPreset(
      id: id,
      name: name ?? this.name,
      imageA: clearImageA ? null : (imageA ?? this.imageA),
      imageB: clearImageB ? null : (imageB ?? this.imageB),
      bubbleImage: clearBubbleImage ? null : (bubbleImage ?? this.bubbleImage),
      placementA: placementA ?? this.placementA,
      placementB: placementB ?? this.placementB,
      importPlacementA: importPlacementA ?? this.importPlacementA,
      importPlacementB: importPlacementB ?? this.importPlacementB,
      bubbleAboveOffset: bubbleAboveOffset ?? this.bubbleAboveOffset,
      bubbleSideOffset: bubbleSideOffset ?? this.bubbleSideOffset,
      focusClockOffset: focusClockOffset ?? this.focusClockOffset,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'imageA': imageA,
        'imageB': imageB,
        'bubbleImage': bubbleImage,
        'placementA': placementA.toJson(),
        'placementB': placementB.toJson(),
        if (importPlacementA != null)
          'importPlacementA': importPlacementA!.toJson(),
        if (importPlacementB != null)
          'importPlacementB': importPlacementB!.toJson(),
        'bubbleAboveOffset': bubbleAboveOffset.toJson(),
        'bubbleSideOffset': bubbleSideOffset.toJson(),
        'focusClockOffset': focusClockOffset.toJson(),
      };

  static DesktopPetPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.trim().isEmpty || name is! String) return null;
    final placementA = DesktopPetPlacement.fromJson(raw['placementA']);
    final placementB = DesktopPetPlacement.fromJson(raw['placementB']);
    return DesktopPetPreset(
      id: id,
      name: name.trim().isEmpty ? '未命名桌宠' : name.trim(),
      imageA: raw['imageA'] is String ? raw['imageA'] as String : null,
      imageB: raw['imageB'] is String ? raw['imageB'] as String : null,
      bubbleImage: raw['bubbleImage'] is String ? raw['bubbleImage'] as String : null,
      placementA: placementA,
      placementB: placementB,
      // Older configs did not preserve an import baseline. Use the last
      // saved placement as a non-destructive compatibility baseline.
      importPlacementA: raw['importPlacementA'] is Map
          ? DesktopPetPlacement.fromJson(raw['importPlacementA'])
          : placementA,
      importPlacementB: raw['importPlacementB'] is Map
          ? DesktopPetPlacement.fromJson(raw['importPlacementB'])
          : placementB,
      bubbleAboveOffset:
          DesktopPetOverlayOffset.fromJson(raw['bubbleAboveOffset']),
      bubbleSideOffset:
          DesktopPetOverlayOffset.fromJson(raw['bubbleSideOffset']),
      focusClockOffset:
          DesktopPetOverlayOffset.fromJson(raw['focusClockOffset']),
    );
  }
}

class DesktopPetSettings extends ChangeNotifier {
  DesktopPetSettings();

  bool _loaded = false;
  Future<void>? _loadInFlight;
  Future<void>? _runtimePersistInFlight;
  Future<void> _persistTail = Future<void>.value();
  bool _enabled = false;
  bool _configLoadedFromDisk = false;
  String? _selectedPresetId;
  DesktopPetBubbleContentMode _bubbleContentMode =
      DesktopPetBubbleContentMode.text;
  DesktopPetTextMode _textMode = DesktopPetTextMode.currentOrder;
  DesktopPetBubblePosition _bubblePosition = DesktopPetBubblePosition.above;
  DesktopPetBubbleStyle _bubbleStyle = DesktopPetBubbleStyle.speech;
  double _petScale = 1;
  double _bubbleTextScale = 1;
  double _bubbleImageScale = 1;
  double _focusClockScale = 1;
  String _customText = '';
  String? _currentOrderId;
  String? _currentOrderTitle;
  String? _currentOrderNode;
  DateTime? _currentOrderDeadline;
  int _bubbleBackgroundArgb = 0xFFF7F7F7;
  int _bubbleForegroundArgb = 0xFF202020;
  int _bubbleBorderArgb = 0x33202020;
  int _bubbleAccentArgb = 0xFF6C7A6B;
  DateTime? _focusStartedAt;
  bool _focusEnabled = true;
  final List<DesktopPetPreset> _presets = <DesktopPetPreset>[];

  bool get loaded => _loaded;
  bool get enabled => _enabled;
  List<DesktopPetPreset> get presets => List<DesktopPetPreset>.unmodifiable(_presets);
  String? get selectedPresetId => _selectedPresetId;
  DesktopPetBubbleContentMode get bubbleContentMode => _bubbleContentMode;
  DesktopPetTextMode get textMode => _textMode;
  DesktopPetBubblePosition get bubblePosition => _bubblePosition;
  DesktopPetBubbleStyle get bubbleStyle => _bubbleStyle;
  double get petScale => _petScale;
  double get bubbleTextScale => _bubbleTextScale;
  double get bubbleImageScale => _bubbleImageScale;
  double get focusClockScale => _focusClockScale;
  DesktopPetOverlayOffset get bubbleAboveOffset =>
      selectedPreset?.bubbleAboveOffset ?? const DesktopPetOverlayOffset();
  DesktopPetOverlayOffset get bubbleSideOffset =>
      selectedPreset?.bubbleSideOffset ?? const DesktopPetOverlayOffset();
  DesktopPetOverlayOffset get focusClockOffset =>
      selectedPreset?.focusClockOffset ?? const DesktopPetOverlayOffset();
  DesktopPetOverlayOffset get activeBubbleOffset =>
      _bubblePosition == DesktopPetBubblePosition.side
          ? bubbleSideOffset
          : bubbleAboveOffset;
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

  Future<void> _cleanupStaleAssetsAtStartup() async {
    if (!_configLoadedFromDisk) return;

    final root = await _rootDirectory();
    final presetsRoot = Directory('${root.path}/presets');
    if (!await presetsRoot.exists()) return;

    final liveByPreset = <String, Set<String>>{
      for (final preset in _presets)
        preset.id: <String>{
          if (preset.imageA != null) File(preset.imageA!).absolute.path,
          if (preset.imageB != null) File(preset.imageB!).absolute.path,
          if (preset.bubbleImage != null) File(preset.bubbleImage!).absolute.path,
        },
    };

    try {
      await for (final entity in presetsRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final presetId = entity.path.split(Platform.pathSeparator).last;
        final live = liveByPreset[presetId];
        if (live == null) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
          continue;
        }

        await for (final child in entity.list(followLinks: false)) {
          if (child is! File) continue;
          if (live.contains(child.absolute.path)) continue;
          try {
            await child.delete();
          } catch (_) {
            // Startup cleanup is best-effort. Never delete assets while the
            // current UI/native host may still be rendering them.
          }
        }
      }
    } catch (_) {
      // Stale local assets are harmless; cleanup must never affect the app.
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final existing = _loadInFlight;
    if (existing != null) {
      await existing;
      return;
    }

    final operation = _loadOnce();
    _loadInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_loadInFlight, operation)) {
        _loadInFlight = null;
      }
    }
  }

  Future<void> _loadOnce() async {
    await _readFromDisk();
    await _cleanupStaleAssetsAtStartup();
    _loaded = true;
    notifyListeners();
  }

  /// Re-read is retained for diagnostics/recovery, but normal mutations use
  /// the single shared in-memory settings instance and never merge stale disk
  /// state back over a newer change.
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

      _bubblePosition = raw['bubblePosition'] == DesktopPetBubblePosition.side.name
          ? DesktopPetBubblePosition.side
          : DesktopPetBubblePosition.above;
      _bubbleStyle = raw['bubbleStyle'] == DesktopPetBubbleStyle.thought.name
          ? DesktopPetBubbleStyle.thought
          : DesktopPetBubbleStyle.speech;
      _petScale = ((raw['petScale'] as num?)?.toDouble() ?? 1)
          .clamp(0.5, 1.8)
          .toDouble();
      _bubbleTextScale =
          ((raw['bubbleTextScale'] as num?)?.toDouble() ??
                  (raw['bubbleScale'] as num?)?.toDouble() ??
                  1)
              .clamp(0.65, 1.8)
              .toDouble();
      _bubbleImageScale =
          ((raw['bubbleImageScale'] as num?)?.toDouble() ?? 1)
              .clamp(0.5, 2.0)
              .toDouble();
      _focusClockScale = ((raw['focusClockScale'] as num?)?.toDouble() ?? 1)
          .clamp(0.65, 1.8)
          .toDouble();

      _bubbleBackgroundArgb =
          (raw['bubbleBackgroundArgb'] as num?)?.toInt() ??
              _bubbleBackgroundArgb;
      _bubbleForegroundArgb =
          (raw['bubbleForegroundArgb'] as num?)?.toInt() ??
              _bubbleForegroundArgb;
      _bubbleBorderArgb =
          (raw['bubbleBorderArgb'] as num?)?.toInt() ?? _bubbleBorderArgb;
      _bubbleAccentArgb =
          (raw['bubbleAccentArgb'] as num?)?.toInt() ?? _bubbleAccentArgb;
      _focusStartedAt = raw['focusStartedAt'] is String
          ? DateTime.tryParse(raw['focusStartedAt'] as String)
          : null;
      _focusEnabled = raw['focusEnabled'] is bool
          ? raw['focusEnabled'] as bool
          : true;

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

      final bubbleContentMode = raw['bubbleContentMode'];
      if (bubbleContentMode == DesktopPetBubbleContentMode.image.name) {
        _bubbleContentMode = DesktopPetBubbleContentMode.image;
      } else if (bubbleContentMode == DesktopPetBubbleContentMode.text.name) {
        _bubbleContentMode = DesktopPetBubbleContentMode.text;
      } else {
        // Migration from the old mixed content model: if the selected preset
        // already has an inserted image, preserve the user's intent as image
        // mode instead of silently hiding it behind text.
        _bubbleContentMode = selectedPreset?.bubbleImage != null
            ? DesktopPetBubbleContentMode.image
            : DesktopPetBubbleContentMode.text;
      }

      // Only a completely parsed config is safe to use as the authority for
      // startup stale-file cleanup. A malformed/corrupt config must never make
      // an empty/partially parsed preset list delete valid local image assets.
      _configLoadedFromDisk = true;
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
    await load();
    final name = rawName.trim();
    if (name.isEmpty) return;
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;
    _presets[index] = _presets[index].copyWith(name: name);
    await _persist();
    notifyListeners();
  }

  Future<void> selectPreset(String id) async {
    await load();
    if (_selectedPresetId == id) return;
    if (!_presets.any((preset) => preset.id == id)) return;
    _selectedPresetId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> deletePreset(String id) async {
    await load();
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;

    // Detach from state first. Deleting image files while Flutter/WPF is still
    // rendering them is a common Windows native-crash path. Physical cleanup
    // is deferred until the next app start, before any preview is mounted.
    _presets.removeAt(index);
    if (_selectedPresetId == id) {
      _selectedPresetId = _presets.isEmpty ? null : _presets.first.id;
    }
    if (_bubbleContentMode == DesktopPetBubbleContentMode.image &&
        selectedPreset?.bubbleImage == null) {
      _bubbleContentMode = DesktopPetBubbleContentMode.text;
    }
    await _persist();
    notifyListeners();
  }

  Future<String?> pickAssetSource() async {
    if (!Platform.isWindows) return null;
    const typeGroup = XTypeGroup(
      label: '桌宠图片',
      extensions: <String>['png', 'jpg', 'jpeg'],
    );
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    return selected?.path;
  }

  Future<String?> importAssetFromPath(
    String presetId,
    DesktopPetAssetSlot slot,
    String sourcePath,
    DesktopPetPlacement placement,
  ) async {
    if (!Platform.isWindows) return null;
    await load();
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0) return null;

    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final root = await _rootDirectory();
    final folder = Directory('${root.path}/presets/$presetId');
    await folder.create(recursive: true);

    final ext = source.path.split('.').last.toLowerCase();
    final baseName = slot == DesktopPetAssetSlot.idleA ? 'imageA' : 'imageB';
    // Never overwrite an image the native host or Flutter preview may still be
    // decoding. Persist the new path first, then prune stale slot files.
    final destination = File(
      '${folder.path}/$baseName.${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    if (source.absolute.path != destination.absolute.path) {
      await source.copy(destination.path);
    }

    _presets[index] = switch (slot) {
      DesktopPetAssetSlot.idleA => _presets[index].copyWith(
          imageA: destination.path,
          placementA: placement,
          importPlacementA: placement,
        ),
      DesktopPetAssetSlot.keyB => _presets[index].copyWith(
          imageB: destination.path,
          placementB: placement,
          importPlacementB: placement,
        ),
    };
    await _persist();
    notifyListeners();
    return destination.path;
  }

  Future<void> clearAsset(
    String presetId,
    DesktopPetAssetSlot slot,
  ) async {
    await load();
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

  Future<void> setPlacement(
    String presetId,
    DesktopPetAssetSlot slot,
    DesktopPetPlacement placement,
  ) async {
    await load();
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0) return;

    _presets[index] = switch (slot) {
      DesktopPetAssetSlot.idleA =>
        _presets[index].copyWith(placementA: placement),
      DesktopPetAssetSlot.keyB =>
        _presets[index].copyWith(placementB: placement),
    };
    await _persist();
    notifyListeners();
  }

  Future<void> setBubbleContentMode(
    DesktopPetBubbleContentMode mode,
  ) async {
    await load();
    if (_bubbleContentMode == mode) return;
    _bubbleContentMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setTextMode(DesktopPetTextMode mode) async {
    await load();
    if (_textMode == mode) return;
    _textMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setBubblePosition(DesktopPetBubblePosition position) async {
    await load();
    if (_bubblePosition == position) return;
    _bubblePosition = position;
    await _persist();
    notifyListeners();
  }

  Future<void> setBubbleStyle(DesktopPetBubbleStyle style) async {
    await load();
    if (_bubbleStyle == style) return;
    _bubbleStyle = style;
    await _persist();
    notifyListeners();
  }

  Future<String?> pickBubbleImageSource() async {
    if (!Platform.isWindows) return null;
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: '透明背景 PNG', extensions: <String>['png']),
      ],
    );
    return selected?.path;
  }

  Future<void> importBubbleImage(String presetId, String sourcePath) async {
    if (!Platform.isWindows) return;
    await load();
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0 || !sourcePath.toLowerCase().endsWith('.png')) return;
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final root = await _rootDirectory();
    final folder = Directory('${root.path}/presets/$presetId');
    await folder.create(recursive: true);
    // Use a fresh filename for every import. This guarantees the desktop host
    // sees a new path and never races a replacement of an image it is decoding.
    final destination = File(
      '${folder.path}/bubble-image.${DateTime.now().microsecondsSinceEpoch}.png',
    );
    if (source.absolute.path != destination.absolute.path) {
      await source.copy(destination.path);
    }
    _presets[index] = _presets[index].copyWith(
      bubbleImage: destination.path,
    );
    _bubbleContentMode = DesktopPetBubbleContentMode.image;
    await _persist();
    notifyListeners();
  }

  Future<void> clearBubbleImage(String presetId) async {
    await load();
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0 || _presets[index].bubbleImage == null) return;
    _presets[index] = _presets[index].copyWith(clearBubbleImage: true);
    _bubbleContentMode = DesktopPetBubbleContentMode.text;
    await _persist();
    notifyListeners();
  }

  Future<void> setPetScale(double value) async {
    await load();
    final normalized = value.clamp(0.5, 1.8).toDouble();
    if ((_petScale - normalized).abs() < 0.001) return;
    _petScale = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setBubbleTextScale(double value) async {
    await load();
    final normalized = value.clamp(0.65, 1.8).toDouble();
    if ((_bubbleTextScale - normalized).abs() < 0.001) return;
    _bubbleTextScale = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setBubbleImageScale(double value) async {
    await load();
    final normalized = value.clamp(0.5, 2.0).toDouble();
    if ((_bubbleImageScale - normalized).abs() < 0.001) return;
    _bubbleImageScale = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setBubbleOffset(
    DesktopPetBubblePosition position,
    DesktopPetOverlayOffset offset,
  ) async {
    await load();
    final selectedId = _selectedPresetId;
    if (selectedId == null) return;
    final index = _presets.indexWhere((preset) => preset.id == selectedId);
    if (index < 0) return;
    final normalized = offset.copyWith();
    _presets[index] = position == DesktopPetBubblePosition.side
        ? _presets[index].copyWith(bubbleSideOffset: normalized)
        : _presets[index].copyWith(bubbleAboveOffset: normalized);
    await _persist();
    notifyListeners();
  }

  Future<void> setFocusClockOffset(DesktopPetOverlayOffset offset) async {
    await load();
    final selectedId = _selectedPresetId;
    if (selectedId == null) return;
    final index = _presets.indexWhere((preset) => preset.id == selectedId);
    if (index < 0) return;
    _presets[index] = _presets[index].copyWith(
      focusClockOffset: offset.copyWith(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> setFocusClockScale(double value) async {
    await load();
    final normalized = value.clamp(0.65, 1.8).toDouble();
    if ((_focusClockScale - normalized).abs() < 0.001) return;
    _focusClockScale = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setCustomText(String value) async {
    await load();
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
    await load();
    _currentOrderId = orderId;
    _currentOrderTitle = title;
    _currentOrderNode = node;
    _currentOrderDeadline = deadline;
    await _persist();
    notifyListeners();
  }

  Future<void> clearCurrentOrderSelection() async {
    await load();
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
    required int bubbleBackgroundArgb,
    required int bubbleForegroundArgb,
    required int bubbleBorderArgb,
    required int bubbleAccentArgb,
    required bool focusEnabled,
    required DateTime? focusStartedAt,
  }) async {
    await load();
    _loaded = true;

    // Home/focus state can call sync repeatedly even when nothing visible has
    // changed. Rewriting config.json every time wakes the native pet host and
    // used to make typing/sliders needlessly rebuild its image resources.
    final unchanged = _enabled == enabled &&
        _currentOrderTitle == currentOrderTitle &&
        _currentOrderNode == currentOrderNode &&
        _currentOrderDeadline == currentOrderDeadline &&
        _bubbleBackgroundArgb == bubbleBackgroundArgb &&
        _bubbleForegroundArgb == bubbleForegroundArgb &&
        _bubbleBorderArgb == bubbleBorderArgb &&
        _bubbleAccentArgb == bubbleAccentArgb &&
        _focusEnabled == focusEnabled &&
        _focusStartedAt == focusStartedAt;
    if (unchanged) {
      final pending = _runtimePersistInFlight;
      if (pending != null) {
        await pending;
      }
      return;
    }

    _enabled = enabled;
    _currentOrderTitle = currentOrderTitle;
    _currentOrderNode = currentOrderNode;
    _currentOrderDeadline = currentOrderDeadline;
    _bubbleBackgroundArgb = bubbleBackgroundArgb;
    _bubbleForegroundArgb = bubbleForegroundArgb;
    _bubbleBorderArgb = bubbleBorderArgb;
    _bubbleAccentArgb = bubbleAccentArgb;
    _focusEnabled = focusEnabled;
    _focusStartedAt = focusStartedAt;

    final operation = _persist();
    _runtimePersistInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_runtimePersistInFlight, operation)) {
        _runtimePersistInFlight = null;
      }
    }
  }

  Future<void> _persist() async {
    final file = await _configFile();
    final active = selectedPreset;
    final payload = <String, dynamic>{
      'schema': 11,
      'enabled': _enabled,
      'selectedPresetId': _selectedPresetId,
      'imageA': active?.imageA,
      'imageB': active?.imageB,
      'bubbleImage': active?.bubbleImage,
      'bubbleContentMode': _bubbleContentMode.name,
      'placementA': active?.placementA.toJson(),
      'placementB': active?.placementB.toJson(),
      'textMode': _textMode.name,
      'bubblePosition': _bubblePosition.name,
      'bubbleStyle': _bubbleStyle.name,
      'petScale': _petScale,
      'bubbleTextScale': _bubbleTextScale,
      'bubbleImageScale': _bubbleImageScale,
      'focusClockScale': _focusClockScale,
      'bubbleAboveOffset': bubbleAboveOffset.toJson(),
      'bubbleSideOffset': bubbleSideOffset.toJson(),
      'focusClockOffset': focusClockOffset.toJson(),
      'customText': _customText,
      'currentOrderId': _currentOrderId,
      'currentOrderTitle': _currentOrderTitle,
      'currentOrderNode': _currentOrderNode,
      'currentOrderDeadline': _currentOrderDeadline?.toIso8601String(),
      'bubbleBackgroundArgb': _bubbleBackgroundArgb,
      'bubbleForegroundArgb': _bubbleForegroundArgb,
      'bubbleBorderArgb': _bubbleBorderArgb,
      'bubbleAccentArgb': _bubbleAccentArgb,
      'focusEnabled': _focusEnabled,
      'focusStartedAt': _focusStartedAt?.toUtc().toIso8601String(),
      'presets': <Map<String, dynamic>>[
        for (final preset in _presets) preset.toJson(),
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);

    // Serialize every settings write. Slider/text/order callbacks can overlap,
    // and concurrent atomic renames on Windows were still able to race each
    // other and the native file watcher.
    final previous = _persistTail;
    final operation = previous.then<void>(
      (_) => _writeEncodedConfig(file, encoded),
      onError: (Object _, StackTrace __) => _writeEncodedConfig(file, encoded),
    );
    _persistTail = operation.catchError((Object _, StackTrace __) {});
    await operation;
  }

  Future<void> _writeEncodedConfig(File file, String encoded) async {
    // Antivirus/indexers can briefly hold the config file on Windows. Retry
    // one transient filesystem failure before surfacing it to the caller.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await file.parent.create(recursive: true);
        await atomicWriteString(file, encoded);
        return;
      } on FileSystemException {
        if (attempt != 0) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

}

class DesktopPetService {
  DesktopPetService({DesktopPetSettings? settings})
      : settings = settings ?? DesktopPetSettings();

  final DesktopPetSettings settings;
  Process? _process;
  Future<void>? _startInFlight;
  Future<void>? _stopInFlight;
  bool _enabledRequested = false;
  int _requestGeneration = 0;

  Future<void> sync({
    required bool enabled,
    String? currentOrderTitle,
    String? currentOrderNode,
    DateTime? currentOrderDeadline,
    required int bubbleBackgroundArgb,
    required int bubbleForegroundArgb,
    required int bubbleBorderArgb,
    required int bubbleAccentArgb,
    required bool focusEnabled,
    required DateTime? focusStartedAt,
  }) async {
    if (!Platform.isWindows) return;
    final requestGeneration = ++_requestGeneration;
    _enabledRequested = enabled;

    await settings.setRuntimeState(
      enabled: enabled,
      currentOrderTitle: currentOrderTitle,
      currentOrderNode: currentOrderNode,
      currentOrderDeadline: currentOrderDeadline,
      bubbleBackgroundArgb: bubbleBackgroundArgb,
      bubbleForegroundArgb: bubbleForegroundArgb,
      bubbleBorderArgb: bubbleBorderArgb,
      bubbleAccentArgb: bubbleAccentArgb,
      focusEnabled: focusEnabled,
      focusStartedAt: focusStartedAt,
    );

    // A newer feature/order/theme sync may have arrived while config.json was
    // being persisted. Never let an older "off" request stop a newer "on"
    // request (or vice versa).
    if (requestGeneration != _requestGeneration) return;

    if (!enabled) {
      await _stopCurrentHost();
      return;
    }

    final existingStop = _stopInFlight;
    if (existingStop != null) {
      await existingStop;
      if (requestGeneration != _requestGeneration || !_enabledRequested) {
        return;
      }
    }
    if (_process != null) return;

    final existingStart = _startInFlight;
    if (existingStart != null) {
      await existingStart;
      return;
    }

    final startFuture = _startHost();
    _startInFlight = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_startInFlight, startFuture)) {
        _startInFlight = null;
      }
    }
  }

  Future<void> _startHost() async {
    if (_process != null) return;

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final host = File(
      '${executableDirectory.path}/desktop_pet/AdventurersGuild.DesktopPet.exe',
    );
    if (!await host.exists()) return;

    final config = await settings._configFile();
    try {
      final process = await Process.start(
        host.path,
        <String>[
          '--config',
          config.path,
          '--parent-pid',
          pid.toString(),
        ],
        mode: ProcessStartMode.detachedWithStdio,
      );
      if (!_enabledRequested) {
        try {
          process.kill();
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {}
        return;
      }
      _process = process;
      unawaited(
        process.exitCode.then<void>(
          (_) {
            if (identical(_process, process)) {
              _process = null;
            }
          },
          onError: (Object _, StackTrace __) {
            if (identical(_process, process)) {
              _process = null;
            }
          },
        ),
      );
    } catch (_) {
      _process = null;
    }
  }

  Future<void> stop() async {
    _requestGeneration++;
    _enabledRequested = false;
    await _stopCurrentHost();
  }

  Future<void> _stopCurrentHost() async {
    final existing = _stopInFlight;
    if (existing != null) {
      await existing;
      return;
    }

    final operation = _stopHost();
    _stopInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_stopInFlight, operation)) {
        _stopInFlight = null;
      }
    }
  }

  Future<void> _stopHost() async {
    final process = _process;
    _process = null;
    if (process == null) return;

    try {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Shutdown is best-effort; the host also watches the parent PID.
    }
  }

  void dispose() {
    unawaited(stop());
    settings.dispose();
  }
}
