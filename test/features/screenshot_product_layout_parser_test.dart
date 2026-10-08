import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_product_layout_parser.dart';

void main() {
  ScreenshotTextLine line(
    String content, int y, {double x = 70, double width = 320},
  ) => ScreenshotTextLine(
    text: content,
    top: y.toDouble(),
    left: x,
    right: x + width,
    bottom: y + 24.0,
  );

  test('product screenshots extract storefronts without any deadline', () {
    final items = const ScreenshotProductLayoutParser().parse(
      imageHeight: 1200,
      lines: [
        line('5:17', 22),
        line('我卖出的', 105),
        line('【常驻】 黑白摸鱼头3.0', 220),
        line('¥94', 275),
        line('小企鹅头像', 520),
        line('¥30', 578),
      ],
    );
    expect(items.length, 2);
    expect(items.first.title, '【常驻】 黑白摸鱼头3.0');
    expect(items.first.price, 94);
    expect(items.last.title, '小企鹅头像');
    expect(items.last.price, 30);
  });

  test('product OCR does not treat dates or sale status as a title', () {
    final items = const ScreenshotProductLayoutParser().parse(
      imageHeight: 1200,
      lines: [
        line('2026-10-08 16:48', 80),
        line('已完成', 120),
        line('【常驻】 角色立绘', 240),
        line('¥50', 310),
      ],
    );
    expect(items.length, 1);
    expect(items.single.title, '【常驻】 角色立绘');
  });

  test('ML Kit y/Y currency confusions keep all product prices', () {
    final items = const ScreenshotProductLayoutParser().parse(
      imageHeight: 1300,
      lines: [
        line('我卖出的', 90),
        line('【常驻】 黑白摸鱼头3.0', 220),
        line('y94', 275), // Real Chinese ML Kit: ¥94 -> y94.
        line('小企鹅头像', 525),
        line('Y30', 580), // Small right-aligned ￥30 -> Y30.
        line('白裙服设批发', 825),
        line('¥50', 885),
      ],
    );
    expect(items, hasLength(3));
    expect(items.map((e) => e.title).toList(),
        ['【常驻】 黑白摸鱼头3.0', '小企鹅头像', '白裙服设批发']);
    expect(items.map((e) => e.price).toList(), [94, 30, 50]);
  });

  test('unrelated y-prefixed artwork text is never reclassified as a price', () {
    final items = const ScreenshotProductLayoutParser().parse(
      imageHeight: 800,
      lines: [
        line('【常驻】 yy94原创头像', 205),
        line('y94元仅限一次', 250), // No exact money token.
        line('【常驻】 全新立绘', 450),
        line('¥60', 525),
      ],
    );
    expect(items, hasLength(2));
    expect(items.first.title, '【常驻】 yy94原创头像');
    expect(items.first.price, isNull);
    expect(items.last.price, 60);
  });

  test('split currency and digits are one price, without inventing bare fees', () {
    final items = const ScreenshotProductLayoutParser().parse(
      imageHeight: 1100,
      lines: [
        line('【常驻】头像', 200, x: 193, width: 200),
        line('¥', 270, x: 586, width: 21),
        line('94', 270, x: 610, width: 28),
        line('【常驻】另一个盒子', 580, x: 190, width: 210),
        line('88', 645, x: 644, width: 26),
      ],
    );
    expect(items, hasLength(2));
    expect(items.map((e) => e.title).toList(),
        ['【常驻】头像', '【常驻】另一个盒子']);
    expect(items.map((e) => e.price).toList(), [94, null]);
  });
}
