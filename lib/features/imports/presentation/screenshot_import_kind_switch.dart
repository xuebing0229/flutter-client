import 'package:flutter/material.dart';

import '../domain/screenshot_import_kind.dart';
import '../domain/screenshot_import_kind_detection.dart';

ScreenshotImportKind importKindForDetectedContent(
  ScreenshotImportContentKind detected,
) {
  return detected == ScreenshotImportContentKind.orders
      ? ScreenshotImportKind.orders
      : ScreenshotImportKind.products;
}

Future<ScreenshotImportKind?> offerScreenshotImportKindSwitch({
  required BuildContext context,
  required ScreenshotImportKind currentKind,
  required ScreenshotImportContentKind detected,
  required int existingCount,
}) async {
  final target = importKindForDetectedContent(detected);
  if (target == currentKind) return null;

  final targetLabel = target.label;
  final currentLabel = currentKind.label;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('检测到更像$targetLabel截图'),
      content: Text(
        '当前正在$currentLabel导入，但这张截图具有明确的$targetLabel页面特征。'
        "${existingCount == 0 ? '' : '切换后会清空当前预览中的 $existingCount 条记录。'}"
        '是否切换到$targetLabel导入并继续处理这批截图？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('继续按$currentLabel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('切换到$targetLabel'),
        ),
      ],
    ),
  );
  return accepted == true ? target : null;
}