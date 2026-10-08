import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_product_layout_parser.dart';

/// Geometry and visible text transcribed from six real commission screenshots.
/// Screenshots themselves stay private; this exercises layout parsing, not
/// native Android/Windows OCR recognition accuracy.
void main() {
  ScreenshotTextLine row(String text, double y, {double x = 70}) =>
      ScreenshotTextLine(
        text: text, left: x, top: y, right: x + 210, bottom: y + 22,
      );

  test('real MiHuashi list: three identical titles remain three orders', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        row('进行中', 105),
        row('截稿时间', 185),
        row('购买时间', 185, x: 495),
        row('买家甲甲', 300),
        row('【常驻】 虚构头像稿3.0', 403, x: 275),
        row('￥94', 446, x: 280),
        row('2026-10-31', 514, x: 285),
        row('60%', 557, x: 340),
        row('买家乙乙', 756),
        row('【常驻】 虚构头像稿3.0', 855, x: 275),
        row('￥94', 895, x: 280),
        row('2026-10-31', 968, x: 285),
        row('60%', 1012, x: 340),
        row('买家丙丙', 1194),
        row('【常驻】 虚构头像稿3.0', 1321, x: 275),
        row('￥94', 1355, x: 280),
        row('2026-10-31', 1420, x: 285),
        row('60%', 1463, x: 340),
      ],
    );
    expect(entries.length, 3);
    expect(entries.map((entry) => entry.clientName).toList(),
        ['买家甲甲', '买家乙乙', '买家丙丙']);
    expect(entries.every((entry) => entry.price == 94), isTrue);
    expect(entries.every((entry) => entry.importReadyDeadline == null), isTrue);
  });

  test('real MiHuashi planned commission list: no fabricated prices', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        row('买家丁', 367),
        row('定向企划', 476, x: 55),
        row('虚构企划头像需求', 476, x: 162),
        row('2026-12-31', 547),
        row('80%', 548, x: 310),
        row('买家戊Sun', 755),
        row('定向企划', 854, x: 55),
        row('虚构头像稿', 854, x: 160),
        row('2026-11-30', 917),
        row('草稿 20%', 918, x: 310),
        row('买家己momo', 1125),
        row('定向企划', 1224, x: 55),
        row('虚构企划头像需求', 1224, x: 162),
        row('2026-11-30', 1289),
        row('80%', 1291, x: 310),
      ],
    );
    expect(entries.length, 3);
    expect(entries.map((entry) => entry.price).toList(),
        [null, null, null]);
    expect(entries.map((entry) => entry.progressPercent).toList(),
        [80, 20, 80]);
  });

  test('real Huajia sold list: distinct buyers, exact times and prices', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        row('我卖出的', 102),
        row('客户一cy', 262),
        row('虚构草稿盒', 327, x: 196),
        row('当前交付节点：终稿（100%）', 366, x: 195),
        row('截稿时间：2026-10-08 16:48', 389, x: 195),
        row('￥30', 442, x: 610),
        row('客户二', 602),
        row('虚构only的摸鱼盒', 694, x: 195),
        row('当前交付节点：终稿（100%）', 739, x: 195),
        row('截稿时间：2026-10-09 01:29', 763, x: 195),
        row('￥88', 816, x: 610),
        row('客户三', 969),
        row('虚构草稿盒', 1064, x: 195),
        row('当前交付节点：终稿（100%）', 1100, x: 195),
        row('截稿时间：2026-10-17 18:01', 1129, x: 195),
        row('￥30', 1179, x: 610),
      ],
    );
    expect(entries.length, 3);
    expect(entries.map((entry) => entry.clientName).toList(),
        ['客户一cy', '客户二', '客户三']);
    expect(entries.map((entry) => entry.price).toList(), [30, 88, 30]);
    expect(entries.first.importReadyDeadline,
        DateTime(2026, 10, 8, 16, 48));
    expect(entries.last.importReadyDeadline,
        DateTime(2026, 10, 17, 18, 1));
  });

  test('real MiHuashi order details retain buyer, price and exact deadline', () {
    final orders = const ScreenshotLayoutParser();
    final first = orders.parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        row('订单', 96, x: 320),
        row('【常驻】 虚构头像稿3.0', 183, x: 176),
        row('距截稿时间 2026-10-31 23:59 还有23天', 273, x: 165),
        row('买家甲甲', 355, x: 105),
        row('创作节点', 480),
        row('60%', 513),
        row('已全额支付 ￥94', 480, x: 454),
      ],
    );
    expect(first.length, 1);
    expect(first.single.title, '【常驻】 虚构头像稿3.0');
    expect(first.single.clientName, '买家甲甲');
    expect(first.single.price, 94);
    expect(first.single.progressPercent, 60);
    expect(first.single.importReadyDeadline,
        DateTime(2026, 10, 31, 23, 59));

    final second = orders.parse(
      imageWidth: 692, imageHeight: 1536,
      lines: [
        row('订单', 96, x: 320),
        row('【这是】 虚构盒子', 187, x: 185),
        row('截稿时间 2026-07-13 21:05', 273, x: 169),
        row('买家庚', 355, x: 105),
        row('约稿完成！稿酬 ￥88', 472),
      ],
    );
    expect(second.length, 1);
    expect(second.single.title, '【这是】 虚构盒子');
    expect(second.single.clientName, '买家庚');
    expect(second.single.price, 88);
    expect(second.single.importReadyDeadline,
        DateTime(2026, 7, 13, 21, 5));
  });

  test('real completed storefront-like cards exclude deadline metadata', () {
    final products = const ScreenshotProductLayoutParser().parse(
      imageHeight: 1536,
      lines: [
        row('我卖出的', 106),
        row('买家辛', 327),
        row('虚构白裙【服设批发】', 404, x: 210),
        row('截稿时间：拍下自动提交源文件', 453, x: 220),
        row('￥10', 520, x: 636),
        row('买家壬', 723),
        row('【批发合集】20r虚构服设批发', 820, x: 230),
        row('截稿时间：2025-05-31 14:34', 861, x: 230),
        row('￥20', 990, x: 636),
        row('买家癸', 1129),
        row('批发服设·虚构2025', 1200, x: 215),
        row('截稿时间：2025-03-24 21:12', 1240, x: 215),
        row('￥10', 1350, x: 636),
      ],
    );
    expect(products.length, 3);
    expect(products.map((product) => product.title).toList(),
        ['虚构白裙【服设批发】', '【批发合集】20r虚构服设批发', '批发服设·虚构2025']);
    expect(products.map((product) => product.price).toList(), [10, 20, 10]);
  });
}
