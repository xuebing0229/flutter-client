import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

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

    // 米画师截图只有日期，绝不能默默写成 2026-10-31 00:00。
    expect(entries.first.detectedDate, DateTime(2026, 10, 31));
    expect(entries.first.needsDeadlineTimeConfirmation, isTrue);
    expect(entries.first.importReadyDeadline, isNull);
    expect(
      entries.first.suggestedDeadline(
        platform: CommissionPlatform.mihuashi,
        isQuickCommission: false,
      ),
      DateTime(2026, 10, 31, 23, 59),
    );
    expect(
      entries.first.suggestedDeadline(
        platform: CommissionPlatform.mihuashi,
      ),
      isNull,
    );
    expect(
      entries.first.suggestedDeadline(
        platform: CommissionPlatform.mihuashi,
        isQuickCommission: true,
      ),
      isNull,
    );
    expect(
      entries.first.suggestedDeadline(platform: CommissionPlatform.huajia),
      isNull,
    );
    expect(
      entries.first.deadlineWithChosenTime(hour: 21, minute: 30),
      DateTime(2026, 10, 31, 21, 30),
    );
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
    expect(entries.first.needsDeadlineTimeConfirmation, isFalse);
    expect(entries.first.importReadyDeadline, DateTime(2026, 10, 8, 16, 48));
    expect(
      entries.first.suggestedDeadline(platform: CommissionPlatform.mihuashi),
      DateTime(2026, 10, 8, 16, 48),
    );
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
  test('date-only deadline requires an explicit valid clock time', () {
    final entries = const ScreenshotLayoutParser().parse(
      imageWidth: 690,
      imageHeight: 1000,
      lines: [
        at('测试单主', 150),
        at('【常驻】黑白摸鱼头3.0', 250),
        at('2026-10-31', 400),
      ],
    );
    expect(entries.length, 1);
    final candidate = entries.single;
    expect(candidate.importReadyDeadline, isNull);
    expect(() => candidate.deadlineWithChosenTime(hour: 24, minute: 0),
        throwsRangeError);
    expect(() => candidate.deadlineWithChosenTime(hour: 18, minute: 60),
        throwsRangeError);
    // A user can explicitly opt into midnight, but OCR will not assume it.
    expect(candidate.deadlineWithChosenTime(hour: 0, minute: 0),
        DateTime(2026, 10, 31));
  });

}
