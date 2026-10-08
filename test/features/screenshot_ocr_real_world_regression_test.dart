import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
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

}
