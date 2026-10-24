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

  test('ML Kit drops centered order heading and attachment filename', () {
    final lines = [
      box('【这是】虚构盒子', 183, x: 183),
      box('截稿时间 2026-07-13 21:05', 266, x: 172),
      box('买家甲', 367, x: 109),
      box('约稿完成！稿酬 ￥88', 478, x: 32),
      box('稿件夹', 585, x: 33),
      box('进程动态', 585, x: 187),
      box('参考信息', 585, x: 328),
      // Upload filename may vanish entirely in native OCR, but its date
      // still exists and must never be imported as another commission.
      box('2026-07-10 11:55', 770, x: 186),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    final rows = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    );
    expect(rows, hasLength(1));
    expect(rows.single.clientName, '买家甲');
    expect(rows.single.price, 88);
    expect(rows.single.detectedDate, DateTime(2026, 7, 13, 21, 5));
  });

  test('missing order heading and tabs, but uploaded PNG remains', () {
    final lines = [
      box('【这是】虚构盒子', 180, x: 185),
      box('截稿时间 2026-07-13 21:05', 265, x: 175),
      box('买家乙', 369, x: 108),
      box('约稿完成！稿酬 ￥88', 474, x: 32),
      box('插画34.png', 741, x: 188),
      box('2026-07-10 11:55', 776, x: 184),
    ];
    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    final rows = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 698, imageHeight: 1536,
    );
    expect(rows, hasLength(1));
    expect(rows.single.title, '【这是】虚构盒子');
    expect(rows.single.detectedDate, DateTime(2026, 7, 13, 21, 5));
  });

  test('newer MiHuashi workbench detail parses title buyer total and progress', () {
    final lines = [
      box('工作板', 92, x: 302),
      box('一则生贺～', 207, x: 28),
      box('距截稿日 2026-11-15 还有 25 天', 274, x: 28),
      box('一个弹珠', 349, x: 111),
      box('验收节点', 470, x: 28),
      box('草稿 20%', 514, x: 28),
      box('已付 ￥148', 478, x: 438),
      box('总额 ￥740', 522, x: 437),
      box('稿件夹', 626, x: 28),
      box('进程动态', 626, x: 165),
      box('参考信息', 626, x: 326),
      box('0 B/5.0 GB', 716, x: 28),
      box('共 0 个文件', 716, x: 548),
      box('联系企划方', 1430, x: 280),
      box('上传稿件', 1430, x: 505),
    ];

    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines,
      imageWidth: 690,
      imageHeight: 1536,
    ), isTrue);

    final found = const ScreenshotLayoutParser().parse(
      lines: lines,
      imageWidth: 690,
      imageHeight: 1536,
    );

    expect(found, hasLength(1));
    expect(found.single.title, '一则生贺～');
    expect(found.single.clientName, '一个弹珠');
    expect(found.single.price, 740);
    expect(found.single.progressPercent, 20);
    expect(found.single.detectedDate, DateTime(2026, 11, 15));
    expect(found.single.deadlineHasTime, isFalse);
  });

  test('workbench still prefers lower total when faint 总额 label is lost', () {
    final lines = [
      box('工作板', 92, x: 302),
      box('一则生贺～', 207, x: 28),
      box('距截稿日 2026-11-15 还有 25 天', 274, x: 28),
      box('一个弹珠', 349, x: 111),
      box('验收节点', 470, x: 28),
      box('草稿 20%', 514, x: 28),
      box('已付 ￥148', 478, x: 438),
      box('￥740', 522, x: 487),
      box('稿件夹', 626, x: 28),
      box('进程动态', 626, x: 165),
      box('参考信息', 626, x: 326),
    ];

    final found = const ScreenshotLayoutParser().parse(
      lines: lines,
      imageWidth: 690,
      imageHeight: 1536,
    );

    expect(found, hasLength(1));
    expect(found.single.price, 740);
  });

  test('actual order-style MiHuashi detail parses full payment accurately', () {
    final lines = [
      box('订单', 111, x: 304),
      box('【常驻】黑白摸鱼头3.0', 219, x: 208),
      box('距截稿时间 2026-11-30 23:59 还有 40 天', 312, x: 191),
      box('y照', 425, x: 116),
      box('创作节点', 552, x: 32),
      box('60%', 603, x: 83),
      box('已全额支付', 557, x: 437),
      box('￥94', 604, x: 437),
      box('稿件夹', 730, x: 33),
      box('进程动态', 730, x: 188),
      box('参考信息', 730, x: 370),
      box('0 B/5.0 GB', 820, x: 34),
      box('共 0 个文件', 820, x: 555),
    ];

    final found = const ScreenshotLayoutParser().parse(
      lines: lines,
      imageWidth: 698,
      imageHeight: 1536,
    );

    expect(found, hasLength(1));
    expect(found.single.title, '【常驻】黑白摸鱼头3.0');
    expect(found.single.clientName, 'y照');
    expect(found.single.price, 94);
    expect(found.single.progressPercent, 60);
    expect(
      found.single.importReadyDeadline,
      DateTime(2026, 11, 30, 23, 59),
    );
  });

  test('actual workbench-style MiHuashi detail parses full payment accurately', () {
    final lines = [
      box('工作板', 111, x: 304),
      box('邀请您价目表中的人head气球', 231, x: 32),
      box('距截稿日 2026-12-31 还有 71 天', 307, x: 32),
      box('W落秋', 391, x: 116),
      box('验收节点', 505, x: 32),
      box('80%', 561, x: 81),
      box('已全额支付', 512, x: 437),
      box('￥105', 561, x: 437),
      box('稿件夹', 690, x: 32),
      box('进程动态', 690, x: 188),
      box('参考信息', 690, x: 370),
      box('0 B/5.0 GB', 789, x: 32),
      box('共 0 个文件', 789, x: 555),
    ];

    final found = const ScreenshotLayoutParser().parse(
      lines: lines,
      imageWidth: 698,
      imageHeight: 1536,
    );

    expect(found, hasLength(1));
    expect(found.single.title, '邀请您价目表中的人head气球');
    expect(found.single.clientName, 'W落秋');
    expect(found.single.price, 105);
    expect(found.single.progressPercent, 80);
    expect(found.single.detectedDate, DateTime(2026, 12, 31));
    expect(found.single.deadlineHasTime, isFalse);
  });

  test('detail page without header or deadline never turns UI labels into orders', () {
    final lines = [
      box('【常驻】黑白摸鱼头3.0', 190, x: 205),
      box('y照', 340, x: 116),
      box('验收节点', 490, x: 32),
      box('已全额支付', 500, x: 437),
      box('60%', 545, x: 83),
      box('￥94', 548, x: 437),
      // Current screenshots can lose the small centered header, deadline and
      // middle tab labels while keeping the bottom action.
      box('上传稿件', 1430, x: 505),
    ];

    expect(isMiHuashiOrderDetailScreenshot(
      lines: lines,
      imageWidth: 698,
      imageHeight: 1536,
    ), isTrue);

    final found = const ScreenshotLayoutParser().parse(
      lines: lines,
      imageWidth: 698,
      imageHeight: 1536,
    );

    expect(found, hasLength(1));
    expect(found.single.title, '【常驻】黑白摸鱼头3.0');
    expect(found.single.clientName, 'y照');
    expect(found.single.price, 94);
    expect(found.single.progressPercent, 60);
    expect(
      found.map((row) => row.title),
      isNot(contains(anyOf('已全额支付', '上传稿件', '验收节点'))),
    );
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
