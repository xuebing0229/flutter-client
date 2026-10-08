import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';

void main() {
  ScreenshotTextLine box(String text, double top, {double x = 185}) =>
      ScreenshotTextLine(
        text: text, left: x, top: top,
        right: x + 190, bottom: top + 24,
      );

  test('one detail page with an attachment date is exactly one commission', () {
    final lines = [
      box('订单', 87, x: 321),
      box('【这是1令盒子', 180, x: 186), // Bad OCR; still actual title row.
      box('截稿时间 2026-07-13 21:05', 265, x: 175),
      box('买家甲', 368, x: 109),
      box('约稿完成！稿酬 ￥88', 477, x: 31),
      box('稿件夹', 586, x: 33),
      box('进程动态', 586, x: 185),
      box('参考信息', 586, x: 328),
      box('203.8 KB/5.0 GB', 679, x: 31),
      box('插画34.png', 723, x: 188),
      box('2026-07-10 11:55', 767, x: 190),
      box('企划方已下载', 825, x: 237),
      box('联系企划方', 1454, x: 246),
      box('上传稿件', 1454, x: 488),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    final found = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    );
    expect(found, hasLength(1));
    expect(found.single.title, '【这是1令盒子');
    expect(found.single.clientName, '买家甲');
    expect(found.single.price, 88);
    expect(found.single.progressPercent, 100);
    expect(found.single.importReadyDeadline, DateTime(2026, 7, 13, 21, 5));
  });

  test('missing tab text and lost deadline label still parse one order', () {
    final lines = [
      box('订单', 96, x: 325),
      box('【这是】虚构盒子', 187, x: 185),
      box('2026-07-13 21:05', 266, x: 273),
      box('买家乙', 362, x: 100),
      box('约稿完成! 稿酬', 472, x: 32),
      box('¥', 472, x: 250),
      box('88', 472, x: 279),
      box('文件 1', 674, x: 30),
      box('插画34.png', 737, x: 200),
      box('2026-07-10 11:55', 775, x: 198),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    final found = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    );
    expect(found, hasLength(1));
    expect(found.single.title, '【这是】虚构盒子');
    expect(found.single.clientName, '买家乙');
    expect(found.single.price, 88);
    expect(found.single.detectedDate, DateTime(2026, 7, 13, 21, 5));
    expect(found.single.progressPercent, 100);
  });

  test('missing actual deadline must not borrow the attachment upload date', () {
    final lines = [
      box('订单', 92, x: 330),
      box('【这是】虚构盒子', 187, x: 180),
      box('买家丙', 370, x: 107),
      box('约稿完成！稿酬 ￥88', 479, x: 30),
      box('稿件夹', 589, x: 38),
      box('插画34.png', 739, x: 188),
      box('2026-07-10 11:55', 775, x: 188),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    final found = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    );
    expect(found, hasLength(1));
    expect(found.single.detectedDate, isNull);
    expect(found.single.clientName, isNot('订单'));
  });

  test('normal vertically stacked commission list is not a detail page', () {
    final lines = [
      box('进行中', 115, x: 167),
      box('购买时间', 182, x: 500),
      box('买家甲', 313, x: 131),
      box('【常驻】作品A', 408, x: 290),
      box('￥94', 449, x: 277),
      box('2026-10-31', 518, x: 272),
      box('买家乙', 770, x: 132),
      box('【常驻】作品A', 866, x: 277),
      box('￥94', 910, x: 274),
      box('2026-10-31', 966, x: 275),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isFalse);
    expect(const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), hasLength(2));
  });
}
