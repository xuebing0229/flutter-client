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
                  child: Text(
                    '冒险者新见闻',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math.max(0.0, math.min(540.0, size.width - 100)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.58),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        history
                            ? '公会历次新增与优化'
                            : '${notice.previousBuild} → ${notice.currentBuild} · 本次新增 ${notice.entries.length} 项',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (notice.entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            '本次暂无单独登记的新见闻。',
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      else
                        DecoratedBox(
                          key: const ValueKey('adventurer-news-unified-content'),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var index = 0;
                                    index < notice.entries.length;
                                    index++) ...[
                                  if (index != 0)
                                    const SizedBox(height: 20),
                                  Text(
                                    notice.entries[index].title,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    notice.entries[index].description,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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
