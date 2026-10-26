import 'package:flutter_app/features/imports/domain/screenshot_import_kind_detection.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScreenshotTextLine line(String text, double y, {double x = 40}) =>
      ScreenshotTextLine(
        text: text,
        left: x,
        top: y,
        right: x + 260,
        bottom: y + 40,
      );

  test('MiHuashi detail strongly suggests order import', () {
    final kind = detectScreenshotImportContentKind(
      imageWidth: 1272,
      imageHeight: 2800,
      lines: [
        line('工作板', 180, x: 530),
        line('一则生贺～', 380),
        line('距截稿日 2026-11-15 还有 25 天', 520),
        line('一个弹珠', 680, x: 200),
        line('验收节点', 910),
        line('已付 ¥148', 920, x: 760),
        line('总额 ¥740', 1000, x: 760),
        line('稿件夹', 1240),
        line('进程动态', 1240, x: 330),
        line('参考信息', 1240, x: 660),
        line('上传稿件', 2450, x: 900),
      ],
    );

    expect(kind, ScreenshotImportContentKind.orders);
  });

  test('Huajia completed storefront strongly suggests product import', () {
    final kind = detectScreenshotImportContentKind(
      imageWidth: 1272,
      imageHeight: 2800,
      lines: [
        line('已完成', 590, x: 1080),
        line('希腊风小白裙【服设批发】', 740, x: 500),
        line('截稿时间：拍下自动提交源文件', 820, x: 400),
        line('￥10', 960, x: 1100),
        line('查看评价', 1140, x: 960),
      ],
    );

    expect(kind, ScreenshotImportContentKind.products);
  });

  test('ambiguous order list does not force a switch', () {
    final kind = detectScreenshotImportContentKind(
      imageWidth: 1272,
      imageHeight: 2800,
      lines: [
        line('我卖出的', 100, x: 500),
        line('【常驻】头像', 400, x: 350),
        line('￥94', 470, x: 900),
      ],
    );

    expect(kind, isNull);
  });
}
