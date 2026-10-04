import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String decodeQrImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('无法读取所选图片。请选择 PNG 或 JPG 图片。');
  }
  final pixels = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr);
  final source = RGBLuminanceSource(
    image.width,
    image.height,
    pixels.buffer.asInt32List(pixels.offsetInBytes, pixels.lengthInBytes ~/ 4),
  );
  try {
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
  } on ReaderException {
    throw const FormatException('所选图片中没有识别到二维码。');
  }
}
