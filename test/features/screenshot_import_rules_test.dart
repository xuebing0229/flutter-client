import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_rules.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  test('platform cues are preselected but ambiguous screenshots stay unknown', () {
    expect(
      preselectImportPlatform(['我卖出的', '当前交付节点']).platform,
      CommissionPlatform.huajia,
    );
    expect(
      preselectImportPlatform(['企划方名称', '定向企划']).platform,
      CommissionPlatform.mihuashi,
    );
    expect(preselectImportPlatform(['进行中', '2026-10-31']).platform, isNull);
  });

  test('import normalization does not strip the real order name', () {
    const title = '【常驻】 黑白摸鱼头3.0';
    expect(normalizedImportTitle(title), '【常驻】 黑白摸鱼头3.0');
    expect(normalizedImportTitle('  【常驻】  黑白摸鱼头3.0  '),
        normalizedImportTitle(title));
  });

  test('percent matches exact preset nodes with no nearest-node guess', () {
    expect(resolveImportNode(preset: defaultNodePreset, recognizedPercent: 60)
        .name, '上色');
    expect(resolveImportNode(preset: defaultNodePreset, recognizedPercent: 55)
        .id, defaultNodePreset.nodes.first.id);
    expect(resolveImportNode(preset: defaultNodePreset)
        .id, defaultNodePreset.nodes.first.id);
  });

  test('remembered preset has priority and is scoped by full title and platform', () {
    final other = NodePreset(
      id: 'special',
      name: '特殊单',
      nodes: [
        const NodeDefinition(
            id: 'start', name: '开始', iconKey: 'edit',
            colorValue: 0, progressPercent: 0),
        const NodeDefinition(
            id: 'done', name: '完成', iconKey: 'check',
            colorValue: 0, progressPercent: 100),
      ],
    );
    final selection = resolveImportPreset(
      platform: CommissionPlatform.mihuashi,
      title: '【常驻】 黑白摸鱼头3.0',
      presets: [defaultNodePreset, other],
      existingOrders: const [],
      rememberedPresetIds: {
        orderPresetMemoryKey(CommissionPlatform.mihuashi,
            '【常驻】 黑白摸鱼头3.0'): other.id,
      },
    );
    expect(selection.id, other.id);
    expect(resolveImportPreset(
      platform: CommissionPlatform.huajia,
      title: '【常驻】 黑白摸鱼头3.0',
      presets: [defaultNodePreset, other],
      existingOrders: const [],
      rememberedPresetIds: {
        orderPresetMemoryKey(CommissionPlatform.mihuashi,
            '【常驻】 黑白摸鱼头3.0'): other.id,
      },
    ).id, defaultNodePreset.id);
  });

  test('duplicate order check includes client title deadline and platform', () {
    final deadline = DateTime(2026, 10, 31, 18, 0);
    final current = QueueOrder(
      id: 'existing',
      platform: CommissionPlatform.huajia,
      title: '【常驻】 黑白摸鱼头3.0',
      clientName: '买家甲',
      deadline: deadline,
      nodePresetId: defaultNodePreset.id,
      nodePresetSnapshot: defaultNodePreset,
      currentNodeId: defaultNodePreset.nodes.first.id,
    );
    expect(hasPotentialOrderDuplicate(
      platform: CommissionPlatform.huajia,
      title: '【常驻】 黑白摸鱼头3.0',
      clientName: '买家甲',
      deadline: deadline,
      existingOrders: [current],
    ), isTrue);
    expect(hasPotentialOrderDuplicate(
      platform: CommissionPlatform.huajia,
      title: '【常驻】 黑白摸鱼头3.0',
      clientName: '买家乙',
      deadline: deadline,
      existingOrders: [current],
    ), isFalse);
  });
}
