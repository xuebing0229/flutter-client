import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_theme_palette.dart';
import 'app_ui_style.dart';
import '../web/web_platform_bridge.dart';

class AppThemeStore extends ChangeNotifier {
  static const String _storageKey = 'adventurers-guild.pwa.theme.v2';

  ThemeMode _mode = ThemeMode.system;
  String _paletteId = AppThemePalettes.guildOriginal.id;
  AppUiStyle _style = AppUiStyle.classic;
  final List<AppThemePalette> _customPalettes = <AppThemePalette>[];

  ThemeMode get mode => _mode;
  String get paletteId => _paletteId;
  AppUiStyle get style => _style;
  List<AppThemePalette> get customPalettes =>
      List<AppThemePalette>.unmodifiable(_customPalettes);

  AppThemePalette get palette =>
      _paletteById(_paletteId) ?? AppThemePalettes.guildOriginal;

  bool containsPaletteId(String id) => _paletteById(id) != null;

  List<Map<String, dynamic>> exportCustomPalettes() => <Map<String, dynamic>>[
        for (final palette in _customPalettes) palette.toCustomJson(),
      ];

  AppThemePalette? _paletteById(String id) {
    for (final palette in _customPalettes) {
      if (palette.id == id) return palette;
    }
    if (AppThemePalettes.containsId(id)) return AppThemePalettes.byId(id);
    return null;
  }

  Future<void> load() async {
    try {
      final source = webStorageGet(_storageKey);
      if (source == null || source.trim().isEmpty) {
        notifyListeners();
        return;
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map) return;

      final mode = decoded['mode'];
      _mode = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

      final custom = decoded['customPalettes'];
      _customPalettes.clear();
      if (custom is List) {
        for (final item in custom) {
          final palette = AppThemePalette.fromCustomJson(item);
          if (palette != null) _customPalettes.add(palette);
        }
      }

      final paletteId = decoded['paletteId'];
      if (paletteId is String && _paletteById(paletteId) != null) {
        _paletteId = paletteId;
      }

      final styleId = decoded['style'];
      _style = styleId is String
          ? AppUiStyle.byId(styleId)
          : AppUiStyle.classic;
    } catch (_) {
      _mode = ThemeMode.system;
      _paletteId = AppThemePalettes.guildOriginal.id;
      _style = AppUiStyle.classic;
      _customPalettes.clear();
    }
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _mode = ThemeMode.system;
    _paletteId = AppThemePalettes.guildOriginal.id;
    _style = AppUiStyle.classic;
    _customPalettes.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setPaletteId(String paletteId) async {
    final resolved = _paletteById(paletteId) ?? AppThemePalettes.guildOriginal;
    if (_paletteId == resolved.id) return;
    _paletteId = resolved.id;
    notifyListeners();
    await _persist();
  }

  Future<void> setStyle(AppUiStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    await _persist();
  }

  Future<AppThemePalette> saveCustomPalette({
    String? id,
    required String name,
    required Color seed,
    required AppThemeSemanticColors light,
    required AppThemeSemanticColors dark,
    required bool advanced,
    bool select = true,
  }) async {
    final resolvedId = id != null && id.startsWith('custom:')
        ? id
        : 'custom:${DateTime.now().microsecondsSinceEpoch}';
    final palette = AppThemePalette.custom(
      id: resolvedId,
      name: name,
      seed: seed,
      light: light,
      dark: dark,
      advanced: advanced,
    );
    final index = _customPalettes.indexWhere((item) => item.id == resolvedId);
    if (index >= 0) {
      _customPalettes[index] = palette;
    } else {
      _customPalettes.add(palette);
    }
    if (select) _paletteId = palette.id;
    notifyListeners();
    await _persist();
    return palette;
  }

  Future<void> replaceCustomPalettesFromJson(Object? raw) async {
    if (raw is! List) {
      throw const FormatException('自定义主题色设置格式无效。');
    }
    final next = <AppThemePalette>[];
    final ids = <String>{};
    for (final item in raw) {
      final palette = AppThemePalette.fromCustomJson(item);
      if (palette == null || !ids.add(palette.id)) {
        throw const FormatException('自定义主题色内容不完整或重复。');
      }
      next.add(palette);
    }
    _customPalettes
      ..clear()
      ..addAll(next);
    if (_paletteId.startsWith('custom:') && _paletteById(_paletteId) == null) {
      _paletteId = AppThemePalettes.guildOriginal.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> deleteCustomPalette(String id) async {
    final before = _customPalettes.length;
    _customPalettes.removeWhere((item) => item.id == id);
    if (_customPalettes.length == before) return;
    if (_paletteId == id) {
      _paletteId = AppThemePalettes.guildOriginal.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      webStorageSet(
        _storageKey,
        jsonEncode(<String, dynamic>{
          'mode': _mode.name,
          'paletteId': _paletteId,
          'style': _style.id,
          'customPalettes': exportCustomPalettes(),
        }),
      );
    } catch (_) {
      // Theme remains usable for the current browser session.
    }
  }
}
