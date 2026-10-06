import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme_palette.dart';

class AppThemeStore extends ChangeNotifier {
  Future<void> _persistTail = Future<void>.value();
  ThemeMode _mode = ThemeMode.system;
  String _paletteId = AppThemePalettes.guildOriginal.id;

  ThemeMode get mode => _mode;
  String get paletteId => _paletteId;
  AppThemePalette get palette => AppThemePalettes.byId(_paletteId);

  Future<File> _modeFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/theme-mode.txt');
  }

  Future<File> _paletteFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/theme-palette.txt');
  }

  Future<void> load() async {
    var changed = false;

    try {
      final file = await _modeFile();
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        final loaded = switch (value) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        if (loaded != _mode) {
          _mode = loaded;
          changed = true;
        }
      }
    } catch (_) {
      // Keep the safe default (follow system) if the mode file is unreadable.
    }

    try {
      final file = await _paletteFile();
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        final loaded = AppThemePalettes.byId(value).id;
        if (loaded != _paletteId) {
          _paletteId = loaded;
          changed = true;
        }
      }
    } catch (_) {
      // Keep the guild original palette if the palette file is unreadable.
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

    final operation = _persistTail.then<void>((_) async {
      try {
        final file = await _modeFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(_mode.name, flush: true);
      } catch (_) {
        // Theme switching should still work for this session.
      }
    });
    _persistTail = operation;
    await operation;
  }

  Future<void> setPaletteId(String paletteId) async {
    final resolved = AppThemePalettes.byId(paletteId);
    if (_paletteId == resolved.id) return;

    _paletteId = resolved.id;
    notifyListeners();

    final operation = _persistTail.then<void>((_) async {
      try {
        final file = await _paletteFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(_paletteId, flush: true);
      } catch (_) {
        // Palette switching should still work for this session.
      }
    });
    _persistTail = operation;
    await operation;
  }
}
