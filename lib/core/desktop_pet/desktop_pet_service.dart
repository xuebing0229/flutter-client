import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';
import '../sync/embedded_syncthing_bridge.dart';
import '../sync/sync_record_store.dart';

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

class DesktopPetBackupExport {
  const DesktopPetBackupExport({
    required this.manifest,
    required this.files,
  });

  final Map<String, dynamic> manifest;
  final Map<String, File> files;
}

class DesktopPetSettings extends ChangeNotifier {
  DesktopPetSettings();

  bool _loaded = false;
  Future<void>? _loadInFlight;
  Future<void>? _runtimePersistInFlight;
  Future<void> _persistTail = Future<void>.value();
  bool _enabled = false;
  final Set<String> _pendingAssetDeletes = <String>{};
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
  DateTime? _accountSyncRevision;
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
  DateTime? get accountSyncRevision => _accountSyncRevision;

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

  Future<bool> hasLocalConfigFile() async => (await _configFile()).exists();

  Future<void> _cleanupExplicitlyRemovedAssetsAtStartup() async {
    if (_pendingAssetDeletes.isEmpty) return;

    final root = await _rootDirectory();
    final managedRoot =
        Directory('${root.path}/presets').absolute.path.toLowerCase();
    final livePaths = <String>{
      for (final preset in _presets) ...<String>[
        if (preset.imageA != null) File(preset.imageA!).absolute.path,
        if (preset.imageB != null) File(preset.imageB!).absolute.path,
        if (preset.bubbleImage != null) File(preset.bubbleImage!).absolute.path,
      ],
    }.map((path) => path.toLowerCase()).toSet();

    final completed = <String>[];
    for (final rawPath in _pendingAssetDeletes) {
      final file = File(rawPath);
      final absolute = file.absolute.path;
      final normalized = absolute.toLowerCase();

      // Only delete exact files that a user explicitly removed from a preset.
      // Never infer "stale" assets from the current config, and never allow a
      // config entry to delete anything outside the desktop-pet asset folder.
      final managedPrefix = managedRoot.endsWith(Platform.pathSeparator)
          ? managedRoot
          : '$managedRoot${Platform.pathSeparator}';
      if (!normalized.startsWith(managedPrefix) ||
          livePaths.contains(normalized)) {
        completed.add(rawPath);
        continue;
      }

      try {
        if (await file.exists()) {
          await file.delete();
        }
        completed.add(rawPath);
      } catch (_) {
        // A file may still be locked briefly by Windows. Keep this exact,
        // explicitly requested deletion queued for a later launch.
      }
    }

    if (completed.isEmpty) return;
    _pendingAssetDeletes.removeAll(completed);
    await _persist();
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
    await _cleanupExplicitlyRemovedAssetsAtStartup();
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
      _accountSyncRevision = raw['accountSyncRevision'] is String
          ? DateTime.tryParse(raw['accountSyncRevision'] as String)?.toUtc()
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
      _pendingAssetDeletes
        ..clear()
        ..addAll(
          (raw['pendingAssetDeletes'] is List
                  ? raw['pendingAssetDeletes'] as List
                  : const <Object?>[])
              .whereType<String>(),
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

    } catch (_) {
      // The desktop pet is optional. A bad config must not affect work data.
    }
  }

