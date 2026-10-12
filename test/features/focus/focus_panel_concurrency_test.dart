import 'package:flutter/material.dart';
import 'package:flutter_app/features/focus/presentation/focus_panel.dart';
import 'package:flutter_app/features/focus/state/focus_store.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'focus target picked from a stale dialog cannot bind an archived order',
    (tester) async {
      final orders = OrderStore();
      final focus = FocusStore();
      addTearDown(orders.dispose);
      addTearDown(focus.dispose);

      orders.addOrder(
        QueueOrder(
          id: 'focus-order',
          platform: CommissionPlatform.mihuashi,
          title: '并发排单',
          clientName: '单主',
          deadline: null,
          nodePresetId: defaultNodePreset.id,
          nodePresetSnapshot: defaultNodePreset,
          currentNodeId: defaultNodePreset.nodes.first.id,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusPanel(
              orderStore: orders,
              focusStore: focus,
              onOpenOrder: (_) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('开始专注'));
      await tester.pump();
      expect(find.text('选择本次专注'), findsOneWidget);

      // The target remains visible in the already-open dialog, but sync has
      // archived it before the user taps that stale card.
      orders.archiveAsSettled('focus-order');
      await tester.pump();

      await tester.tap(find.text('并发排单'));
      await tester.pump();

      expect(focus.activeSession, isNull);
      expect(find.text('这笔排单状态已经更新，请按当前列表重新选择。'), findsOneWidget);
    },
  );
}
