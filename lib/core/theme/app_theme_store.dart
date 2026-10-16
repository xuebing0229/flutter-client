import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme_palette.dart';
import 'app_ui_style.dart';

class AppThemeStore extends ChangeNotifier {
  Future<void> _persistTail = Future<void>.value();
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

  Future<File> _modeFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/theme-mode.txt');
  }

  Future<File> _paletteFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/theme-palette.txt');
  }

  Future<File> _customPalettesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/theme-custom-palettes.json');
  }

  Future<File> _styleFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ui-style.txt');
  }

  Future<File> _legacyTextureFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ui-texture.txt');
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
      final file = await _customPalettesFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          final loaded = <AppThemePalette>[];
          for (final item in raw) {
            final palette = AppThemePalette.fromCustomJson(item);
            if (palette != null) loaded.add(palette);
          }
          _customPalettes
            ..clear()
            ..addAll(loaded);
          changed = loaded.isNotEmpty;
        }
      }
    } catch (_) {
      // A broken custom-palette file must not block app startup.
    }

    try {
      final file = await _paletteFile();
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        final loaded = _paletteById(value)?.id ??
            AppThemePalettes.guildOriginal.id;
        if (loaded != _paletteId) {
          _paletteId = loaded;
          changed = true;
        }
      }
    } catch (_) {
      // Keep the guild original palette if the palette file is unreadable.
    }

    try {
      final file = await _styleFile();
      AppUiStyle? loaded;
      if (await file.exists()) {
        loaded = AppUiStyle.byId((await file.readAsString()).trim());
      } else {
        final legacyFile = await _legacyTextureFile();
        if (await legacyFile.exists()) {
          loaded = AppUiStyle.fromLegacyTextureId(
            (await legacyFile.readAsString()).trim(),
          );
        }
      }
      if (loaded != null && loaded != _style) {
        _style = loaded;
        changed = true;
      }
    } catch (_) {
      // Keep the classic UI style if the saved style is unreadable.
    }

    if (changed) notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await setMode(ThemeMode.system);
    await setPaletteId(AppThemePalettes.guildOriginal.id);
    await setStyle(AppUiStyle.classic);
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
    final resolved =
        _paletteById(paletteId) ?? AppThemePalettes.guildOriginal;
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

    final index =
        _customPalettes.indexWhere((item) => item.id == resolvedId);
    if (index >= 0) {
      _customPalettes[index] = palette;
    } else {
      _customPalettes.add(palette);
    }
    if (select) _paletteId = palette.id;
    notifyListeners();

    final operation = _persistTail.then<void>((_) async {
      await _persistCustomPalettes();
      if (select) {
        try {
          final file = await _paletteFile();
          await file.parent.create(recursive: true);
          await file.writeAsString(_paletteId, flush: true);
        } catch (_) {
          // Keep the selected custom palette for this session.
        }
      }
    });
    _persistTail = operation;
    await operation;
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

    final operation = _persistTail.then<void>((_) async {
      await _persistCustomPalettes();
      try {
        final file = await _paletteFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(_paletteId, flush: true);
      } catch (_) {}
    });
    _persistTail = operation;
    await operation;
  }

  Future<void> deleteCustomPalette(String id) async {
    final before = _customPalettes.length;
    _customPalettes.removeWhere((item) => item.id == id);
    if (_customPalettes.length == before) return;

    final wasSelected = _paletteId == id;
    if (wasSelected) {
      _paletteId = AppThemePalettes.guildOriginal.id;
    }
    notifyListeners();

    final operation = _persistTail.then<void>((_) async {
      await _persistCustomPalettes();
      if (wasSelected) {
        try {
          final file = await _paletteFile();
          await file.parent.create(recursive: true);
          await file.writeAsString(_paletteId, flush: true);
        } catch (_) {}
      }
    });
    _persistTail = operation;
    await operation;
  }

  Future<void> _persistCustomPalettes() async {
    try {
      final file = await _customPalettesFile();
      await file.parent.create(recursive: true);
      final payload = <Map<String, dynamic>>[
        for (final palette in _customPalettes) palette.toCustomJson(),
      ];
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
    } catch (_) {
      // Theme editing remains usable for the session if persistence fails.
    }
  }

  Future<void> setStyle(AppUiStyle style) async {
    if (_style == style) return;

    _style = style;
    notifyListeners();

    final operation = _persistTail.then<void>((_) async {
      try {
        final file = await _styleFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(_style.id, flush: true);
      } catch (_) {
        // Style switching should still work for this session.
      }
    });
    _persistTail = operation;
    await operation;
  }
}
