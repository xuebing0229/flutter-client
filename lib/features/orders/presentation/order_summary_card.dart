import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/presentation/summary_card_widgets.dart';
import '../domain/queue_order.dart';

class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({
    required this.order,
    required this.onTap,
    this.onLongPress,
    this.onConfirmNode,
    this.onDecreaseNodeProgress,
    this.onIncreaseNodeProgress,
    this.showPlatform = true,
    this.showClient = true,
    this.showTags = false,
    this.showNodeProgress = true,
    this.compact = false,
    this.hasSyncConflict = false,
    super.key,
  });

  final QueueOrder order;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onConfirmNode;
  final VoidCallback? onDecreaseNodeProgress;
  final VoidCallback? onIncreaseNodeProgress;
  final bool showPlatform;
  final bool showClient;
  final bool showTags;
  final bool showNodeProgress;
  final bool compact;
  final bool hasSyncConflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentNode = order.currentNode;

    return SummaryCardSurface(
      compact: compact,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                Row(
                  children: [
                    if (showPlatform)
                      SummaryTag(
                        text: order.platform.label,
                        compact: true,
                      ),
                    if (showTags && order.tags.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: SummaryTag(
                          text: '#'+order.tags.first,
                          compact: true,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (hasSyncConflict) ...[
                      const Tooltip(
                        message: '有同步冲突待确认',
                        child: _SyncConflictDot(),
                      ),
                      const SizedBox(width: 7),
                    ],
                    if (order.isPinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _DeadlineStatusBadge(
                      order: order,
                      compact: true,
                      neverEllipsize: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  order.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ] else
                Row(
                  children: [
                    if (showPlatform) ...[
                      SummaryTag(text: order.platform.label),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        order.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (hasSyncConflict) ...[
                      const Tooltip(
                        message: '有同步冲突待确认',
                        child: _SyncConflictDot(),
                      ),
                      const SizedBox(width: 7),
                    ],
                    if (order.isPinned) ...[
                      Icon(
                        Icons.push_pin_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 7),
                    ],
                    _DeadlineStatusBadge(order: order),
                  ],
                ),
              if (!compact && showTags && order.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    for (final tag in order.tags)
                      SummaryTag(text: '#'+tag),
                  ],
                ),
              ],
              if (showClient) ...[
                SizedBox(height: compact ? 10 : 13),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: compact ? 16 : 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        order.clientName.isEmpty ? '未填写' : order.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: compact ? theme.textTheme.bodySmall : null,
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: compact ? 10 : 13),
              Divider(height: 1, color: colors.outlineVariant),
              SizedBox(height: compact ? 9 : 13),
              if (compact)
                _CompactDeadlineMeta(deadline: order.deadline)
              else
                SummaryMetaItem(
                  icon: Icons.calendar_today_outlined,
                  label: order.deadline == null
                      ? '截稿时间未设置'
                      : _formatDateTime(order.deadline!),
                ),
              SizedBox(height: compact ? 7 : 9),
              SummaryMetaItem(
                icon: Icons.route_outlined,
                label: '${currentNode.name} ${currentNode.progressPercent}%',
                compact: compact,
              ),
              SizedBox(height: compact ? 7 : 9),
              SummaryMetaItem(
                icon: Icons.payments_outlined,
                label: '实收 ¥ ${_formatMoney(order.realIncome)}',
                compact: compact,
              ),
              if (showNodeProgress) ...[
                SizedBox(height: compact ? 9 : 11),
                if (onDecreaseNodeProgress != null ||
                    onIncreaseNodeProgress != null)
                  _NodeWorkProgress(
                    progress: order.currentNodeProgress,
                    compact: compact,
                    onDecrease: order.currentNodeProgress <= 0
                        ? null
                        : onDecreaseNodeProgress,
                    onIncrease: order.currentNodeProgress >= 100
                        ? null
                        : onIncreaseNodeProgress,
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: currentNode.progressPercent / 100,
                      minHeight: compact ? 5 : 6,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
              ],
              if (onConfirmNode != null) ...[
                SizedBox(height: compact ? 10 : 12),
                SizedBox(
                  width: double.infinity,
                  child: ResponsiveCardActionButton(
                    onPressed: onConfirmNode,
                    icon: Icons.check_circle_outline_rounded,
                    label: '确认节点',
                    compact: compact,
                  ),
                ),
              ],
        ],
      ),
    );
  }
}

class _CompactDeadlineMeta extends StatelessWidget {
  const _CompactDeadlineMeta({required this.deadline});

  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
      height: 1.15,
    );

    if (deadline == null) {
      return Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text('截稿时间未设置', style: style)),
        ],
      );
    }

    String two(int number) => number.toString().padLeft(2, '0');
    final deadlineText =
        '${deadline!.year}-${two(deadline!.month)}-${two(deadline!.day)}\n'
        '${two(deadline!.hour)}:${two(deadline!.minute)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            deadlineText,
            maxLines: 2,
            softWrap: false,
            textAlign: TextAlign.left,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _SyncConflictDot extends StatelessWidget {
  const _SyncConflictDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _NodeWorkProgress extends StatelessWidget {
  const _NodeWorkProgress({
    required this.progress,
    required this.compact,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int progress;
  final bool compact;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget stepButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      final disabled = onPressed == null;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? () {} : null,
        onLongPress: disabled ? () {} : null,
        child: IconButton(
          tooltip: disabled ? null : tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
          ),
          iconSize: compact ? 18 : 20,
          icon: Icon(icon),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var index = 0; index < 10; index++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: compact ? 7 : 8,
                  decoration: BoxDecoration(
                    color: index < progress ~/ 10
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (index != 9) SizedBox(width: compact ? 2 : 3),
            ],
          ],
        ),
        SizedBox(height: compact ? 5 : 7),
        Row(
          children: [
            stepButton(
              icon: Icons.remove_rounded,
              tooltip: '节点进度 -10%',
              onPressed: onDecrease,
            ),
            Expanded(
              child: Text(
                '$progress%',
                textAlign: TextAlign.center,
                style: (compact
                        ? Theme.of(context).textTheme.labelSmall
                        : Theme.of(context).textTheme.labelMedium)
                    ?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            stepButton(
              icon: Icons.add_rounded,
              tooltip: '节点进度 +10%',
              onPressed: onIncrease,
            ),
          ],
        ),
      ],
    );
  }
}

