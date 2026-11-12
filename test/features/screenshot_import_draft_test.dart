import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_draft.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_rules.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';

void main() {
  ScreenshotImportDraft create(String id, {
    int percent = 60,
    String title = '【常驻】 黑白摸鱼头3.0',
    bool priceRecognized = false,
  }) => ScreenshotImportDraft(
    id: id,
    sourceImageId: 'shot1',
    title: title,
    clientName: '画师测试',
    price: 94,
    priceRecognized: priceRecognized,
    platform: CommissionPlatform.mihuashi,
    detectedDate: DateTime(2026, 10, 31),
    deadline: DateTime(2026, 10, 31, 23, 59),
    deadlineConfirmed: true,
    recognizedPercent: percent,
    presetId: defaultNodePreset.id,
    nodeId: defaultNodePreset.nodes.first.id,
  );


  test('probable duplicate defaults to the more complete screenshot', () {
    final dayOnly = create('day-only');
    dayOnly.deadline = null;
    dayOnly.deadlineConfirmed = false;

    final detailed = ScreenshotImportDraft(
      id: 'detailed',
      sourceImageId: 'shot2',
      title: dayOnly.title,
      clientName: dayOnly.clientName,
      price: dayOnly.price,
      platform: dayOnly.platform,
      detectedDate: DateTime(2026, 10, 31, 23, 59),
      sourceHasClock: true,
      deadline: DateTime(2026, 10, 31, 23, 59),
      deadlineConfirmed: true,
      recognizedPercent: 60,
      presetId: defaultNodePreset.id,
      nodeId: defaultNodePreset.nodes.first.id,
    );

    expect(
      screenshotImportInformationScore(detailed),
      greaterThan(screenshotImportInformationScore(dayOnly)),
    );
    expect(preferredScreenshotDuplicate(dayOnly, detailed), same(detailed));
    // Stable fallback: equal-information duplicates keep the earlier row.
    expect(preferredScreenshotDuplicate(dayOnly, create('same')), same(dayOnly));
  });

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

  test('manual price fills only later same-title rows missing OCR price', () {
    final earlier = create('earlier')..price = 80;
    final changed = create('changed')..price = 120;
    final laterMissing = create('later-missing')..price = null;
    final laterRecognized = create(
      'later-recognized',
      priceRecognized: true,
    )..price = 135;
    final laterManual = create('later-manual')
      ..price = 150
      ..priceManuallyChanged = true;
    final otherTitle = create('other', title: '另一个橱窗')..price = 60;

    changed.priceManuallyChanged = true;
    cascadeScreenshotPrice(
      changed: changed,
      rows: [
        earlier,
        changed,
        laterMissing,
        laterRecognized,
        laterManual,
        otherTitle,
      ],
      price: 120,
    );

    expect(earlier.price, 80, reason: '以前的条目不能被回改');
    expect(changed.price, 120);
    expect(laterMissing.price, 120, reason: 'OCR 未识别价格时才跟随记忆价');
    expect(laterMissing.priceInputRevision, 1);
    expect(laterRecognized.price, 135, reason: 'OCR 识别出的价格必须优先');
    expect(laterRecognized.priceInputRevision, 0);
    expect(laterManual.price, 150, reason: '后面手动改过的条目优先');
    expect(otherTitle.price, 60);
  });

  test('price memory key follows complete normalized artwork title only', () {
    expect(
      orderPriceMemoryKey('  【常驻】  黑白摸鱼头3.0  '),
      orderPriceMemoryKey('【常驻】 黑白摸鱼头3.0'),
    );
    expect(
      orderPriceMemoryKey('【常驻】 黑白摸鱼头3.0'),
      isNot(orderPriceMemoryKey('【常驻】 黑白摸鱼头4.0')),
    );
  });

  test('screenshot commit rejects a preset removed by sync', () {
    final row = create('stale-preset')
      ..presetId = 'removed-preset'
      ..nodeId = 'removed-node';

    expect(
      validateScreenshotPresetSelection(
        row: row,
        presets: const <NodePreset>[defaultNodePreset],
      ),
      contains('删除'),
    );
  });

  test('screenshot commit rejects a node removed from the selected preset', () {
    final changed = NodePreset(
      id: 'changed-preset',
      name: '同步后的预设',
      nodes: const [
        NodeDefinition(
          id: 'new-node',
          name: '新节点',
          progressPercent: 20,
          iconKey: 'edit',
          colorValue: 0,
        ),
      ],
    );
    final row = create('stale-node')
      ..presetId = changed.id
      ..nodeId = 'old-node';

    expect(
      validateScreenshotPresetSelection(row: row, presets: <NodePreset>[changed]),
      contains('变化'),
    );
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
