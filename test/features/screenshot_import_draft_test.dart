import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_draft.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';

void main() {
  ScreenshotImportDraft create(String id, {
    int percent = 60,
    String title = '【常驻】 黑白摸鱼头3.0',
  }) => ScreenshotImportDraft(
    id: id,
    sourceImageId: 'shot1',
    title: title,
    clientName: '画师测试',
    price: 94,
    platform: CommissionPlatform.mihuashi,
    detectedDate: DateTime(2026, 10, 31),
    deadline: DateTime(2026, 10, 31, 23, 59),
    deadlineConfirmed: true,
    recognizedPercent: percent,
    presetId: defaultNodePreset.id,
    nodeId: defaultNodePreset.nodes.first.id,
  );

  test('choosing last row preset changes all unmodified same-title rows', () {
    final custom = NodePreset(
      id: 'custom',
      name: '自定义预设',
      nodes: const [
        NodeDefinition(
          id: 'start', name: '草稿', progressPercent: 0,
          iconKey: 'edit', colorValue: 0,
        ),
        NodeDefinition(
          id: 'sixty', name: '上色', progressPercent: 60,
          iconKey: 'palette', colorValue: 0,
        ),
      ],
    );
    final top = create('top');
    final middle = create('middle', percent: 70);
    final bottom = create('bottom');
    final manual = create('manual');
    manual.nodeManuallyChanged = true;
    cascadeScreenshotPreset(
      changed: bottom,
      rows: [top, middle, bottom, manual],
      selectedPreset: custom,
    );
    expect(top.presetId, 'custom');
    expect(top.nodeId, 'sixty');
    expect(middle.nodeId, 'start');
    expect(bottom.presetId, 'custom');
    expect(manual.presetId, defaultNodePreset.id);
  });

  test('incomplete deadlines are held for review before an order write', () {
    final row = create('order');
    row.deadlineConfirmed = false;
    expect(row.validate(importingProducts: false), contains('截稿时间'));
    row.deadline = null;
    row.deadlineConfirmed = true; // User explicitly chooses 未设置.
    expect(row.validate(importingProducts: false), isNull);
  });

  test('product import does not require a client, time, or sale count', () {
    final row = create('product');
    row.clientName = '';
    row.deadlineConfirmed = false;
    row.deadline = null;
    row.saleType = ProductSaleType.multiple;
    expect(row.validate(importingProducts: true), isNull);
  });
}
