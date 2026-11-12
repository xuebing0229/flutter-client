import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import '../web/web_platform_bridge.dart';
import 'app_theme_palette.dart';
import 'theme_palette_transfer_codec.dart';

class ThemePaletteTransferService {
  const ThemePaletteTransferService({
    ThemePaletteTransferCodec codec = const ThemePaletteTransferCodec(),
  }) : _codec = codec;

  final ThemePaletteTransferCodec _codec;

  String shareCode(AppThemePalette palette) => _codec.encodeShareCode(palette);
  SharedThemePreset decode(String raw) => _codec.decode(raw);

  Future<bool> exportPalette(AppThemePalette palette) async {
    final safeName = safeThemePresetFileName(palette.name);
    final bytes = utf8.encode(_codec.encodeFile(palette));
    webDownloadBytes(
      fileName: '$safeName.agtheme',
      bytes: bytes,
      mimeType: 'application/json',
    );
    return true;
  }

  Future<SharedThemePreset?> importFromFile() async {
    const typeGroup = XTypeGroup(
      label: '冒险者公会主题配色',
      extensions: <String>['agtheme', 'json'],
    );
    final picked =
        await openFile(acceptedTypeGroups: const <XTypeGroup>[typeGroup]);
    if (picked == null) return null;
    final name = picked.name.toLowerCase();
    if (!name.endsWith('.agtheme') && !name.endsWith('.json')) {
      throw const FormatException('请选择 .agtheme 主题配色文件。');
    }
    return _codec.decode(await picked.readAsString());
  }
}
