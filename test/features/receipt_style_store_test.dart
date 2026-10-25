import 'package:flutter_app/features/shared/domain/receipt_style_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt header follows account name until customized', () {
    final store = ReceiptStyleStore();

    expect(store.effectiveHeaderText('雪饼'), '雪饼');

    store.setHeaderText('画师工作室');
    expect(store.effectiveHeaderText('雪饼'), '画师工作室');

    store.setHeaderText('');
    expect(store.effectiveHeaderText('雪饼'), isEmpty);

    store.resetDefault();
    expect(store.effectiveHeaderText('新账号名'), '新账号名');
  });

  test('new presets preserve the resolved header text', () {
    final store = ReceiptStyleStore();
    store.setHeaderText('画师工作室');

    final preset = store.saveCurrentPreset(
      '测试预设',
      resolvedHeaderText: store.effectiveHeaderText('雪饼'),
    );

    expect(preset.headerText, '画师工作室');
    expect(ReceiptStylePreset.fromJson(preset.toJson()).headerText, '画师工作室');
  });

  test('old presets without header text remain readable', () {
    final preset = ReceiptStylePreset.fromJson(<String, dynamic>{
      'id': 'legacy',
      'name': '旧预设',
      'fontColorValue': ReceiptStyleStore.defaultFontColorValue,
    });

    expect(preset.headerText, isNull);
  });
}
