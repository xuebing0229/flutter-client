enum ScreenshotImportKind { orders, products }

extension ScreenshotImportKindLabel on ScreenshotImportKind {
  bool get products => this == ScreenshotImportKind.products;
  String get label => products ? '成品' : '排单';
}
