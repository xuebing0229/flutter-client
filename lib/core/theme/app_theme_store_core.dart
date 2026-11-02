import 'package:flutter/material.dart';

import 'app_theme_palette.dart';
import 'app_ui_style.dart';

abstract class AppThemeStoreCore extends ChangeNotifier {
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
    final raw = await readPersistedTheme();
    if (raw == null) {
      notifyListeners();
      return;
    }

    try {
      final modeName = raw['mode'];
      _mode = switch (modeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

      _customPalettes.clear();
      final custom = raw['customPalettes'];
      if (custom is List) {
        for (final item in custom) {
          final palette = AppThemePalette.fromCustomJson(item);
          if (palette != null) _customPalettes.add(palette);
        }
      }

      final paletteId = raw['paletteId'];
      _paletteId = paletteId is String && _paletteById(paletteId) != null
          ? paletteId
          : AppThemePalettes.guildOriginal.id;

      final styleId = raw['style'];
      if (styleId is String) {
        _style = AppUiStyle.byId(styleId);
      } else {
        final legacyTextureId = raw['legacyTexture'];
        _style = legacyTextureId is String
            ? AppUiStyle.fromLegacyTextureId(legacyTextureId)
            : AppUiStyle.classic;
      }
    } catch (_) {
      _mode = ThemeMode.system;
      _paletteId = AppThemePalettes.guildOriginal.id;
      _style = AppUiStyle.classic;
      _customPalettes.clear();
    }
    notifyListeners();
  }

  /// Resets the selected appearance only. User-created palettes are data and
  /// must survive a reset, matching the long-standing native behavior.
  Future<void> resetToDefaults() async {
    final changed = _mode != ThemeMode.system ||
        _paletteId != AppThemePalettes.guildOriginal.id ||
        _style != AppUiStyle.classic;
    _mode = ThemeMode.system;
    _paletteId = AppThemePalettes.guildOriginal.id;
    _style = AppUiStyle.classic;
    if (changed) notifyListeners();
    await persistTheme(_snapshot());
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await persistTheme(_snapshot());
  }

  Future<void> setPaletteId(String paletteId) async {
    final resolved = _paletteById(paletteId) ?? AppThemePalettes.guildOriginal;
    if (_paletteId == resolved.id) return;
    _paletteId = resolved.id;
    notifyListeners();
    await persistTheme(_snapshot());
  }

  Future<void> setStyle(AppUiStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    await persistTheme(_snapshot());
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
    await persistTheme(_snapshot());
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
      if (palette == null) {
        throw const FormatException('自定义主题色内容不完整或已经损坏。');
      }
      if (!ids.add(palette.id)) {
        throw FormatException('自定义主题色包含重复 ID：${palette.id}');
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
    await persistTheme(_snapshot());
  }

  Future<void> deleteCustomPalette(String id) async {
    final before = _customPalettes.length;
    _customPalettes.removeWhere((item) => item.id == id);
    if (_customPalettes.length == before) return;
    if (_paletteId == id) {
      _paletteId = AppThemePalettes.guildOriginal.id;
    }
    notifyListeners();
    await persistTheme(_snapshot());
  }

  Map<String, dynamic> _snapshot() => <String, dynamic>{
        'mode': _mode.name,
        'paletteId': _paletteId,
        'style': _style.id,
        'customPalettes': exportCustomPalettes(),
      };

  Future<Map<String, dynamic>?> readPersistedTheme();

  Future<void> persistTheme(Map<String, dynamic> value);
}