  Future<DesktopPetBackupExport> exportForBackup() async {
    await load();
    final files = <String, File>{};

    Future<String?> registerAsset({
      required DesktopPetPreset preset,
      required String slot,
      required String? rawPath,
    }) async {
      if (rawPath == null || rawPath.trim().isEmpty) return null;
      final source = File(rawPath);
      if (!await source.exists()) {
        throw StateError('桌宠预设“${preset.name}”的图片文件已丢失，完整备份已取消。');
      }

      final lower = source.path.toLowerCase();
      final extension = lower.endsWith('.jpeg')
          ? '.jpeg'
          : lower.endsWith('.jpg')
              ? '.jpg'
              : '.png';
      final safePresetId = preset.id.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final relative =
          'desktop-pet/presets/$safePresetId/$slot$extension';
      files[relative] = source;
      return relative;
    }

    final presetPayloads = <Map<String, dynamic>>[];
    for (final preset in _presets) {
      final imageA = await registerAsset(
        preset: preset,
        slot: 'imageA',
        rawPath: preset.imageA,
      );
      final imageB = await registerAsset(
        preset: preset,
        slot: 'imageB',
        rawPath: preset.imageB,
      );
      final bubbleImage = await registerAsset(
        preset: preset,
        slot: 'bubbleImage',
        rawPath: preset.bubbleImage,
      );
      presetPayloads.add(<String, dynamic>{
        ...preset.toJson(),
        'imageA': imageA,
        'imageB': imageB,
        'bubbleImage': bubbleImage,
      });
    }

    return DesktopPetBackupExport(
      manifest: <String, dynamic>{
        'schema': 1,
        if (_accountSyncRevision != null)
          'syncRevision': _accountSyncRevision!.toUtc().toIso8601String(),
        'selectedPresetId': _selectedPresetId,
        'bubbleContentMode': _bubbleContentMode.name,
        'textMode': _textMode.name,
        'bubblePosition': _bubblePosition.name,
        'bubbleStyle': _bubbleStyle.name,
        'petScale': _petScale,
        'bubbleTextScale': _bubbleTextScale,
        'bubbleImageScale': _bubbleImageScale,
        'focusClockScale': _focusClockScale,
        'customText': _customText,
        'currentOrderId': _currentOrderId,
        'presets': presetPayloads,
      },
      files: files,
    );
  }

  Future<void> restoreFromBackup({
    required Object? rawManifest,
    required Directory extractedRoot,
  }) async {
    if (rawManifest is! Map) {
      throw const FormatException('桌宠备份设置格式无效。');
    }
    if (rawManifest['schema'] != 1) {
      throw const FormatException('不支持的桌宠备份版本。');
    }

    final rawPresets = rawManifest['presets'];
    if (rawPresets is! List) {
      throw const FormatException('桌宠备份缺少预设列表。');
    }

    final root = await _rootDirectory();
    final restored = <DesktopPetPreset>[];

    Future<String?> restoreAsset({
      required String presetId,
      required String presetName,
      required String slot,
      required Object? rawPath,
    }) async {
      if (rawPath == null) return null;
      if (rawPath is! String ||
          !rawPath.startsWith('desktop-pet/presets/')) {
        throw FormatException('桌宠预设“$presetName”的图片路径无效。');
      }
      final segments = rawPath.split('/');
      if (segments.length != 4 ||
          segments.any((segment) => segment.isEmpty || segment == '..')) {
        throw FormatException('桌宠预设“$presetName”的图片路径无效。');
      }

      final source = File(
        <String>[
          extractedRoot.path,
          ...segments,
        ].join(Platform.pathSeparator),
      );
      if (!await source.exists()) {
        throw FormatException('桌宠预设“$presetName”缺少 $slot 图片。');
      }

      final safePresetId = presetId.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final folder = Directory(
        '${root.path}${Platform.pathSeparator}presets'
        '${Platform.pathSeparator}$safePresetId',
      );
      await folder.create(recursive: true);
      final fileName = segments.last;
      final destination = File(
        '${folder.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}-$fileName',
      );
      await source.copy(destination.path);
      return destination.path;
    }

    for (final raw in rawPresets) {
      if (raw is! Map) {
        throw const FormatException('桌宠备份包含无效预设。');
      }
      final id = raw['id'];
      final name = raw['name'];
      if (id is! String || id.isEmpty || name is! String) {
        throw const FormatException('桌宠备份包含无效预设。');
      }
      final imageA = await restoreAsset(
        presetId: id,
        presetName: name,
        slot: 'A',
        rawPath: raw['imageA'],
      );
      final imageB = await restoreAsset(
        presetId: id,
        presetName: name,
        slot: 'B',
        rawPath: raw['imageB'],
      );
      final bubbleImage = await restoreAsset(
        presetId: id,
        presetName: name,
        slot: '气泡',
        rawPath: raw['bubbleImage'],
      );

      final normalized = <String, dynamic>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
        'imageA': imageA,
        'imageB': imageB,
        'bubbleImage': bubbleImage,
      };
      final preset = DesktopPetPreset.fromJson(normalized);
      if (preset == null) {
        throw const FormatException('桌宠备份包含无法读取的预设。');
      }
      restored.add(preset);
    }

