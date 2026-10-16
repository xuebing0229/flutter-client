import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../portability/data_portability_file_bridge.dart';
import 'app_theme_palette.dart';

class SharedThemePreset {
  const SharedThemePreset({
    required this.name,
    required this.seed,
    required this.advanced,
    required this.light,
    required this.dark,
  });

  final String name;
  final Color seed;
  final bool advanced;
  final AppThemeSemanticColors light;
  final AppThemeSemanticColors dark;

  AppThemePalette toPalette() => AppThemePalette.custom(
        id: 'custom:import-preview',
        name: name,
        seed: seed,
        light: light,
        dark: dark,
        advanced: advanced,
      );
}

class ThemePaletteTransferCodec {
  const ThemePaletteTransferCodec();

  static const String sharePrefix = 'AGTHEME1:';
  static const int schema = 1;
  static const String kind = 'adventurers-guild-theme';

  String encodeFile(AppThemePalette palette) {
    final payload = _payloadFor(palette);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String encodeShareCode(AppThemePalette palette) {
    final json = jsonEncode(_payloadFor(palette));
    final data = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
    return '$sharePrefix$data';
  }

  SharedThemePreset decode(String raw) {
    final trimmed = raw.trim();
    final jsonText = trimmed.startsWith(sharePrefix)
        ? _decodeShareCode(trimmed.substring(sharePrefix.length))
        : trimmed;

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('这不是有效的主题配色数据。');
    }
    if (decoded['kind'] != kind || decoded['schema'] != schema) {
      throw const FormatException('这不是受支持的冒险者公会主题配色。');
    }

    final name = decoded['name'];
    final seed = decoded['seed'];
    final advanced = decoded['advanced'];
    final light = AppThemeSemanticColors.fromJson(decoded['light']);
    final dark = AppThemeSemanticColors.fromJson(decoded['dark']);

    if (name is! String ||
        name.trim().isEmpty ||
        seed is! int ||
        advanced is! bool ||
        light == null ||
        dark == null) {
      throw const FormatException('主题配色内容不完整或已经损坏。');
    }

    final trimmedName = name.trim();
    final safeName = trimmedName.length > 32
        ? trimmedName.substring(0, 32)
        : trimmedName;

    return SharedThemePreset(
      name: safeName,
      seed: Color(seed),
      advanced: advanced,
      light: light,
      dark: dark,
    );
  }

  Map<String, dynamic> _payloadFor(AppThemePalette palette) {
    final light = palette.lightSemanticColors;
    final dark = palette.darkSemanticColors;
    if (!palette.isCustom || light == null || dark == null) {
      throw StateError('只有完整的自定义配色方案可以分享。');
    }

    return <String, dynamic>{
      'kind': kind,
      'schema': schema,
      'name': palette.name,
      'seed': palette.lightSeed.toARGB32(),
      'advanced': palette.customAdvanced,
      'light': light.toJson(),
      'dark': dark.toJson(),
    };
  }

  String _decodeShareCode(String encoded) {
    try {
      final normalized = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      throw const FormatException('分享码无法识别，请确认内容是否完整。');
    }
  }
}

class ThemePaletteTransferService {
  const ThemePaletteTransferService({
    ThemePaletteTransferCodec codec = const ThemePaletteTransferCodec(),
    DataPortabilityFileBridge fileBridge =
        const DataPortabilityFileBridge(),
  })  : _codec = codec,
        _fileBridge = fileBridge;

  final ThemePaletteTransferCodec _codec;
  final DataPortabilityFileBridge _fileBridge;

  String shareCode(AppThemePalette palette) => _codec.encodeShareCode(palette);

  SharedThemePreset decode(String raw) => _codec.decode(raw);

  Future<bool> exportPalette(AppThemePalette palette) async {
    final temporary = await Directory.systemTemp.createTemp(
      'adventurers-guild-theme-',
    );
    final safeName = _safeFileName(palette.name);
    final file = File(
      '${temporary.path}${Platform.pathSeparator}$safeName.agtheme',
    );

    try {
      await file.writeAsString(_codec.encodeFile(palette), flush: true);
      return await _fileBridge.exportLocalFile(
        sourcePath: file.path,
        fileName: '$safeName.agtheme',
        mimeType: 'application/json',
      );
    } finally {
      try {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<SharedThemePreset?> importFromFile() async {
    final picked = await _fileBridge.pickThemePresetFile();
    if (picked == null) return null;

    final file = File(picked.path);
    try {
      final name = picked.name.toLowerCase();
      if (!name.endsWith('.agtheme') && !name.endsWith('.json')) {
        throw const FormatException(
          '请选择 .agtheme 主题配色文件。',
        );
      }
      return _codec.decode(await file.readAsString());
    } finally {
      if (picked.temporary) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? '冒险者公会配色' : cleaned;
  }
}
