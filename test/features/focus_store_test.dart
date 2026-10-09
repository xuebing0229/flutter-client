import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/focus/domain/focus_session.dart';
import 'package:flutter_app/features/focus/state/focus_store.dart';

void main() {
  test('自由专注开始和结束后保留完整记录', () {
    final store = FocusStore();
    final startedAt = DateTime(2026, 10, 9, 20, 0);
    final endedAt = DateTime(2026, 10, 9, 20, 25, 30);

    final started = store.start(startedAt: startedAt);
    expect(started.displayTitle, '自由专注');
    expect(store.activeSession?.id, started.id);

    final stopped = store.stop(endedAt: endedAt);
    expect(stopped?.endedAt, endedAt);
    expect(store.activeSession, isNull);
    expect(store.sessions.single.elapsedAt(endedAt), const Duration(minutes: 25, seconds: 30));

    store.dispose();
  });

  test('关联排单使用 ID 锁定，同时保留标题快照', () {
    final store = FocusStore();
    final session = store.start(
      orderId: 'order-1',
      orderTitleSnapshot: '同名排单',
      startedAt: DateTime(2026, 10, 9, 20, 0),
    );

    expect(session.orderId, 'order-1');
    expect(session.displayTitle, '同名排单');
    expect(
      () => store.start(
        orderId: 'order-2',
        orderTitleSnapshot: '另一个排单',
      ),
      throwsStateError,
    );

    store.dispose();
  });

  test('跨设备意外产生多个活动记录时，一次结束会全部收口', () {
    final store = FocusStore();
    store.replaceAll(<FocusSession>[
      FocusSession(
        id: 'focus-a',
        startedAt: DateTime(2026, 10, 9, 20, 0),
        orderId: 'order-a',
        orderTitleSnapshot: 'A',
      ),
      FocusSession(
        id: 'focus-b',
        startedAt: DateTime(2026, 10, 9, 20, 5),
        orderId: 'order-b',
        orderTitleSnapshot: 'B',
      ),
    ]);

    expect(store.activeSession?.id, 'focus-b');
    store.stop(endedAt: DateTime(2026, 10, 9, 20, 30));

    expect(store.sessions.where((session) => session.isActive), isEmpty);
    expect(
      store.sessions.every(
        (session) => session.endedAt == DateTime(2026, 10, 9, 20, 30),
      ),
      isTrue,
    );

    store.dispose();
  });
}
