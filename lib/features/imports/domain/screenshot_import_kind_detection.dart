import 'screenshot_huajia_detail_parser.dart';
import 'screenshot_layout_parser.dart';

enum ScreenshotImportContentKind { orders, products }

/// Only returns a kind when the screenshot contains strong, layout-specific
/// evidence. Ambiguous list/card screenshots stay null so the current import
/// mode is never switched on a guess.
ScreenshotImportContentKind? detectScreenshotImportContentKind({
  required List<ScreenshotTextLine> lines,
  required double imageWidth,
  required double imageHeight,
}) {
  if (isHuajiaOrderDetailScreenshot(
        lines: lines,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ) ||
      isMiHuashiOrderDetailScreenshot(
        lines: lines,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      )) {
    return ScreenshotImportContentKind.orders;
  }

  final text = lines.map((line) => line.text.trim()).join(' ');

  // Huajia completed storefront/product screenshots expose "查看评价" together
  // with a delivery/deadline row. That combination is specific enough to
  // offer a products switch without reclassifying ordinary order lists.
  final huajiaCompletedStorefront =
      text.contains('查看评价') &&
      text.contains('截稿时间') &&
      (text.contains('已完成') ||
          text.contains('批发') ||
          text.contains('拍下自动提交源文件'));
  if (huajiaCompletedStorefront) {
    return ScreenshotImportContentKind.products;
  }

  return null;
}
