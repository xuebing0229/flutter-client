import 'package:flutter_app/features/imports/domain/screenshot_import_kind.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_kind_detection.dart';
import 'package:flutter_app/features/imports/presentation/screenshot_import_kind_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detected order content maps to shared order import kind', () {
    expect(
      importKindForDetectedContent(ScreenshotImportContentKind.orders),
      ScreenshotImportKind.orders,
    );
  });

  test('detected product content maps to shared product import kind', () {
    expect(
      importKindForDetectedContent(ScreenshotImportContentKind.products),
      ScreenshotImportKind.products,
    );
  });

  test('shared import kind labels stay consistent', () {
    expect(ScreenshotImportKind.orders.label, '排单');
    expect(ScreenshotImportKind.products.label, '成品');
  });
}
