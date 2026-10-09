import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';
import 'windows_rapidocr_onnx.dart';

/// The native recognizer only sends recognized line text and boxes.
/// No screenshot or OCR output is uploaded to a remote service.
class ScreenshotOcrService {
  const ScreenshotOcrService();

  static const MethodChannel _channel = MethodChannel('app.screenshot_ocr');

  bool get supported => Platform.isAndroid || Platform.isWindows;

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
      return const WindowsRapidOcrOnnx().recognize(imagePath);
    }
    if (!supported) {
      throw UnsupportedError('当前平台尚未接入本地截图识别引擎');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'recognize',
      {'path': imagePath},
    );
    if (result == null) throw const FormatException('OCR 未返回识别结果');

    double number(Object? value, String field) {
      if (value is num) return value.toDouble();
      throw FormatException('识别坐标缺少 $field');
    }

    final raw = result['lines'];
    if (raw is! List) throw const FormatException('OCR 文字行格式错误');
    final lines = <ScreenshotTextLine>[];
    for (final value in raw) {
      if (value is! Map || value['text'] is! String) continue;
      lines.add(ScreenshotTextLine(
        text: value['text'] as String,
        recoveredFromCrop: value['recoveredFromCrop'] == true,
        left: number(value['left'], 'left'),
        top: number(value['top'], 'top'),
        right: number(value['right'], 'right'),
        bottom: number(value['bottom'], 'bottom'),
      ));
    }
    final width = number(result['imageWidth'], 'imageWidth');
    final height = number(result['imageHeight'], 'imageHeight');
    if (width <= 0 || height <= 0) {
      throw const FormatException('OCR 图片尺寸无效');
    }
    return ScreenshotOcrResult(
      width: width,
      height: height,
      lines: List.unmodifiable(lines),
      nativeTrace: List<String>.unmodifiable(
        (result['nativeTrace'] is List)
            ? (result['nativeTrace'] as List).whereType<String>()
            : const <String>[],
      ),
    );
  }
}
