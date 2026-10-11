import 'package:flutter/material.dart';

Future<String?> showFocusRecoveryDialog({
  required BuildContext context,
  required DateTime cutoff,
  bool fromBackup = false,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = cutoff.toLocal();
  final cutoffText =
      '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(fromBackup ? '备份中有未结束的专注' : '发现未结束的专注'),
      content: Text(
        fromBackup
            ? '这份备份导出时，这次专注还在计时。'
                '你可以继续计时、按备份时间（$cutoffText）结束，或作废这次记录。'
            : '上次离开公会时，这次专注还在计时。'
                '你可以继续计时、按上次安全记录时间（$cutoffText）结束，或作废这次记录。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('discard'),
          child: const Text('作废本次'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('end'),
          child: Text(fromBackup ? '按备份时间结束' : '按记录时间结束'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop('continue'),
          child: const Text('继续计时'),
        ),
      ],
    ),
  );
}
