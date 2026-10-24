import 'dart:convert';
import 'dart:js_interop';

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';
import 'web_screenshot_files.dart';

@JS('adventurersGuildOcrRecognize')
external JSPromise<JSString> _recognizeScreenshot(JSString base64Data);

@JS('adventurersGuildOcrRelease')
external JSPromise<JSString> _releaseScreenshotOcr();

class ScreenshotOcrService {
  const ScreenshotOcrService();

  bool get supported => true;

  String get engineLabel => '官方 PaddleOCR.js PP-OCRv6 Small';

  Future<String?> lastNativeCrashReport() async => null;

  Future<void> release() async {
    try {
      await _releaseScreenshotOcr().toDart;
    } catch (_) {
      // Releasing a browser OCR session is best-effort.
    }
  }

  Future<ScreenshotOcrResult> recognize(String imageToken) async {
    final encoded = base64Encode(WebScreenshotFiles.bytes(imageToken));
    final source = (await _recognizeScreenshot(encoded.toJS).toDart).toDart;
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException('浏览器 OCR 返回格式无效');
    }

    double number(Object? raw, String field) {
      if (raw is num) return raw.toDouble();
      throw FormatException('浏览器 OCR 缺少 $field');
    }

    final rawLines = value['lines'];
    if (rawLines is! List) {
      throw const FormatException('浏览器 OCR 文字行格式无效');
    }
    final lines = <ScreenshotTextLine>[];
    for (final item in rawLines) {
      if (item is! Map || item['text'] is! String) continue;
      lines.add(
        ScreenshotTextLine(
          text: item['text'] as String,
          left: number(item['left'], 'left'),
          top: number(item['top'], 'top'),
          right: number(item['right'], 'right'),
          bottom: number(item['bottom'], 'bottom'),
          confidence: item['confidence'] is num
              ? (item['confidence'] as num).toDouble()
              : 1,
        ),
      );
    }

    final width = number(value['imageWidth'], 'imageWidth');
    final height = number(value['imageHeight'], 'imageHeight');
    if (width <= 0 || height <= 0) {
      throw const FormatException('浏览器 OCR 图片尺寸无效');
    }
    return ScreenshotOcrResult(
      width: width,
      height: height,
      lines: List<ScreenshotTextLine>.unmodifiable(lines),
      nativeTrace: const <String>[
        'PaddleOCR.js · PP-OCRv6 Small · browser WASM',
      ],
    );
  }
}
