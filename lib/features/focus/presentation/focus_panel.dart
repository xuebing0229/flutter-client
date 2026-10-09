import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/desktop_pet/desktop_pet_service.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../domain/focus_session.dart';
import '../state/focus_store.dart';

enum _FocusListMode { sessions, orders }
enum _FocusScope { all, orders, free }
enum _FocusSessionSortField { startedAt, duration }
enum _FocusGroupSortField { totalDuration, sessionCount, recentFocus }

class FocusPanel extends StatefulWidget {
  const FocusPanel({
    required this.orderStore,
    required this.focusStore,
    required this.onOpenOrder,
    this.desktopSettings,
    super.key,
  });

  final OrderStore orderStore;
  final FocusStore focusStore;
  final DesktopPetSettings? desktopSettings;
  final Future<void> Function(String orderId) onOpenOrder;

  @override
  State<FocusPanel> createState() => _FocusPanelState();
}

class _FocusPanelState extends State<FocusPanel> {
  Timer? _ticker;
  _FocusListMode _mode = _FocusListMode.sessions;
  _FocusScope _scope = _FocusScope.all;
  _FocusSessionSortField _sessionSortField = _FocusSessionSortField.startedAt;
  bool _sessionSortDescending = true;
  _FocusGroupSortField _groupSortField = _FocusGroupSortField.totalDuration;
  bool _groupSortDescending = true;
  DateTime? _filterStart;
  DateTime? _filterEnd;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.focusStore.activeSession != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  QueueOrder? _orderById(String? id) {
    if (id == null || !widget.orderStore.contains(id)) return null;
    return widget.orderStore.byId(id);
  }

  List<QueueOrder> get _activeOrders => widget.orderStore.orders
      .where((order) => !order.isArchived && !order.isCompleted)
      .toList(growable: false);

  String _targetLabel(FocusSession session) {
    if (session.isFreeFocus) return '自由专注';
    return _orderById(session.orderId)?.title ??
        session.orderTitleSnapshot ??
        '已删除排单';
  }

