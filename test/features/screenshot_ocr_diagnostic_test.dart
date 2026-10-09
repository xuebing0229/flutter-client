import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/data/screenshot_ocr_diagnostic.dart';
import 'package:flutter_app/features/imports/data/screenshot_ocr_result.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';

void main() {
  test('diagnostics include actual OCR lines and independently parsed fields', () {
    final text = formatScreenshotOcrDiagnostic(
      screenshotNumber: 2,
      ocr: const ScreenshotOcrResult(
        width: 698,
        height: 1536,
        lines: [
          ScreenshotTextLine(
            text: 'y94', left: 278, top: 443, right: 320, bottom: 462,
          ),
          ScreenshotTextLine(
            text: '【常驻】虚构盒子', left: 285, top: 397,
            right: 536, bottom: 424,
          ),
        ],
      ),
      route: '排单列表',
      platform: '米画师',
      parsedRows: ['图名=【常驻】虚构盒子 | 稿价=94'],
    );
    expect(text, contains('截图 2'));
    expect(text, contains('698 × 1536'));
    expect(text, contains('[278,443,320,462] y94'));
    expect(text.indexOf('【常驻】虚构盒子'),
        lessThan(text.indexOf('[278,443,320,462] y94')));
    expect(text, contains('解析出的记录 (1 条)'));
    expect(text, contains('稿价=94'));
    expect(text, isNot(contains('file://')));
  });

  test('zero parsed rows still retain OCR evidence for failures', () {
    final report = formatScreenshotOcrDiagnostic(
      screenshotNumber: 1,
      ocr: const ScreenshotOcrResult(
        width: 400, height: 900, lines: [],
      ),
      route: '无法确定',
      platform: '待选择',
      parsedRows: const [],
    );
    expect(report, contains('原始 OCR (0 行'));
    expect(report, contains('解析出的记录 (0 条)'));
  });

  test('native missing-buyer retry trace remains visible in user-authorized report', () {
    final text = formatScreenshotOcrDiagnostic(
      screenshotNumber: 1,
      ocr: const ScreenshotOcrResult(
        width: 865, height: 1920, lines: [],
        nativeTrace: [
          '小字单主候选标题=3；需要局部重识别=1',
          '单主区域y=1085；放大：[测试买家]；有效=[测试买家]',
        ],
      ),
      route: '排单列表',
      platform: '米画师',
      parsedRows: const [],
    );
    expect(text, contains('本机二次识别过程'));
    expect(text, contains('需要局部重识别=1'));
    expect(text, contains('放大：[测试买家]'));
  });
}