    _presets
      ..clear()
      ..addAll(restored);
    final selected = rawManifest['selectedPresetId'];
    _selectedPresetId = selected is String &&
            _presets.any((preset) => preset.id == selected)
        ? selected
        : (_presets.isEmpty ? null : _presets.first.id);

    _bubbleContentMode =
        rawManifest['bubbleContentMode'] == DesktopPetBubbleContentMode.image.name
            ? DesktopPetBubbleContentMode.image
            : DesktopPetBubbleContentMode.text;
    _textMode = rawManifest['textMode'] == DesktopPetTextMode.custom.name
        ? DesktopPetTextMode.custom
        : DesktopPetTextMode.currentOrder;
    _bubblePosition =
        rawManifest['bubblePosition'] == DesktopPetBubblePosition.side.name
            ? DesktopPetBubblePosition.side
            : DesktopPetBubblePosition.above;
    _bubbleStyle =
        rawManifest['bubbleStyle'] == DesktopPetBubbleStyle.thought.name
            ? DesktopPetBubbleStyle.thought
            : DesktopPetBubbleStyle.speech;
    _petScale = ((rawManifest['petScale'] as num?)?.toDouble() ?? 1)
        .clamp(0.5, 1.8)
        .toDouble();
    _bubbleTextScale =
        ((rawManifest['bubbleTextScale'] as num?)?.toDouble() ?? 1)
            .clamp(0.65, 1.8)
            .toDouble();
    _bubbleImageScale =
        ((rawManifest['bubbleImageScale'] as num?)?.toDouble() ?? 1)
            .clamp(0.5, 2.0)
            .toDouble();
    _focusClockScale =
        ((rawManifest['focusClockScale'] as num?)?.toDouble() ?? 1)
            .clamp(0.65, 1.8)
            .toDouble();
    _customText =
        rawManifest['customText'] is String ? rawManifest['customText'] as String : '';
    _currentOrderId = rawManifest['currentOrderId'] is String
        ? rawManifest['currentOrderId'] as String
        : null;
    _accountSyncRevision = rawManifest['syncRevision'] is String
        ? DateTime.tryParse(rawManifest['syncRevision'] as String)?.toUtc()
        : _accountSyncRevision;
    _pendingAssetDeletes.clear();
    _loaded = true;
    await _persist();
    notifyListeners();
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

    // The user explicitly chose to delete this preset. Queue only these exact
    // app-managed files for later cleanup; never infer deletions from config.
    final removed = _presets[index];
    _pendingAssetDeletes.addAll(<String>[
      if (removed.imageA != null) removed.imageA!,
      if (removed.imageB != null) removed.imageB!,
      if (removed.bubbleImage != null) removed.bubbleImage!,
    ]);
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
    final removedPath = switch (slot) {
      DesktopPetAssetSlot.idleA => _presets[index].imageA,
      DesktopPetAssetSlot.keyB => _presets[index].imageB,
    };
    _presets[index] = switch (slot) {
      DesktopPetAssetSlot.idleA =>
        _presets[index].copyWith(clearImageA: true),
      DesktopPetAssetSlot.keyB =>
        _presets[index].copyWith(clearImageB: true),
    };
    if (removedPath != null) {
      _pendingAssetDeletes.add(removedPath);
    }
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
    final removedPath = _presets[index].bubbleImage!;
    _presets[index] = _presets[index].copyWith(clearBubbleImage: true);
    _pendingAssetDeletes.add(removedPath);
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
      'schema': 12,
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
      'accountSyncRevision': _accountSyncRevision?.toUtc().toIso8601String(),
      'presets': <Map<String, dynamic>>[
        for (final preset in _presets) preset.toJson(),
      ],
      'pendingAssetDeletes': _pendingAssetDeletes.toList()..sort(),
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


