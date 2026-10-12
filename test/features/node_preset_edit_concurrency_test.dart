import 'package:flutter/material.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/presentation/node_preset_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NodePreset preset({
    required String name,
    String firstNodeName = '草图',
  }) {
    return NodePreset(
      id: 'shared-preset',
      name: name,
      nodes: <NodeDefinition>[
        NodeDefinition(
          id: 'draft',
          name: firstNodeName,
          iconKey: 'edit',
          colorValue: 0xFF777777,
          progressPercent: 0,
        ),
        const NodeDefinition(
          id: 'done',
          name: '成稿',
          iconKey: 'image',
          colorValue: 0xFF777777,
          progressPercent: 100,
        ),
      ],
    );
  }

  testWidgets('preset editor merges independent remote field changes', (
    tester,
  ) async {
    final store = NodePresetStore();
    addTearDown(store.dispose);
    final baseline = preset(name: '原预设');
    store.upsert(baseline);

    await tester.pumpWidget(
      MaterialApp(
        home: NodePresetEditorPage(store: store, preset: baseline),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '本机名称');

    // The remote device changes only the node list while this editor stays
    // open. Saving a local name change must not put the old nodes back.
    store.upsert(preset(name: '原预设', firstNodeName: '远端草图'));
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final merged = store.presets.firstWhere(
      (item) => item.id == baseline.id,
    );
    expect(merged.name, '本机名称');
    expect(merged.nodes.first.name, '远端草图');
  });

  testWidgets('same-field preset edit asks before overwriting remote value', (
    tester,
  ) async {
    final store = NodePresetStore();
    addTearDown(store.dispose);
    final baseline = preset(name: '原预设');
    store.upsert(baseline);

    await tester.pumpWidget(
      MaterialApp(
        home: NodePresetEditorPage(store: store, preset: baseline),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '本机名称');
    store.upsert(preset(name: '远端名称'));
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('这个预设已在另一处更新'), findsOneWidget);
    expect(
      store.presets.firstWhere((item) => item.id == baseline.id).name,
      '远端名称',
    );

    await tester.tap(find.text('保留本机修改'));
    await tester.pumpAndSettle();

    expect(
      store.presets.firstWhere((item) => item.id == baseline.id).name,
      '本机名称',
    );
  });

  testWidgets('deleted remote preset is not silently resurrected by stale editor', (
    tester,
  ) async {
    final store = NodePresetStore();
    addTearDown(store.dispose);
    final baseline = preset(name: '原预设');
    store.upsert(baseline);

    await tester.pumpWidget(
      MaterialApp(
        home: NodePresetEditorPage(store: store, preset: baseline),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '本机名称');
    store.remove(baseline.id);
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      store.presets.where((item) => item.id == baseline.id),
      isEmpty,
    );
    expect(find.text('这个预设已在另一处删除，请返回后重新新建。'), findsOneWidget);
  });
}
