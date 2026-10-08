import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/changelog/adventurer_news.dart';

/// Returns true only if the user deliberately dismisses the notice.
Future<bool> showAdventurerNewsDialog(
  BuildContext context, {
  required AdventurerNewsNotice notice,
  bool history = false,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final colors = theme.colorScheme;
          final size = MediaQuery.sizeOf(dialogContext);
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.auto_stories_rounded, color: colors.primary),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('冒险者新见闻', style: TextStyle(
                    fontWeight: FontWeight.w800,
                  )),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(540, size.width - 100),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.58),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        history
                            ? '公会历次更新记录'
                            : '从 ' + notice.previousBuild.toString() +
                                ' 号版本升级到 ' +
                                notice.currentBuild.toString() + ' 号版本',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (notice.entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            '本次版本暂无单独登记的新功能。',
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      else
                        for (final entry in notice.entries) ...[
                          _NewsCard(entry: entry),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(history ? '返回公会' : '我知道啦'),
              ),
            ],
          );
        },
      ) ??
      false;
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.entry});

  final AdventurerNewsEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本 ' + entry.introducedBuild.toString(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(entry.description, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
