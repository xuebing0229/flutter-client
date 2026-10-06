import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'app_theme_palette.dart';

class AppThemeStore extends ChangeNotifier {
  static const String _modeKey = 'adventurers-guild.web.theme-mode.v1';
  static const String _paletteKey = 'adventurers-guild.web.theme-palette.v1';

  ThemeMode _mode = ThemeMode.system;
  String _paletteId = AppThemePalettes.guildOriginal.id;

  ThemeMode get mode => _mode;
  String get paletteId => _paletteId;
  AppThemePalette get palette => AppThemePalettes.byId(_paletteId);

  Future<void> load() async {
    var changed = false;
    try {
      final mode = html.window.localStorage[_modeKey];
      final loadedMode = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (loadedMode != _mode) {
        _mode = loadedMode;
        changed = true;
      }

      final paletteId = html.window.localStorage[_paletteKey];
      if (paletteId != null && AppThemePalettes.containsId(paletteId)) {
        final resolved = AppThemePalettes.byId(paletteId).id;
        if (resolved != _paletteId) {
          _paletteId = resolved;
          changed = true;
        }
      }
    } catch (_) {
      // Safari private mode may reject persistent storage. Session state still works.
    }
    if (changed) notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await setMode(ThemeMode.system);
    await setPaletteId(AppThemePalettes.guildOriginal.id);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      html.window.localStorage[_modeKey] = mode.name;
    } catch (_) {}
  }

  Future<void> setPaletteId(String paletteId) async {
    final resolved = AppThemePalettes.byId(paletteId);
    if (_paletteId == resolved.id) return;
    _paletteId = resolved.id;
    notifyListeners();
    try {
      html.window.localStorage[_paletteKey] = _paletteId;
    } catch (_) {}
  }
}