String formatOrderDateTime(DateTime value) => _formatDateTime(value);

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _DeadlineStatusBadge extends StatefulWidget {
  const _DeadlineStatusBadge({
    required this.order,
    this.compact = false,
    this.neverEllipsize = false,
  });

  final QueueOrder order;
  final bool compact;
  final bool neverEllipsize;

  @override
  State<_DeadlineStatusBadge> createState() => _DeadlineStatusBadgeState();
}

class _DeadlineStatusBadgeState extends State<_DeadlineStatusBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _deadlineStatus(widget.order, DateTime.now());

    final Color background;
    final Color foreground;

    if (widget.order.isCompleted) {
      background = colors.primaryContainer;
      foreground = colors.onPrimaryContainer;
    } else if (status.overdue) {
      background = colors.errorContainer;
      foreground = colors.onErrorContainer;
    } else if (status.within24Hours) {
      background = colors.tertiaryContainer;
      foreground = colors.onTertiaryContainer;
    } else {
      background = colors.surfaceContainerHighest;
      foreground = colors.onSurfaceVariant;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 7 : 9,
          vertical: widget.compact ? 4 : 5,
        ),
        child: Text(
          status.label,
          maxLines: 1,
          overflow: widget.neverEllipsize
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          softWrap: false,
          style: (widget.compact
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.labelMedium)
              ?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

_DeadlineStatus _deadlineStatus(QueueOrder order, DateTime now) {
  if (order.isCompleted) {
    return const _DeadlineStatus(
      label: '已交稿',
      overdue: false,
      within24Hours: false,
    );
  }

  final deadline = order.deadline;
  if (deadline == null) {
    return const _DeadlineStatus(
      label: '未定稿期',
      overdue: false,
      within24Hours: false,
    );
  }

  final raw = deadline.difference(now);
  final overdue = raw.isNegative;
  final duration = raw.abs();

  return _DeadlineStatus(
    label: overdue
        ? '已逾期 ${_formatRemaining(duration)}'
        : '剩余 ${_formatRemaining(duration)}',
    overdue: overdue,
    within24Hours: !overdue && duration <= const Duration(hours: 24),
  );
}

String _formatRemaining(Duration duration) {
  if (duration > const Duration(hours: 24)) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    return '$days天$hours小时';
  }

  if (duration >= const Duration(hours: 1)) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours小时$minutes分';
  }

  final minutes = (duration.inSeconds / 60).ceil().clamp(1, 59);
  return '$minutes分';
}

class _DeadlineStatus {
  const _DeadlineStatus({
    required this.label,
    required this.overdue,
    required this.within24Hours,
  });

  final String label;
  final bool overdue;
  final bool within24Hours;
}

String _formatMoney(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
