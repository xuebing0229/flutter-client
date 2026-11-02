import '../../../core/web/web_platform_bridge.dart';\nimport 'receipt_style_image_types.dart';

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

  Future<PickedReceiptStyleImage?> pickImage() async {
    final picked = await webPickImage();
    if (picked == null) return null;
    return PickedReceiptStyleImage(
      name: picked.name,
      bytes: picked.bytes,
    );
  }

  Future<bool> exportImage({
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
