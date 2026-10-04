import 'package:flutter/material.dart';

import '../../../core/notifications/order_deadline_reminder_service.dart';

bool isAggressiveReminderVendor(Map<String, dynamic> diagnostics) {
  final manufacturer =
      (diagnostics['manufacturer'] as String? ?? '').toLowerCase();
  final brand = (diagnostics['brand'] as String? ?? '').toLowerCase();
  final source = '$manufacturer $brand';
  return source.contains('oneplus') ||
      source.contains('oppo') ||
      source.contains('realme');
}

String reminderDeviceName(Map<String, dynamic> diagnostics) {
  final brand = (diagnostics['brand'] as String? ?? '').trim();
  final model = (diagnostics['model'] as String? ?? '').trim();
  return [brand, model].where((part) => part.isNotEmpty).join(' ');
}

Future<void> showReminderBackgroundGuide({
  required BuildContext context,
  required OrderDeadlineReminderService reminderService,
  bool force = false,
}) async {
  Map<String, dynamic> diagnostics = const <String, dynamic>{};

  try {
    diagnostics = await reminderService.getDiagnostics();
  } catch (_) {
    // The guide is still useful even if diagnostics are temporarily unavailable.
  }

  if (!context.mounted) return;

  final device = reminderDeviceName(diagnostics);
  final aggressiveVendor = isAggressiveReminderVendor(diagnostics);
  final notificationsEnabled = diagnostics['notificationsEnabled'] == true;
  final batteryOptimizationIgnored =
      diagnostics['batteryOptimizationIgnored'] == true;
  final backgroundGuideShown = diagnostics['backgroundGuideShown'] == true;

  final setupLooksComplete =
      notificationsEnabled &&
      batteryOptimizationIgnored &&
      backgroundGuideShown;
  if (!force && setupLooksComplete) return;

  final deviceHint = aggressiveVendor
      ? '检测到${device.isEmpty ? '一加 / OPPO / realme 系' : device}设备，这类系统后台管理通常更严格。\n\n'
      : device.isEmpty
          ? ''
          : '当前设备：$device。\n\n';

  final action = await showDialog<_ReminderGuideAction>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('让截稿提醒更稳'),
        content: Text(
          '$deviceHint'
          '① 通知权限：${notificationsEnabled ? '已开启' : '请保持开启'}\n'
          '② 电池优化：${batteryOptimizationIgnored ? '已关闭限制' : '建议关闭'}\n'
          '③ 最近任务：请手动给 App 上锁\n\n'
          '系统没有可靠接口让 App 自动替你锁定最近任务，所以第 ③ 步需要手动完成。'
          '锁定后可以正常切去做别的事，不需要一直停留在 App 里。'
          '${aggressiveVendor ? '\n\n如果系统会把“从最近任务划掉”当成主动结束应用，请尽量不要再手动划掉它。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ReminderGuideAction.later),
            child: const Text('稍后'),
          ),
          if (!batteryOptimizationIgnored)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _ReminderGuideAction.openBatterySettings,
              ),
              child: const Text('去关闭电池优化'),
            )
          else
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ReminderGuideAction.done),
              child: const Text('知道了'),
            ),
        ],
      );
    },
  );

  if (action != _ReminderGuideAction.later) {
    try {
      await reminderService.markBackgroundGuideShown();
    } catch (_) {
      // Guidance persistence is best-effort.
    }
  }

  if (action != _ReminderGuideAction.openBatterySettings ||
      !context.mounted) {
    return;
  }

  try {
    await reminderService.openBatteryOptimizationSettings();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('系统没有成功打开电池优化设置，可以稍后从设置里的“截稿提醒”进入。'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

enum _ReminderGuideAction {
  later,
  openBatterySettings,
  done,
}
