import 'package:flutter/material.dart';

enum ConcurrentEditChoice { cancel, useSynced, keepLocal }

Future<ConcurrentEditChoice> showConcurrentEditDialog({
  required BuildContext context,
  required String subject,
  required List<String> fields,
}) async {
  final choice = await showDialog<ConcurrentEditChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$subject已在另一处更新'),
      content: Text(
        '你编辑期间，同步设备也修改了${fields.join('、')}。'
        '未冲突的字段会自动合并；这些同字段修改需要你选择保留哪一边。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            ConcurrentEditChoice.cancel,
          ),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            ConcurrentEditChoice.useSynced,
          ),
          child: const Text('使用同步版本'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            ConcurrentEditChoice.keepLocal,
          ),
          child: const Text('保留本机修改'),
        ),
      ],
    ),
  );

  return choice ?? ConcurrentEditChoice.cancel;
}