  Future<void> markAccountSyncRevision(DateTime revision) async {
    final normalized = revision.toUtc();
    if (_accountSyncRevision == normalized) return;
    _accountSyncRevision = normalized;
    await _persist();
  }

}

class DesktopPetAccountSync {
  DesktopPetAccountSync({
    required this.settings,
    SyncRecordStore? recordStore,
    EmbeddedSyncthingBridge bridge = const EmbeddedSyncthingBridge(),
  })  : _recordStore = recordStore ?? SyncRecordStore(),
        _bridge = bridge;

  final DesktopPetSettings settings;
  final SyncRecordStore _recordStore;
  final EmbeddedSyncthingBridge _bridge;
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace __) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<File> _manifestFile(String accountId) async {
    final root = await _recordStore.rootDirectory(accountId);
    return File(
      '${root.path}${Platform.pathSeparator}auxiliary'
      '${Platform.pathSeparator}desktop-pet'
      '${Platform.pathSeparator}manifest.json',
    );
  }

  Future<void> publish(String accountId) {
    return _enqueue(() => _publishUnlocked(accountId));
  }

  Future<void> _publishUnlocked(String accountId) async {
    await settings.load();
    final revision = DateTime.now().toUtc();
    final exported = await settings.exportForBackup();
    final root = await _recordStore.rootDirectory(accountId);

    for (final entry in exported.files.entries) {
      final destination = File(
        <String>[
          root.path,
          ...entry.key.split('/'),
        ].join(Platform.pathSeparator),
      );
      await destination.parent.create(recursive: true);
      if (entry.value.absolute.path != destination.absolute.path) {
        await entry.value.copy(destination.path);
      }
    }

    final manifest = <String, dynamic>{
      ...exported.manifest,
      'syncRevision': revision.toIso8601String(),
    };
    await atomicWriteString(
      await _manifestFile(accountId),
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    await settings.markAccountSyncRevision(revision);

    try {
      await _bridge.requestScan(accountId: accountId);
    } catch (_) {
      // Files already live in the shared account workspace and will be
      // discovered by the next normal Syncthing scan.
    }
  }

  Future<void> reconcile(String accountId) {
    return _enqueue(() async {
      await settings.load();
      final manifestFile = await _manifestFile(accountId);
      if (!await manifestFile.exists()) {
        if (await settings.hasLocalConfigFile()) {
          await _publishUnlocked(accountId);
        }
        return;
      }

      final raw = jsonDecode(await manifestFile.readAsString());
      if (raw is! Map || raw['schema'] != 1) {
        throw const FormatException('同步桌宠设置格式无效。');
      }
      final revisionRaw = raw['syncRevision'];
      if (revisionRaw is! String) {
        throw const FormatException('同步桌宠设置缺少版本时间。');
      }
      final remoteRevision = DateTime.tryParse(revisionRaw)?.toUtc();
      if (remoteRevision == null) {
        throw const FormatException('同步桌宠设置版本时间无效。');
      }

      final localRevision = settings.accountSyncRevision;
      if (localRevision != null && !remoteRevision.isAfter(localRevision)) {
        return;
      }

      final root = await _recordStore.rootDirectory(accountId);
      await settings.restoreFromBackup(
        rawManifest: raw,
        extractedRoot: root,
      );
      await settings.markAccountSyncRevision(remoteRevision);
    });
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