  String _formatDuration(Duration value) {
    final seconds = value.inSeconds.clamp(0, 999999999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final seed = current ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 10),
      initialDate: seed,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<_FocusTarget?> _chooseTarget() async {
    final orders = _activeOrders;
    return showDialog<_FocusTarget>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择本次专注'),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.self_improvement_rounded),
                  title: const Text('自由专注'),
                  subtitle: const Text('这次专注不绑定排单'),
                  onTap: () =>
                      Navigator.of(dialogContext).pop(const _FocusTarget()),
                ),
                if (orders.isNotEmpty) const Divider(),
                for (final order in orders)
                  ListTile(
                    leading: const Icon(Icons.draw_outlined),
                    title: Text(order.title),
                    subtitle: Text(
                      '${order.platform.label} · ${order.currentNode.name}',
                    ),
                    onTap: () =>
                        Navigator.of(dialogContext).pop(_FocusTarget(order)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _startFocus() async {
    if (widget.focusStore.activeSession != null) return;

    QueueOrder? order;
    final settings = widget.desktopSettings;
    if (settings != null) {
      await settings.refresh();
      if (!mounted) return;
      final selected = _orderById(settings.currentOrderId);
      if (selected != null &&
          !selected.isArchived &&
          !selected.isCompleted) {
        order = selected;
      } else {
        final picked = await _chooseTarget();
        if (picked == null) return;
        order = picked.order;
      }
    } else {
      final picked = await _chooseTarget();
      if (picked == null) return;
      order = picked.order;
    }

    widget.focusStore.start(order: order);
  }

  Future<void> _stopFocus() async {
    final active = widget.focusStore.activeSession;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('结束本次专注？'),
        content: Text(
          '${_targetLabel(active)}\n'
          '已专注 ${_formatDuration(active.durationAt())}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续专注'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('结束专注'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.focusStore.stopActive();
    }
  }

  List<FocusSession> get _filteredSessions {
    final result = widget.focusStore.sessions.where((session) {
      if (session.isActive) return false;
      if (_scope == _FocusScope.orders && session.isFreeFocus) return false;
      if (_scope == _FocusScope.free && !session.isFreeFocus) return false;
      if (_filterStart != null && session.startedAt.isBefore(_filterStart!)) {
        return false;
      }
      if (_filterEnd != null && session.startedAt.isAfter(_filterEnd!)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) {
      final comparison = switch (_sessionSortField) {
        _FocusSessionSortField.startedAt =>
          a.startedAt.compareTo(b.startedAt),
        _FocusSessionSortField.duration =>
          a.durationAt().compareTo(b.durationAt()),
      };
      if (comparison != 0) {
        return _sessionSortDescending ? -comparison : comparison;
      }
      return b.startedAt.compareTo(a.startedAt);
    });
    return result;
  }

  List<_FocusGroup> get _groups {
    final map = <String, List<FocusSession>>{};
    for (final session in _filteredSessions) {
      final key = session.orderId ?? '__free__';
      map.putIfAbsent(key, () => <FocusSession>[]).add(session);
    }

    final groups = <_FocusGroup>[
      for (final entry in map.entries)
        _FocusGroup(
          orderId: entry.key == '__free__' ? null : entry.key,
          label: entry.key == '__free__'
              ? '自由专注'
              : (_orderById(entry.key)?.title ??
                  entry.value.first.orderTitleSnapshot ??
                  '已删除排单'),
          sessions: entry.value,
        ),
    ];
    groups.sort((a, b) {
      final comparison = switch (_groupSortField) {
        _FocusGroupSortField.totalDuration =>
          a.totalDuration.compareTo(b.totalDuration),
        _FocusGroupSortField.sessionCount =>
          a.sessions.length.compareTo(b.sessions.length),
        _FocusGroupSortField.recentFocus =>
          a.mostRecentStartedAt.compareTo(b.mostRecentStartedAt),
      };
      if (comparison != 0) {
        return _groupSortDescending ? -comparison : comparison;
      }
      return a.label.compareTo(b.label);
    });
    return groups;
  }

  Future<void> _confirmOpenOrder(String orderId, String fallbackTitle) async {
    if (!widget.orderStore.contains(orderId)) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('无法跳转'),
          content: const Text('排单记录已删除，无法跳转。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final order = widget.orderStore.byId(orderId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('打开排单详情？'),
        content: Text(
          '将跳转到“${order.title.isEmpty ? fallbackTitle : order.title}”'
          '${order.isArchived ? '（已归档）' : ''}的详情页。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onOpenOrder(orderId);
    }
  }

  Future<void> _showCleanupDialog() async {
    DateTime? start;
    DateTime? end;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final count = widget.focusStore.countStartedInRange(
            start: start,
            end: end,
          );
          final rangeComplete = start != null && end != null;
          final rangeValid =
              rangeComplete && !start!.isAfter(end!);
          final canClean = rangeValid;
          return AlertDialog(
            title: const Text('清理专注记录'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '请选择完整的“从 / 到”时间范围；按专注开始时间匹配，正在进行的专注不会被清理。',
                  ),
                  const SizedBox(height: 12),
                  _RangeButton(
                    label: '从',
                    value: start,
                    onTap: () async {
                      final picked = await _pickDateTime(start);
                      if (picked != null) {
                        setDialogState(() => start = picked);
                      }
                    },
                    onClear: start == null
                        ? null
                        : () => setDialogState(() => start = null),
                  ),
                  const SizedBox(height: 8),
                  _RangeButton(
                    label: '到',
                    value: end,
                    onTap: () async {
                      final picked = await _pickDateTime(end);
                      if (picked != null) {
                        setDialogState(() => end = picked);
                      }
                    },
                    onClear: end == null
                        ? null
                        : () => setDialogState(() => end = null),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    canClean
                        ? '当前范围匹配 $count 条历史记录。'
                        : rangeComplete
                            ? '起始时间不能晚于结束时间。'
                            : '时间范围未选完整，不能清理。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton.tonal(
                onPressed: !canClean || count == 0
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: dialogContext,
                          builder: (confirmContext) => AlertDialog(
                            title: const Text('确认清理？'),
                            content: Text('将永久删除 $count 条专注历史记录。'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(false),
                                child: const Text('返回'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(true),
                                child: const Text('确认删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        widget.focusStore.removeStartedInRange(
                          start: start,
                          end: end,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: const Text('清理记录'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.focusStore,
        widget.orderStore,
      ]),
      builder: (context, _) => Column(
        children: [
          _buildTimerCard(context),
          const SizedBox(height: 14),
          _buildHistory(context),
        ],
      ),
    );
  }

  Widget _buildTimerCard(BuildContext context) {
    final active = widget.focusStore.activeSession;
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text(
                  '专注计时',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (active == null) ...[
              Text(
                '当前未计时',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.desktopSettings == null
                    ? '开始时可以选择一个排单，或选择自由专注。'
                    : '有“当前在画订单”时会在开始瞬间锁定该排单；没有时再选择排单或自由专注。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _startFocus,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始专注'),
              ),
            ] else ...[
              Text(
                _formatDuration(active.durationAt()),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _targetLabel(active),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '开始于 ${_formatDateTime(active.startedAt)}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _stopFocus,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('结束专注'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sessions = _filteredSessions;
    final groups = _groups;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '专注列表',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showCleanupDialog,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清理'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<_FocusListMode>(
              segments: const [
                ButtonSegment(
                  value: _FocusListMode.sessions,
                  label: Text('单次专注'),
                ),
                ButtonSegment(
                  value: _FocusListMode.orders,
                  label: Text('按订单合并'),
                ),
              ],
              selected: <_FocusListMode>{_mode},
              onSelectionChanged: (value) {
                if (value.isEmpty) return;
                setState(() => _mode = value.first);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<_FocusScope>(
                  value: _scope,
                  items: const [
                    DropdownMenuItem(
                      value: _FocusScope.all,
                      child: Text('全部专注'),
                    ),
                    DropdownMenuItem(
                      value: _FocusScope.orders,
                      child: Text('排单专注'),
                    ),
                    DropdownMenuItem(
                      value: _FocusScope.free,
                      child: Text('自由专注'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _scope = value);
                  },
                ),
                if (_mode == _FocusListMode.sessions) ...[
                  DropdownButton<_FocusSessionSortField>(
                    value: _sessionSortField,
                    items: const [
                      DropdownMenuItem(
                        value: _FocusSessionSortField.startedAt,
                        child: Text('按开始时间'),
                      ),
                      DropdownMenuItem(
                        value: _FocusSessionSortField.duration,
                        child: Text('按时长'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sessionSortField = value);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: _sessionSortDescending ? '当前：从大到小' : '当前：从小到大',
                    onPressed: () => setState(
                      () => _sessionSortDescending = !_sessionSortDescending,
                    ),
                    icon: Icon(
                      _sessionSortDescending
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                  ),
                ] else ...[
                  DropdownButton<_FocusGroupSortField>(
                    value: _groupSortField,
                    items: const [
                      DropdownMenuItem(
                        value: _FocusGroupSortField.totalDuration,
                        child: Text('按累计时长'),
                      ),
                      DropdownMenuItem(
                        value: _FocusGroupSortField.sessionCount,
                        child: Text('按专注次数'),
                      ),
                      DropdownMenuItem(
                        value: _FocusGroupSortField.recentFocus,
                        child: Text('按最近专注时间'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _groupSortField = value);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: _groupSortDescending ? '当前：从大到小' : '当前：从小到大',
                    onPressed: () => setState(
                      () => _groupSortDescending = !_groupSortDescending,
                    ),
                    icon: Icon(
                      _groupSortDescending
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '按专注开始时间筛选；不选择范围时显示全部记录。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RangeButton(
                  label: '从',
                  value: _filterStart,
                  onTap: () async {
                    final picked = await _pickDateTime(_filterStart);
                    if (picked != null) setState(() => _filterStart = picked);
                  },
                  onClear: _filterStart == null
                      ? null
                      : () => setState(() => _filterStart = null),
                ),
                _RangeButton(
                  label: '到',
                  value: _filterEnd,
                  onTap: () async {
                    final picked = await _pickDateTime(_filterEnd);
                    if (picked != null) setState(() => _filterEnd = picked);
                  },
                  onClear: _filterEnd == null
                      ? null
                      : () => setState(() => _filterEnd = null),
                ),
                if (_filterStart != null || _filterEnd != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _filterStart = null;
                      _filterEnd = null;
                    }),
                    child: const Text('显示全部时间'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if ((_mode == _FocusListMode.sessions && sessions.isEmpty) ||
                (_mode == _FocusListMode.orders && groups.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    '当前条件下没有专注记录。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              )
            else if (_mode == _FocusListMode.sessions)
              for (final session in sessions)
                _SessionTile(
                  session: session,
                  targetLabel: _targetLabel(session),
                  timeText: session.orderId == null
                      ? '开始 ${_formatDateTime(session.startedAt)}\n'
                          '结束 ${_formatDateTime(session.endedAt!)} · '
                          '${_formatDuration(session.durationAt())}'
                      : '排单 ID：${session.orderId}\n'
                          '开始 ${_formatDateTime(session.startedAt)}\n'
                          '结束 ${_formatDateTime(session.endedAt!)} · '
                          '${_formatDuration(session.durationAt())}',
                  onTap: session.orderId == null
                      ? null
                      : () => _confirmOpenOrder(
                            session.orderId!,
                            session.orderTitleSnapshot ?? '排单',
                          ),
                )
            else
              for (final group in groups)
                _GroupTile(
                  group: group,
                  durationText: _formatDuration(group.totalDuration),
                  recentText: _formatDateTime(group.mostRecentStartedAt),
                  onTap: group.orderId == null
                      ? null
                      : () => _confirmOpenOrder(group.orderId!, group.label),
                ),
          ],
        ),
      ),
    );
  }
}

class _FocusTarget {
  const _FocusTarget([this.order]);
  final QueueOrder? order;
}

class _FocusGroup {
  const _FocusGroup({
    required this.orderId,
    required this.label,
    required this.sessions,
  });

  final String? orderId;
  final String label;
  final List<FocusSession> sessions;

  Duration get totalDuration => sessions.fold(
        Duration.zero,
        (total, session) => total + session.durationAt(),
      );

  DateTime get mostRecentStartedAt => sessions
      .map((session) => session.startedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    String format(DateTime input) {
      final local = input.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${local.year}/${two(local.month)}/${two(local.day)} '
          '${two(local.hour)}:${two(local.minute)}';
    }

    return InputChip(
      avatar: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text('$label：${value == null ? '不限' : format(value!)}'),
      onPressed: onTap,
      onDeleted: onClear,
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.targetLabel,
    required this.timeText,
    required this.onTap,
  });

  final FocusSession session;
  final String targetLabel;
  final String timeText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          session.isFreeFocus
              ? Icons.self_improvement_rounded
              : Icons.draw_outlined,
        ),
        title: Text(targetLabel),
        subtitle: Text(timeText, maxLines: session.orderId == null ? 2 : 3),
        trailing: onTap == null
            ? null
            : const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.durationText,
    required this.recentText,
    required this.onTap,
  });

  final _FocusGroup group;
  final String durationText;
  final String recentText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          group.orderId == null
              ? Icons.self_improvement_rounded
              : Icons.draw_outlined,
        ),
        title: Text(group.label),
        subtitle: Text(
          group.orderId == null
              ? '${group.sessions.length} 次专注 · 最近 $recentText'
              : '排单 ID：${group.orderId}\n'
                  '${group.sessions.length} 次专注 · 最近 $recentText',
          maxLines: group.orderId == null ? 1 : 2,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              durationText,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, size: 18),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
