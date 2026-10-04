import 'package:flutter/services.dart';

import '../account/account_models.dart';
import '../../features/orders/domain/queue_order.dart';

class OrderDeadlineReminderService {
  const OrderDeadlineReminderService();

  static const MethodChannel _channel = MethodChannel('app.order_reminders');

  Future<bool> ensurePermission() async {
    final granted = await _channel.invokeMethod<bool>('ensurePermission');
    if (granted == null) {
      throw StateError('通知权限请求没有返回结果。');
    }
    return granted;
  }

  Future<Map<String, dynamic>> getDiagnostics() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'getDiagnostics',
    );
    if (raw == null) {
      throw StateError('通知诊断没有返回结果。');
    }
    return raw;
  }

  Future<Map<String, dynamic>> scheduleDiagnosticTest({
    Duration delay = const Duration(minutes: 1),
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'scheduleDiagnosticTest',
      <String, Object>{
        'delaySeconds': delay.inSeconds,
      },
    );
    if (raw == null) {
      throw StateError('通知诊断测试没有返回结果。');
    }
    return raw;
  }

  Future<void> openBatteryOptimizationSettings() async {
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  Future<void> openExactAlarmSettings() async {
    await _channel.invokeMethod<void>('openExactAlarmSettings');
  }

  Future<void> openNotificationSettings() async {
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  Future<void> markBackgroundGuideShown() async {
    await _channel.invokeMethod<void>('markBackgroundGuideShown');
  }

  Future<void> clearActiveAccount() async {
    await _channel.invokeMethod<void>('clearActiveAccount');
  }

  Future<void> activateAccount({
    required String accountId,
  }) async {
    requireValidAccountId(accountId);
    await _channel.invokeMethod<void>(
      'activateAccount',
      <String, Object>{'accountId': accountId},
    );
  }

  Future<void> clearAll({
    required String accountId,
  }) async {
    requireValidAccountId(accountId);
    await _channel.invokeMethod<void>(
      'clearAll',
      <String, Object>{'accountId': accountId},
    );
  }

  Future<void> syncOrders({
    required String accountId,
    required Iterable<QueueOrder> orders,
  }) async {
    requireValidAccountId(accountId);
    final now = DateTime.now();
    final reminders = <Map<String, Object>>[];

    for (final order in orders) {
      final deadline = order.deadline;
      if (deadline == null ||
          !deadline.isAfter(now) ||
          order.isCompleted ||
          order.isArchived) {
        continue;
      }

      void addReminder(String kind, Duration before, String label) {
        final triggerAt = deadline.subtract(before);
        if (!triggerAt.isAfter(now)) return;

        reminders.add({
          'key': '$accountId:${order.id}:$kind',
          'orderId': order.id,
          'title': order.title,
          'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
          'deadlineAtMillis': deadline.millisecondsSinceEpoch,
          'kind': kind,
          'label': label,
        });
      }

      addReminder('7d', const Duration(days: 7), '7天');
      addReminder('1d', const Duration(days: 1), '1天');
    }

    await _channel.invokeMethod<void>(
      'sync',
      <String, Object>{
        'accountId': accountId,
        'reminders': reminders,
      },
    );
  }
}
