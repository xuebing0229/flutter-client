import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/account/qr_image_decoder.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/theme_palette_transfer.dart';
import 'theme_color_page_shared.dart';
import 'theme_share_scan_page.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({
    required this.store,
    this.onBack,
    super.key,
  });

  static const _files = DataPortabilityFileBridge();
  static const _transfer = ThemePaletteTransferService();

  final AppThemeStore store;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SharedThemeColorPage(
      store: store,
      onBack: onBack,
      importFromShareImage: _importFromShareImage,
      qrScannerBuilder: Platform.isAndroid
          ? () => const ThemeShareScanPage()
          : null,
    );
  }

  static Future<SharedThemePreset?> _importFromShareImage() async {
    final path = await _files.pickQrImage();
    if (path == null) return null;
    try {
      final raw = decodeQrImage(await File(path).readAsBytes()).trim();
      if (raw.isEmpty) {
        throw const FormatException('所选图片中没有识别到配色二维码。');
      }
      return _transfer.decode(raw);
    } finally {
      if (Platform.isAndroid) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }
}
