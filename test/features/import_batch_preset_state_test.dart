import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/import_batch_preset_state.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_rules.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  const special = NodePreset(
    id: 'special-preset',
    name: '常驻作品专用',
    nodes: [
      NodeDefinition(
        id: 'first',
        name: '开始',
        iconKey: 'pause',
        colorValue: 0,
        progressPercent: 0,
      ),
      NodeDefinition(
        id: 'draft60',
        name: '线稿',
        iconKey: 'edit',
        colorValue: 0,
        progressPercent: 60,
      ),
      NodeDefinition(
        id: 'almost80',
        name: '上色',
        iconKey: 'palette',
        colorValue: 0,
        progressPercent: 80,
      ),
      NodeDefinition(
        id: 'end',
        name: '成稿',
        iconKey: 'image',
        colorValue: 0,
        progressPercent: 100,
      ),
    ],
  );

  ImportPresetDraft draft(
    String id, {
    String title = '【常驻】 黑白摸鱼头3.0',
    CommissionPlatform platform = CommissionPlatform.mihuashi,
    int? percentage,
    bool presetEdited = false,
  }) =>
      ImportPresetDraft(
        id: id,
        platform: platform,
        title: title,
        presetId: defaultNodePreset.id,
        nodeId: defaultNodePreset.nodes.first.id,
        recognizedPercent: percentage,
        presetManuallyChanged: presetEdited,
      );

  test('editing first row instantly suggests same preset to later same-name rows', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [
        draft('first', percentage: 60),
        draft('second', percentage: 80),
        draft('third', percentage: 55),
      ],
    );
    var notifications = 0;
    state.addListener(() => notifications++);

    state.selectPreset('first', special.id);

    expect(notifications, 1);
    expect(state.byId('first').presetId, special.id);
    expect(state.byId('first').nodeId, 'draft60');
    expect(state.byId('second').presetId, special.id);
    expect(state.byId('second').nodeId, 'almost80');
    expect(state.byId('third').presetId, special.id);
    // No matching 55% node; do not jump to the nearest one.
    expect(state.byId('third').nodeId, 'first');
    expect(state.pendingPresetChoices[
      orderPresetMemoryKey(CommissionPlatform.mihuashi, '【常驻】 黑白摸鱼头3.0')
    ], special.id);
    state.dispose();
  });

  test('editing the last item also updates matching items above it', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [
        draft('above-60', percentage: 60),
        draft('above-80', percentage: 80),
        draft('last-edited', percentage: 55),
      ],
    );

    state.selectPreset('last-edited', special.id);

    expect(state.byId('above-60').presetId, special.id);
    expect(state.byId('above-60').nodeId, 'draft60');
    expect(state.byId('above-80').presetId, special.id);
    expect(state.byId('above-80').nodeId, 'almost80');
    expect(state.byId('last-edited').nodeId, 'first');
    state.dispose();
  });

  test('editing the middle row updates both directions and preserves overrides', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [
        draft('above', percentage: 80),
        draft('manual-override', percentage: 60),
        draft('middle', percentage: 60),
        draft('below', percentage: 55),
        draft('different-platform', platform: CommissionPlatform.huajia),
      ],
    );

    state.selectNode('manual-override', defaultNodePreset.nodes.last.id);
    state.selectPreset('middle', special.id);

    expect(state.byId('above').presetId, special.id);
    expect(state.byId('above').nodeId, 'almost80');
    expect(state.byId('manual-override').presetId, defaultNodePreset.id);
    expect(state.byId('manual-override').nodeId, defaultNodePreset.nodes.last.id);
    expect(state.byId('middle').nodeId, 'draft60');
    expect(state.byId('below').presetId, special.id);
    expect(state.byId('below').nodeId, 'first');
    expect(state.byId('different-platform').presetId, defaultNodePreset.id);
    state.dispose();
  });

  test('distinct platforms, titles and explicitly changed later rows are safe', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [
        draft('first'),
        draft('same', percentage: 80),
        draft('custom', percentage: 60),
        draft('other-title', title: '【常驻】 红白摸鱼头3.0'),
        draft('other-platform', platform: CommissionPlatform.huajia),
      ],
    );

    state.selectPreset('custom', special.id);
    state.selectPreset('first', defaultNodePreset.id);

    expect(state.byId('same').presetId, defaultNodePreset.id);
    expect(state.byId('custom').presetId, special.id);
    expect(state.byId('other-title').presetId, defaultNodePreset.id);
    expect(state.byId('other-platform').presetId, defaultNodePreset.id);
    state.dispose();
  });

  test('a later node chosen by hand is not silently reset', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [
        draft('first'),
        draft('later'),
      ],
    );

    state.selectNode('later', defaultNodePreset.nodes.last.id);
    state.selectPreset('first', special.id);

    expect(state.byId('later').presetId, defaultNodePreset.id);
    expect(state.byId('later').nodeId, defaultNodePreset.nodes.last.id);
    state.dispose();
  });

  test('later OCR screenshot rows inherit unsaved batch choices immediately', () {
    final state = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [draft('first')],
    );
    state.selectPreset('first', special.id);
    state.appendRow(draft('from-second-screenshot', percentage: 80));

    expect(state.byId('from-second-screenshot').presetId, special.id);
    expect(state.byId('from-second-screenshot').nodeId, 'almost80');
    state.dispose();
  });

  test('preview selections are in memory and may be discarded', () {
    final first = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [draft('one')],
    );
    first.selectPreset('one', special.id);
    first.dispose();

    final nextPreview = ImportBatchPresetState(
      presets: [defaultNodePreset, special],
      rows: [draft('one')],
    );
    expect(nextPreview.pendingPresetChoices, isEmpty);
    expect(nextPreview.byId('one').presetId, defaultNodePreset.id);
    nextPreview.dispose();
  });
}
