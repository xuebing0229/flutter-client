import 'dart:async';

import 'package:flutter/material.dart';

import '../../orders/data/node_presets.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/presentation/order_detail_page.dart';
import '../../orders/state/order_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../../core/features/app_feature_store.dart';
import '../domain/focus_session.dart';
import '../state/focus_store.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({
    required this.accountId,
    required this.store,
    required this.orderStore,
    required this.nodePresetStore,
    required this.featureStore,
    super.key,
  });

  final String accountId;
  final FocusStore store;
  final OrderStore orderStore;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  static const _freeFocusValue = '__free_focus__';

  Timer? _ticker;
  late String _selectedTarget;

  @override
  void initState() {
    super.initState();
    _selectedTarget = _initialTarget();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.store.activeSession != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _initialTarget() {
    final active = widget.store.activeSession;
    if (active != null) return active.orderId ?? _freeFocusValue;

    for (final order in widget.orderStore.orders) {
      if (order.isPinned && !order.isArchived && !order.isCompleted) {
        return order.id;
      }
    }
    return _freeFocusValue;
  }

  List<QueueOrder> _availableOrders(FocusSession? active) {
    final result = <QueueOrder>[
      for (final order in widget.orderStore.orders)
        if (!order.isArchived && !order.isCompleted) order,
    ];

    final activeId = active?.orderId;
    if (activeId != null &&
        widget.orderStore.contains(activeId) &&
        !result.any((order) => order.id == activeId)) {
      result.add(widget.orderStore.byId(activeId));
    }
    return result;
  }

  String _effectiveTarget(
    FocusSession? active,
    List<QueueOrder> availableOrders,
  ) {
    if (active != null) return active.orderId ?? _freeFocusValue;
    if (_selectedTarget == _freeFocusValue) return _freeFocusValue;
    if (availableOrders.any((order) => order.id == _selectedTarget)) {
      return _selectedTarget;
    }
    return _freeFocusValue;
  }

  Future<void> _changeTarget(
    String next,
    FocusSession? active,
  ) async {
    if (active != null) {
      final lockedName = active.displayTitle;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('这次专注已经锁定'),
          content: Text(
            '当前计时锁定在“$lockedName”。如果要换一个排单，建议先结束这次专注，再重新开始一次计时。',
          ),
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

    if (_selectedTarget == next) return;
    setState(() => _selectedTarget = next);
  }

  void _startFocus(
    String target,
    List<QueueOrder> availableOrders,
  ) {
    if (widget.store.activeSession != null) return;

    if (target == _freeFocusValue) {
      widget.store.start();
      setState(() => _selectedTarget = _freeFocusValue);
      return;
    }

    QueueOrder? order;
    for (final item in availableOrders) {
      if (item.id == target) {
        order = item;
        break;
      }
    }
    if (order == null || order.isArchived || order.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这个排单当前不能开始专注，请重新选择。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    widget.store.start(
      orderId: order.id,
      orderTitleSnapshot: order.title,
    );
    setState(() => _selectedTarget = order!.id);
  }

  Future<void> _stopFocus(FocusSession active) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('结束这次专注？'),
        content: Text(
          '“${active.displayTitle}”已专注 ${_formatDuration(active.elapsedAt(DateTime.now()))}。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续专注'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.stop();
    setState(() {});
  }

  Future<void> _openLinkedOrder(FocusSession session) async {
    final orderId = session.orderId;
    if (orderId == null) return;

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

    final current = widget.orderStore.byId(orderId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('前往排单？'),
        content: Text('要打开“${current.title}”的排单详情吗？'),
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
    if (confirmed != true || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          accountId: widget.accountId,
          store: widget.orderStore,
          orderId: orderId,
          nodePresetStore: widget.nodePresetStore,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 999999999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '专注',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.store,
          widget.orderStore,
        ]),
        builder: (context, _) {
          final active = widget.store.activeSession;
          final orders = _availableOrders(active);
          final target = _effectiveTarget(active, orders);
          final history = <FocusSession>[
            for (final session in widget.store.sessions)
              if (!session.isActive) session,
          ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

          final targetItems = <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: _freeFocusValue,
              child: Text('自由专注'),
            ),
            for (final order in orders)
              DropdownMenuItem<String>(
                value: order.id,
                child: Text(
                  active?.orderId == order.id &&
                          (order.isArchived || order.isCompleted)
                      ? '${order.title}（当前锁定）'
                      : order.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ];

          if (active?.orderId != null &&
              !targetItems.any((item) => item.value == active!.orderId)) {
            targetItems.add(
              DropdownMenuItem<String>(
                value: active!.orderId,
                child: Text(
                  '${active.orderTitleSnapshot ?? '排单'}（当前锁定）',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }

          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 12,
              right: 16,
            ),
            children: [
              _FocusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      active == null ? '开始一次专注' : '正在专注',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: target,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '本次专注',
                        border: OutlineInputBorder(),
                      ),
                      items: targetItems,
                      onChanged: (value) {
                        if (value == null) return;
                        unawaited(_changeTarget(value, active));
                      },
                    ),
                    const SizedBox(height: 18),
                    if (active != null) ...[
                      Text(
                        _formatDuration(active.elapsedAt(DateTime.now())),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        active.displayTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => unawaited(_stopFocus(active)),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('结束专注'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: () => _startFocus(target, orders),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('开始专注'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '专注记录',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                _FocusCard(
                  child: Text(
                    '还没有专注记录。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                _FocusCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < history.length; index++) ...[
                        _FocusHistoryTile(
                          session: history[index],
                          duration: _formatDuration(
                            history[index].elapsedAt(DateTime.now()),
                          ),
                          startedAt: _formatDateTime(history[index].startedAt),
                          onTap: history[index].orderId == null
                              ? null
                              : () => unawaited(
                                    _openLinkedOrder(history[index]),
                                  ),
                        ),
                        if (index != history.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _FocusHistoryTile extends StatelessWidget {
  const _FocusHistoryTile({
    required this.session,
    required this.duration,
    required this.startedAt,
    required this.onTap,
  });

  final FocusSession session;
  final String duration;
  final String startedAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.timer_outlined),
      title: Text(
        session.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$startedAt · $duration'),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }
}
