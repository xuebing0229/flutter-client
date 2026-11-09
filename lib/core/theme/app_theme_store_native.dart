import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_theme_store_core.dart';

class AppThemeStore extends AppThemeStoreCore {
  Future<void> _persistTail = Future<void>.value();

  Future<Directory> _dir() => getApplicationSupportDirectory();
  Future<File> _modeFile() async => File('${(await _dir()).path}/theme-mode.txt');
  Future<File> _paletteFile() async => File('${(await _dir()).path}/theme-palette.txt');
  Future<File> _customPalettesFile() async =>
      File('${(await _dir()).path}/theme-custom-palettes.json');
  Future<File> _styleFile() async => File('${(await _dir()).path}/ui-style.txt');
  Future<File> _imageThemeFile() async =>
      File('${(await _dir()).path}/theme-image.json');
  Future<File> _legacyTextureFile() async =>
      File('${(await _dir()).path}/ui-texture.txt');

  @override
  Future<Map<String, dynamic>?> readPersistedTheme() async {
    final result = <String, dynamic>{};
    try {
      final file = await _modeFile();
      if (await file.exists()) result['mode'] = (await file.readAsString()).trim();
    } catch (_) {}
    try {
      final file = await _customPalettesFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) result['customPalettes'] = raw;
      }
    } catch (_) {}
    try {
      final file = await _paletteFile();
      if (await file.exists()) {
        result['paletteId'] = (await file.readAsString()).trim();
      }
    } catch (_) {}
    try {
      final file = await _styleFile();
      if (await file.exists()) {
        result['style'] = (await file.readAsString()).trim();
      } else {
        final legacy = await _legacyTextureFile();
        if (await legacy.exists()) {
          result['legacyTexture'] = (await legacy.readAsString()).trim();
        }
      }
    } catch (_) {}
    try {
      final file = await _imageThemeFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) {
          for (final key in const <String>[
            'appearanceMode',
            'imageBackgroundMode',
            'imageBackgroundBase64',
            'imageBackgroundName',
            'imageFontColorValue',
          ]) {
            if (raw.containsKey(key)) result[key] = raw[key];
          }
        }
      }
    } catch (_) {}
    return result.isEmpty ? null : result;
  }

  @override
  Future<void> persistTheme(Map<String, dynamic> value) {
    final operation = _persistTail.then<void>((_) async {
      try {
        final mode = await _modeFile();
        final palette = await _paletteFile();
        final custom = await _customPalettesFile();
        final style = await _styleFile();
        final imageTheme = await _imageThemeFile();
        await mode.parent.create(recursive: true);
        await Future.wait<void>([
          mode.writeAsString(value['mode']?.toString() ?? 'system', flush: true),
          palette.writeAsString(
            value['paletteId']?.toString() ?? '',
            flush: true,
          ),
          custom.writeAsString(
            jsonEncode(value['customPalettes'] ?? const <Object>[]),
            flush: true,
          ),
          style.writeAsString(
            value['style']?.toString() ?? 'classic',
            flush: true,
          ),
          imageTheme.writeAsString(
            jsonEncode(<String, dynamic>{
              'appearanceMode': value['appearanceMode']?.toString() ?? 'color',
              'imageBackgroundMode':
                  value['imageBackgroundMode']?.toString() ?? 'glass',
              if (value['imageBackgroundBase64'] != null)
                'imageBackgroundBase64': value['imageBackgroundBase64'],
              if (value['imageBackgroundName'] != null)
                'imageBackgroundName': value['imageBackgroundName'],
              'imageFontColorValue':
                  value['imageFontColorValue'] ?? defaultImageFontColorValue,
            }),
            flush: true,
          ),
        ]);
      } catch (_) {
        // Appearance changes remain usable for the current session.
      }
    });
    _persistTail = operation;
    return operation;
  }
}
