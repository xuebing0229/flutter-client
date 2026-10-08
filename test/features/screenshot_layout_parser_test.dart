import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';

void main() {
  ScreenshotTextLine at(String text, double y, {double x = 80}) =>
      ScreenshotTextLine(text: text, left: x, top: y, right: x + 220,
          bottom: y + 22);

  test('米画师 screenshot can separate two cards without crossing fields', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 690,
      imageHeight: 1400,
      lines: [
        at('3:17', 25),
        at('吃小孩咯', 300, x: 120),
        at('【常驻】 黑白摸鱼头3.0', 410, x: 275),
        at('¥94', 460, x: 280),
        at('2026-10-31', 535, x: 290),
        at('60%', 568, x: 280),
        at('晓vv', 768, x: 120),
        at('【常驻】 黑白摸鱼头3.0', 856, x: 275),
        at('¥94', 906, x: 280),
        at('2026-10-31', 1002, x: 290),
        at('60%', 1034, x: 280),
      ],
    );
    expect(entries.length, 2);
    expect(entries.first.title, '【常驻】 黑白摸鱼头3.0');
    expect(entries.first.clientName, '吃小孩咯');
    expect(entries.first.price, 94);
    expect(entries.first.progressPercent, 60);
    expect(entries.last.clientName, '晓vv');
    expect(entries.last.price, 94);
  });

  test('画加: progress and price are not mixed with the next card', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 690,
      imageHeight: 1580,
      lines: [
        at('我卖出的', 145),
        at('55cy', 270, x: 55),
        at('黑白草稿盒', 340, x: 200),
        at('当前交付节点：终稿（100%）', 371, x: 200),
        at('截稿时间：2026-10-08 16:48', 395, x: 200),
        at('¥30', 460, x: 560),
        at('桃不掉方', 615, x: 55),
        at('妹宝only的摸鱼草盲盒', 720, x: 200),
        at('当前交付节点：终稿（100%）', 755, x: 200),
        at('截稿时间：2026-10-09 01:29', 780, x: 200),
        at('¥88', 830, x: 560),
      ],
    );
    expect(entries.length, 2);
    expect(entries.first.title, '黑白草稿盒');
    expect(entries.first.clientName, '55cy');
    expect(entries.first.price, 30);
    expect(entries.last.title, '妹宝only的摸鱼草盲盒');
    expect(entries.last.price, 88);
    expect(entries.last.progressPercent, 100);
  });

  test('no guessed price when a platform shows no money', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 690,
      imageHeight: 1200,
      lines: [
        at('W落秋', 365),
        at('定向企划 邀请您企目表中的Xhead气球', 480),
        at('2026-12-31', 552),
        at('80%', 574),
      ],
    );
    expect(entries.single.price, isNull);
    expect(entries.single.title, '邀请您企目表中的Xhead气球');
  });
}
