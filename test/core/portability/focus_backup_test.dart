import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/features/focus/domain/focus_session.dart';

void main() {
  test('focus sessions survive full backup round trip', () {
    final started = DateTime.utc(2026, 10, 9, 12, 30);
    final ended = started.add(const Duration(hours: 1, minutes: 15));
    final backup = AppBackupData(
      exportedAt: ended,
      orders: const [],
      products: const [],
      nodePresets: const [],
      focusSessions: [
        FocusSession(
          id: 'focus-test',
          startedAt: started,
          endedAt: ended,
          orderId: 'order-test',
          orderTitleSnapshot: '测试排单',
        ),
      ],
    );

    final decoded = AppBackupData.decode(backup.encode(pretty: false));

    expect(decoded.focusSessions, hasLength(1));
    final session = decoded.focusSessions.single;
    expect(session.id, 'focus-test');
    expect(session.startedAt, started);
    expect(session.endedAt, ended);
    expect(session.orderId, 'order-test');
    expect(session.orderTitleSnapshot, '测试排单');
  });
}
