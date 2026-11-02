import 'dart:io';

import '../portability/data_portability_file_bridge.dart';
import 'app_theme_palette.dart';
import 'theme_palette_transfer_codec.dart';

class ThemePaletteTransferService {
  const ThemePaletteTransferService({
    ThemePaletteTransferCodec codec = const ThemePaletteTransferCodec(),
    DataPortabilityFileBridge fileBridge = const DataPortabilityFileBridge(),
  })  : _codec = codec,
        _fileBridge = fileBridge;

  final ThemePaletteTransferCodec _codec;
  final DataPortabilityFileBridge _fileBridge;

  String shareCode(AppThemePalette palette) => _codec.encodeShareCode(palette);
  SharedThemePreset decode(String raw) => _codec.decode(raw);

  Future<bool> exportPalette(AppThemePalette palette) async {
    final temporary =
        await Directory.systemTemp.createTemp('adventurers-guild-theme-');
    final safeName = safeThemePresetFileName(palette.name);
    final file = File(
      '${temporary.path}${Platform.pathSeparator}$safeName.agtheme',
    );
    try {
      await file.writeAsString(_codec.encodeFile(palette), flush: true);
      return _fileBridge.exportLocalFile(
        sourcePath: file.path,
        fileName: '$safeName.agtheme',
        mimeType: 'application/json',
      );
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete(recursive: true);
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
        throw const FormatException('请选择 .agtheme 主题配色文件。');
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
}
