import 'dart:typed_data';

import '../../../core/web/web_platform_bridge.dart';

class ThemeShareImageExporter {
  const ThemeShareImageExporter();

  Future<bool> export({
    required String fileName,
    required Uint8List bytes,
  }) async {
    webDownloadBytes(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'image/png',
    );
    return true;
  }
}
