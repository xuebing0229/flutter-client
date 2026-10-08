import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_huajia_detail_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_rules.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  ScreenshotTextLine box(String text, double y, {double x = 210}) =>
      ScreenshotTextLine(
        text: text, left: x, top: y, right: x + 138, bottom: y + 24,
      );

  test('real Huajia completed detail: order header, seller, fee and deadline', () {
    final screenshot = [
      box('订单已完成', 120, x: 260),
      box('秋叶七海', 246, x: 94),
      box('已实名', 246, x: 220),
      box('❤真爱永恒 Lv1', 246, x: 315),
      box('【24h】速食1k5短打+赠捡手...', 346, x: 204),
      box('¥40', 387, x: 197),
      box('截稿时间：2025-04-27 16:37', 428, x: 194),
      box('稿件 6', 574, x: 30),
      box('订单动态', 574, x: 150),
      box('改价历史', 574, x: 304),
      box('参考信息', 574, x: 473),
      box('1.6MB/1.0GB', 637, x: 540),
      box('2025-04-27', 1008, x: 36),
      box('34.6KB', 1008, x: 35),
      box('92.4KB', 1008, x: 350),
    ];
    expect(isHuajiaOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    expect(isMiHuashiOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isFalse);
    expect(preselectImportPlatform(
      screenshot.map((line) => line.text)).platform,
        CommissionPlatform.huajia);
    final orders = const ScreenshotHuajiaDetailParser().parse(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    );
    expect(orders, hasLength(1));
    expect(orders.single.title, '【24h】速食1k5短打+赠捡手...');
    expect(orders.single.clientName, '秋叶七海');
    expect(orders.single.price, 40);
    expect(orders.single.importReadyDeadline,
        DateTime(2025, 4, 27, 16, 37));
    expect(orders.single.progressPercent, 100);
  });

  test('second attachment date cannot create another order', () {
    final screenshot = [
      box('订单已完成', 120, x: 260),
      box('客户甲', 246, x: 93),
      box('真爱永恒 Lv1', 248, x: 310),
      box('【24H】作品名', 346, x: 202),
      box('￥', 390, x: 197),
      box('40', 390, x: 220),
      box('截稿时间：2025-04-27 16:37', 428, x: 195),
      box('稿件 6', 573, x: 30),
      box('订单动态', 573, x: 152),
      box('改价历史', 573, x: 302),
      box('2025-04-22 08:00', 990, x: 40),
      box('2025-04-23 21:05', 1260, x: 340),
    ];
    final orders = const ScreenshotHuajiaDetailParser().parse(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    );
    expect(orders, hasLength(1));
    expect(orders.single.title, '【24H】作品名');
    expect(orders.single.price, 40);
    expect(orders.single.importReadyDeadline,
        DateTime(2025, 4, 27, 16, 37));
  });

  test('missing visible deadline stays unset, never borrows file date', () {
    final screenshot = [
      box('订单已完成', 120, x: 260),
      box('客户乙', 248, x: 90),
      box('真爱永恒 Lv1', 248, x: 320),
      box('【24h】示例稿', 348, x: 205),
      box('¥40', 391, x: 195),
      box('稿件 6', 571, x: 30),
      box('订单动态', 571, x: 150),
      box('改价历史', 571, x: 302),
      box('2025-04-27 16:37', 960, x: 40),
    ];
    final orders = const ScreenshotHuajiaDetailParser().parse(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    );
    expect(orders, hasLength(1));
    expect(orders.single.detectedDate, isNull);
    expect(orders.single.clientName, '客户乙');
    expect(orders.single.price, 40);
  });

  test('generic details cannot be auto-labelled MiHuashi or Huajia', () {
    final screenshot = [
      box('订单', 120, x: 310),
      box('客户丙', 240, x: 90),
      box('参考信息', 580, x: 305),
      box('稿件', 580, x: 40),
      box('2025-04-27', 980, x: 35),
    ];
    expect(preselectImportPlatform(
      screenshot.map((line) => line.text)).platform, isNull);
    expect(isHuajiaOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isFalse);
    expect(isMiHuashiOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isFalse);
    expect(const ScreenshotHuajiaDetailParser().parse(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isEmpty);
  });

  test('real MiHuashi detail still routes exclusively to its own parser', () {
    final screenshot = [
      box('订单', 96, x: 320),
      box('【这是】虚构盒子', 180, x: 185),
      box('截稿时间 2026-07-13 21:05', 265, x: 175),
      box('客户丁', 367, x: 94),
      box('约稿完成！稿酬 ￥88', 469, x: 30),
      box('稿件夹', 584, x: 30),
      box('进程动态', 584, x: 165),
      box('参考信息', 584, x: 318),
      box('2026-07-10 11:55', 780, x: 185),
    ];
    expect(isHuajiaOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isFalse);
    expect(isMiHuashiOrderDetailScreenshot(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), isTrue);
    expect(const ScreenshotLayoutParser().parse(
      lines: screenshot, imageWidth: 698, imageHeight: 1536,
    ), hasLength(1));
  });
}
