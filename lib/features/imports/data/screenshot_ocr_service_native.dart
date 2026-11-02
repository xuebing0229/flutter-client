import 'dart:io';

import 'package:flutter/services.dart';

import 'screenshot_ocr_result.dart';
import 'screenshot_ocr_result_parser.dart';
import 'windows_official_paddleocr.dart';

/// The native recognizer only sends recognized line text and boxes.
/// No screenshot or OCR output is uploaded to a remote service.
class ScreenshotOcrService {
  const ScreenshotOcrService();

  static const MethodChannel _channel = MethodChannel('app.screenshot_ocr');

  bool get supported => Platform.isAndroid || Platform.isWindows;

  String get engineLabel => Platform.isAndroid
      ? '官方 PaddleOCR PP-OCRv6 Small'
      : 'RapidOCR ONNX Windows';

  /// Reads local Android process-exit diagnostics. No image or OCR text is sent.
  Future<String?> lastNativeCrashReport() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('lastCrashReport');
  }

  /// Explicitly release native ONNX sessions after the selected-image batch.
  /// Windows OCR uses short-lived resources inside recognize().
  Future<void> release() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('release');
    }
  }

  Future<ScreenshotOcrResult> recognize(String imagePath) async {
    if (Platform.isWindows) {
      return const WindowsOfficialPaddleOcr().recognize(imagePath);
    }
    if (!supported) {
      throw UnsupportedError('当前平台暂不支持截图识别');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'recognize',
      {'path': imagePath},
    );
    if (result == null) throw const FormatException('截图识别未返回结果');

    return parseScreenshotOcrPayload(result);

  }
}
