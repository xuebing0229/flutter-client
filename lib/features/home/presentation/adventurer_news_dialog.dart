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
              width: math.max(0.0, math.min(540.0, size.width - 100)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.62),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        history
                            ? '公会历次更新记录'
                            : '${notice.previousBuild} → ${notice.currentBuild} · 本次更新内容',
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
                        for (final entry in notice.entries)
                          _NewsEntry(entry: entry),
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

/// One continuous reading surface; the catalog remains versioned but the
/// interface must not display each entry inside another separate card.
class _NewsEntry extends StatelessWidget {
  const _NewsEntry({required this.entry});

  final AdventurerNewsEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  entry.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'v${entry.introducedBuild}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(entry.description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
