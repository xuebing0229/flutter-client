import 'dart:convert';
import 'dart:js_interop';

import 'screenshot_ocr_result.dart';
import 'screenshot_ocr_result_parser.dart';
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
      throw const FormatException('截图识别结果格式无效');
    }

    return parseScreenshotOcrPayload(
      value,
      fallbackTrace: const <String>[
        'PaddleOCR.js · PP-OCRv6 Small · browser WASM',
      ],
    );

  }
}
