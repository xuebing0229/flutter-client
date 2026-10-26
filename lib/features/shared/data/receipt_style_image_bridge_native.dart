import 'dart:io';
import 'dart:typed_data';

import '../../../core/portability/data_portability_file_bridge.dart';

class PickedReceiptStyleImage {
  const PickedReceiptStyleImage({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

class ReceiptStyleImageBridge {
  const ReceiptStyleImageBridge();

  static const DataPortabilityFileBridge _files =
      DataPortabilityFileBridge();

  Future<PickedReceiptStyleImage?> pickImage() async {
    final path = await _files.pickImage();
    if (path == null) return null;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final normalized = path.replaceAll('\\', '/');
      return PickedReceiptStyleImage(
        name: normalized.split('/').last,
        bytes: bytes,
      );
    } finally {
      if (Platform.isAndroid) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<bool> exportImage({
    required String fileName,
    required Uint8List bytes,
  }) {
    return _files.exportImage(
      fileName: fileName,
      bytes: bytes,
    );
  }
}
