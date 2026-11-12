import 'dart:typed_data';

import '../../../core/portability/data_portability_file_bridge.dart';

class ThemeShareImageExporter {
  const ThemeShareImageExporter();

  static const DataPortabilityFileBridge _files = DataPortabilityFileBridge();

  Future<bool> export({
    required String fileName,
    required Uint8List bytes,
  }) {
    return _files.exportImage(fileName: fileName, bytes: bytes);
  }
}
