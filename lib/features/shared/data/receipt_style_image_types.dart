import 'dart:typed_data';

class PickedReceiptStyleImage {
  const PickedReceiptStyleImage({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}
