import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';
import 'web_screenshot_files.dart';

class ScreenshotOcrService {
  const ScreenshotOcrService();

  bool get supported => true;

  Future<String?> lastNativeCrashReport() async => null;

  Future<void> release() async {
    if (!js_util.hasProperty(html.window, 'adventurersGuildOcrRelease')) return;
    try {
      final promise = js_util.callMethod<Object?>(
        html.window,
        'adventurersGuildOcrRelease',
        const <Object?>[],
      );
      if (promise != null) await js_util.promiseToFuture<Object?>(promise as Object);
    } catch (_) {}
  }

  Future<ScreenshotOcrResult> recognize(String imageToken) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (js_util.hasProperty(html.window, 'adventurersGuildOcrRecognize')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!js_util.hasProperty(html.window, 'adventurersGuildOcrRecognize')) {
      throw StateError('浏览器 OCR 模块没有加载完成，请联网后重试。');
    }

    final blob = html.Blob(<Object>[WebScreenshotFiles.bytes(imageToken)]);
    final promise = js_util.callMethod<Object?>(
      html.window,
      'adventurersGuildOcrRecognize',
      <Object?>[blob],
    );
    final result = await js_util.promiseToFuture<Object?>(promise as Object);
    final value = js_util.dartify(result);
    if (value is! Map) throw const FormatException('浏览器 OCR 返回格式无效');

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
