import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/focus/domain/focus_session.dart';
import 'package:flutter_app/features/focus/state/focus_store.dart';

void main() {
  test('free focus starts and can be ended at a chosen time', () {
    final store = FocusStore();
    final started = store.start();

    expect(started.isFreeFocus, isTrue);
    expect(store.activeSession?.id, started.id);

    final end = started.startedAt.add(const Duration(minutes: 42));
    final finished = store.stopActiveAt(end);

    expect(finished, isNotNull);
    expect(finished!.endedAt, end);
    expect(finished.durationAt(), const Duration(minutes: 42));
    expect(store.activeSession, isNull);
  });

  test('multiple synced active sessions resolve deterministically', () {
    final store = FocusStore();
    final firstStart = DateTime.utc(2026, 10, 9, 10);
    final secondStart = DateTime.utc(2026, 10, 9, 11);
    final first = FocusSession(
      id: 'focus-a',
      startedAt: firstStart,
      endedAt: null,
      orderId: null,
      orderTitleSnapshot: null,
    );
    final second = FocusSession(
      id: 'focus-b',
      startedAt: secondStart,
      endedAt: null,
      orderId: null,
      orderTitleSnapshot: null,
    );

    store.replaceAll([first, second]);

    expect(store.activeSession?.id, 'focus-b');
    expect(store.byId('focus-a').endedAt, secondStart);
  });

  test('cleanup requires a range and never removes active focus', () {
    final store = FocusStore();
    final active = store.start();

    expect(
      () => store.removeStartedInRange(),
      throwsArgumentError,
    );

    final removed = store.removeStartedInRange(
      start: active.startedAt.subtract(const Duration(days: 1)),
      end: active.startedAt.add(const Duration(days: 1)),
    );
    expect(removed, 0);
    expect(store.activeSession?.id, active.id);
  });
}
