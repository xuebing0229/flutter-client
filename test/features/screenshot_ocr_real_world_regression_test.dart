import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_huajia_detail_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_rules.dart';
import 'package:flutter_app/features/imports/data/screenshot_import_history.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  ScreenshotTextLine at(String text, double y, {double x = 250}) =>
      ScreenshotTextLine(
        text: text, left: x, top: y, right: x + 80, bottom: y + 20,
      );

  test('MiHuashi ML Kit split currency: title/buyer/price never swap', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1500,
      lines: [
        at('截稿时间', 185, x: 160),
        at('购买时间', 185, x: 500),
        at('买家甲', 310, x: 130),
        at('【常驻】 虚构稿3.0', 410, x: 270),
        at('¥', 454, x: 272), at('94', 454, x: 292),
        at('2026-10-31', 526, x: 280),
        at('上色 60%', 561, x: 276),
        at('买家乙', 765, x: 130),
        at('【常驻】 虚构稿3.0', 862, x: 270),
        at('94', 900, x: 282),
        at('2026-10-31', 970, x: 280),
        at('上色 60%', 1010, x: 276),
      ],
    );
    expect(rows.length, 2);
    expect(rows.map((e) => e.title).toList(),
        ['【常驻】 虚构稿3.0', '【常驻】 虚构稿3.0']);
    expect(rows.map((e) => e.clientName).toList(), ['买家甲', '买家乙']);
    expect(rows.map((e) => e.price).toList(), [94, 94]);
  });

  test('Huajia ML Kit split right aligned currency still yields prices', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        at('我卖出的', 111, x: 300),
        at('买家甲', 252, x: 60),
        at('虚构草稿盒', 337, x: 198),
        at('当前交付节点：终稿（100%）', 369, x: 198),
        at('截稿时间：2026-10-08 16:48', 393, x: 198),
        at('￥', 443, x: 616), at('30', 443, x: 645),
        at('买家乙', 598, x: 60),
        at('虚构摸鱼盒', 710, x: 198),
        at('当前交付节点：终稿（100%）', 735, x: 198),
        at('截稿时间：2026-10-09 01:29', 764, x: 198),
        at('88', 818, x: 651),
        at('买家丙', 965, x: 60),
        at('虚构草稿盒', 1072, x: 198),
        at('当前交付节点：终稿（100%）', 1103, x: 198),
        at('截稿时间：2026-10-17 18:01', 1128, x: 198),
        at('800', 1178, x: 625),
      ],
    );
    expect(rows.length, 3);
    expect(rows.map((e) => e.price).toList(), [30, 88, 800]);
    expect(rows.first.importReadyDeadline, DateTime(2026, 10, 8, 16, 48));
  });

  test('MiHuashi detail detects platform and never splits uploaded file', () {
    final lines = [
      at('订单', 103, x: 310),
      at('【这是】虚构盒子', 189, x: 180),
      at('截稿时间 2026-07-13 21:05', 270, x: 170),
      at('买家丁', 356, x: 95),
      at('约稿完成！稿酬', 465, x: 30),
      at('￥', 465, x: 268), at('88', 465, x: 305),
      at('稿件夹', 599, x: 28),
      at('进程动态', 599, x: 164),
      at('参考信息', 599, x: 320),
      at('203.8KB / 5.0 GB', 687, x: 30),
      at('插画34.png', 741, x: 170),
      at('2026-07-10 11:55', 778, x: 170),
      at('联系企划方', 1442, x: 256),
      at('上传稿件', 1442, x: 491),
    ];
    expect(preselectImportPlatform(lines.map((e) => e.text)).platform,
        CommissionPlatform.mihuashi);
    final rows = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 692, imageHeight: 1536,
    );
    expect(rows.length, 1);
    expect(rows.single.title, '【这是】虚构盒子');
    expect(rows.single.clientName, '买家丁');
    expect(rows.single.price, 88);
    expect(rows.single.importReadyDeadline, DateTime(2026, 7, 13, 21, 5));
  });

  test('MiHuashi detail: full timestamp only, no duplicate title card', () {
    final lines = [
      at('订单', 102, x: 320),
      at('【常驻】虚构头像稿', 190, x: 180),
      at('距截稿时间 2026-10-31 23:59 还有23天', 267, x: 165),
      at('买家戊', 356, x: 94),
      at('创作节点', 489, x: 50),
      at('60%', 521, x: 60),
      at('已全额支付 ￥94', 489, x: 452),
      at('稿件夹', 607, x: 40),
      at('进程动态', 607, x: 200),
      at('参考信息', 607, x: 360),
      at('联系企划方', 1445, x: 255),
    ];
    expect(preselectImportPlatform(lines.map((e) => e.text).toList()).platform,
        CommissionPlatform.mihuashi);
    final rows = const ScreenshotLayoutParser().parse(
      lines: lines, imageWidth: 692, imageHeight: 1536,
    );
    expect(rows.length, 1);
    expect(rows.single.price, 94);
    expect(rows.single.importReadyDeadline, DateTime(2026, 10, 31, 23, 59));
  });

  test('real ML Kit output: MiHuashi Y94 fee and split-month date', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        at('测试买家甲', 296, x: 115),
        at('【常驻】黑白摸鱼头3.0', 397, x: 285),
        at('y94', 443, x: 278),
        at('2026-10-31', 513, x: 309),
        at('60%', 554, x: 341),
        at('测试买家', 753, x: 116),
        at('【常驻】黑白摸鱼头3.0', 851, x: 284),
        at('Y94', 898, x: 278),
        at('2026-1 0-31', 968, x: 309),
        at('60%', 1009, x: 341),
        at('测试买家丙', 1200, x: 115),
        at('【常驻】黑白模鱼头3.0', 1304, x: 296),
        at('y94', 1348, x: 278),
        at('2026-10-31', 1418, x: 309),
      ],
    );
    expect(rows, hasLength(3));
    expect(rows.map((row) => row.price), [94, 94, 94]);
    expect(rows.every((row) => row.detectedDate?.month == 10), isTrue);
    expect(rows.map((row) => row.clientName),
        ['测试买家甲', '测试买家', '测试买家丙']);
  });

  test('real ML Kit output: Huajia detail has y40, 己完成 and 载稿时间', () {
    final screenshot = [
      at('订单己完成', 107, x: 247),
      at('虚构用户', 254, x: 104),
      at('真愛永恒M', 258, x: 319),
      at('【24h】速食短打+赠捡手', 339, x: 220),
      at('y40', 390, x: 198),
      at('载稿时间:2025-04-27 16:37', 428, x: 188),
      at('稿件6 订单动态改价历史参考信息', 569, x: 26),
      at('2025-04-27', 1010, x: 41),
    ];
    final details = const ScreenshotHuajiaDetailParser().parse(
      lines: screenshot, imageWidth: 692, imageHeight: 1536,
    );
    expect(details, hasLength(1));
    expect(details.single.title, '【24h】速食短打+赠捡手');
    expect(details.single.clientName, '虚构用户');
    expect(details.single.price, 40);
    expect(details.single.progressPercent, 100);
    expect(details.single.importReadyDeadline,
        DateTime(2025, 4, 27, 16, 37));
  });

  test('same file different card index is independent; repeated card matches', () {
    const sha = 'fake-sha256';
    final first = screenshotCardFingerprint(
      imageSha256: sha, cardIndex: 0, products: false,
    );
    final second = screenshotCardFingerprint(
      imageSha256: sha, cardIndex: 1, products: false,
    );
    final again = screenshotCardFingerprint(
      imageSha256: sha, cardIndex: 0, products: false,
    );
    expect(first, again);
    expect(second, isNot(first));
    expect(screenshotCardFingerprint(
      imageSha256: sha, cardIndex: 0, products: true,
    ), isNot(first));
  });
  test('A nearby progress icon cannot make date-only deadline midnight', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1200,
      lines: [
        at('买家甲', 225, x: 115),
        at('【常驻】 虚构稿', 344, x: 270),
        at('94', 388, x: 280),
        at('2026-10-31', 480, x: 277),
        at('00:00', 518, x: 296), // Misread node/progress icon below date.
      ],
    );
    expect(rows, hasLength(1));
    expect(rows.single.needsDeadlineTimeConfirmation, isTrue);
    expect(rows.single.importReadyDeadline, isNull);
  });

  test('Huajia navigation arrow is not included in buyer nickname', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1040,
      lines: [
        at('我卖出的', 110, x: 260),
        at('客户甲 >', 252, x: 55),
        at('虚构草稿盒', 334, x: 190),
        at('截稿时间：2026-10-08 16:48', 397, x: 190),
        at('30', 450, x: 645),
      ],
    );
    expect(rows, hasLength(1));
    expect(rows.single.clientName, '客户甲');
    expect(rows.single.price, 30);
  });

  test('Huajia right-corner OCR amount beyond the old 115px cutoff', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        at('我卖出的', 110, x: 310),
        at('客户甲', 250, x: 60),
        at('虚构草稿盒', 325, x: 195),
        at('当前交付节点：终稿（100%）', 360, x: 197),
        at('截稿时间：2026-10-08 16:48', 386, x: 194),
        at('￥30', 485, x: 628),
        at('客户乙', 598, x: 60),
        at('虚构摸鱼盒', 696, x: 195),
        at('当前交付节点：终稿（100%）', 735, x: 197),
        at('截稿时间：2026-10-09 01:29', 768, x: 194),
        at('￥88', 887, x: 633),
        at('客户丙', 976, x: 60),
        at('虚构草稿盒', 1065, x: 195),
        at('当前交付节点：终稿（100%）', 1098, x: 197),
        at('截稿时间：2026-10-17 18:01', 1130, x: 194),
        at('￥', 1250, x: 622),
        at('30', 1250, x: 649),
        at('客户丁', 1320, x: 60),
        at('虚构盒子', 1390, x: 195),
        at('截稿时间：2026-10-21 10:25', 1470, x: 194),
      ],
    );
    expect(rows.length, 4);
    expect(rows.map((row) => row.price).toList(), [30, 88, 30, null]);
  });

  test('Right crop OCR fragment of deadline clock must not become a fee', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1070,
      lines: [
        at('我卖出的', 108, x: 300),
        at('客户甲', 265, x: 60),
        at('虚构草稿盒', 350, x: 205),
        at('截稿时间：2026-10-08 16:48', 430, x: 206),
        at('48', 432, x: 590),
        // Price is not visible in the screenshot; never invent 48 yuan.
      ],
    );
    expect(rows.length, 1);
    expect(rows.single.price, isNull);
  });

  test('Right column bare amount is accepted below deadline when ¥ missed', () {
    final rows = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1120,
      lines: [
        at('我卖出的', 106, x: 310),
        at('客户甲', 263, x: 64),
        at('虚构草稿盒', 345, x: 204),
        at('截稿时间：2026-10-08 16:48', 428, x: 204),
        at('30', 579, x: 643),
      ],
    );
    expect(rows, hasLength(1));
    expect(rows.single.price, 30);
  });

}
