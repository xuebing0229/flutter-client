import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_product_layout_parser.dart';

void main() {
  ScreenshotTextLine line(String content, int y) => ScreenshotTextLine(
    text: content,
    top: y.toDouble(),
    left: 70,
    right: 390,
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
}
