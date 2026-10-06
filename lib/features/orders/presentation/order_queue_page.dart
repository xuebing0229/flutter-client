import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/sync/sync_ui_coordinator.dart';
import '../../shared/presentation/collection_card_grid.dart';
import '../../shared/presentation/collection_widgets.dart';
import '../data/node_presets.dart';
import '../domain/queue_order.dart';
import '../state/order_store.dart';
import 'order_detail_page.dart';
import 'order_summary_card.dart';

enum _TerminationSettlementMode { node, customRefund }

enum _BulkOrderArchiveMode { successful, terminatedIndividually }

enum _OrderSortMode {
  defaultOrder('默认排序'),
  income('按收入金额'),
  deadline('按截稿时间');

  const _OrderSortMode(this.label);
  final String label;
}

class OrderQueuePage extends StatefulWidget {
  const OrderQueuePage({
    required this.accountId,
    required this.store,
    required this.nodePresetStore,
    required this.featureStore,
    required this.syncCoordinator,
    required this.cardView,
    required this.onCardViewChanged,
    required this.sortModeName,
    required this.onSortModeChanged,
    super.key,
  });

  final String accountId;
  final OrderStore store;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;
  final SyncUiCoordinator syncCoordinator;
  final bool cardView;
  final ValueChanged<bool> onCardViewChanged;
  final String sortModeName;
  final ValueChanged<String> onSortModeChanged;

  @override
  State<OrderQueuePage> createState() => _OrderQueuePageState();
}

class _OrderQueuePageState extends State<OrderQueuePage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _searchField = 'all';

  _OrderSortMode get _sortMode => _OrderSortMode.values.firstWhere(
    (mode) => mode.name == widget.sortModeName,
    orElse: () => _OrderSortMode.defaultOrder,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QueueOrder> _visibleOrders() {
    final query = widget.featureStore.search ? _query.trim().toLowerCase() : '';

    final effectiveSearchField =
        _searchField == 'client' && !widget.featureStore.clientInfo
        ? 'all'
        : _searchField;

    final filtered = widget.store.orders.where((order) {
      if (order.isArchived) {
        return false;
      }

      if (query.isEmpty) return true;

      final currentNode = order.currentNode;
      final titleMatches = order.title.toLowerCase().contains(query);
      final clientMatches =
          widget.featureStore.clientInfo &&
          order.clientName.toLowerCase().contains(query);
      final platformMatches = order.platform.label.toLowerCase().contains(
        query,
      );
      final nodeMatches = currentNode.name.toLowerCase().contains(query);

      return switch (effectiveSearchField) {
        'title' => titleMatches,
        'client' => clientMatches,
        'platform' => platformMatches,
        'node' => nodeMatches,
        _ => titleMatches || clientMatches || platformMatches || nodeMatches,
      };
    }).toList();

    final pinned = filtered.where((order) => order.isPinned).toList();
    final regular = filtered.where((order) => !order.isPinned).toList();

    _sortGroup(pinned);
    _sortGroup(regular);

    return [...pinned, ...regular];
  }

  void _sortGroup(List<QueueOrder> orders) {
    if (!widget.featureStore.sorting) return;
    switch (_sortMode) {
      case _OrderSortMode.defaultOrder:
        return;
      case _OrderSortMode.income:
        orders.sort((left, right) {
          final byPrice = right.realIncome.compareTo(left.realIncome);
          if (byPrice != 0) return byPrice;
          return _compareDeadline(left.deadline, right.deadline);
        });
      case _OrderSortMode.deadline:
        orders.sort((left, right) {
          final byDeadline = _compareDeadline(left.deadline, right.deadline);
          if (byDeadline != 0) return byDeadline;
          return right.realIncome.compareTo(left.realIncome);
        });
    }
  }

  void _openOrder(QueueOrder order) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          accountId: widget.accountId,
          store: widget.store,
          orderId: order.id,
          nodePresetStore: widget.nodePresetStore,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  Future<void> _confirmNode(QueueOrder order) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (order.isCompleted || order.nodePresetSnapshot.nodes.isEmpty) return;

    final nodes = order.nodePresetSnapshot.nodes;
    final currentName = order.currentNode.name;
    String? nextNodeName;
    var completesOrder = false;

    if (order.currentNodeId == notStartedNodeId) {
      nextNodeName = nodes.first.name;
    } else {
      final currentIndex = nodes.indexWhere(
        (node) => node.id == order.currentNodeId,
      );

      if (currentIndex < 0) {
        nextNodeName = nodes.first.name;
      } else if (currentIndex < nodes.length - 1) {
        nextNodeName = nodes[currentIndex + 1].name;
      } else {
        completesOrder = true;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认节点'),
          content: Text(
            completesOrder
                ? '将“${order.title}”标记为已交稿？\n\n'
                      '标记后仍保留在排单中，需手动归档后才正式结算。'
                : '将“${order.title}”从“$currentName”推进到“$nextNodeName”？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    widget.store.advanceOrder(order.id);

    if (!mounted) return;
    final updated = widget.store.byId(order.id);

    if (updated.isCompleted) {
      final archiveNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.inventory_2_outlined),
          title: const Text('提示'),
          content: const Text('成稿归档后计入收入统计。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后归档'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('现在归档'),
            ),
          ],
        ),
      );

      if (archiveNow == true && mounted) {
        await _showArchiveOptions(updated);
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已更新到「${updated.currentNode.name}」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showQuickActions(QueueOrder order) {
    return showCollectionQuickActions(
      context: context,
      title: order.title,
      isPinned: order.isPinned,
      onTogglePinned: () {
        widget.store.setPinned(order.id, !order.isPinned);
      },
      onArchive: () {
        _showArchiveOptions(order);
      },
      onBulkArchive: () {
        _bulkArchive(order);
      },
      onDelete: () {
        _confirmDelete(order);
      },
      onBulkDelete: () {
        _bulkDelete(order);
      },
    );
  }

  Future<Set<String>?> _pickOrdersForBulk({
    required QueueOrder initial,
    required String title,
    required String confirmLabel,
    bool destructive = false,
  }) {
    final orders = _visibleOrders();
    return showCollectionBulkPicker(
      context: context,
      title: title,
      confirmLabel: confirmLabel,
      destructive: destructive,
      initialSelection: <String>{initial.id},
      items: [
        for (final order in orders)
          CollectionBulkItem(
            id: order.id,
            title: order.title,
            subtitle: '${order.platform.label} · ${order.currentNode.name}',
          ),
      ],
    );
  }

  Future<void> _bulkDelete(QueueOrder initial) async {
    final ids = await _pickOrdersForBulk(
      initial: initial,
      title: '批量删除排单',
      confirmLabel: '继续删除',
      destructive: true,
    );
    if (!mounted || ids == null || ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除 ${ids.length} 个排单？'),
        content: const Text('删除后会从本地数据中移除，无法从归档页恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('批量删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.store.deleteOrders(ids);
    }
  }

  Future<void> _bulkArchive(QueueOrder initial) async {
    final ids = await _pickOrdersForBulk(
      initial: initial,
      title: '批量归档排单',
      confirmLabel: '选择归档方式',
    );
    if (!mounted || ids == null || ids.isEmpty) return;

    final mode = await showModalBottomSheet<_BulkOrderArchiveMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: AppLayoutSpacing.bottomSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    '批量归档 ${ids.length} 个排单',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('顺利结算'),
                  subtitle: const Text('所选排单全部按完整真实收入结算'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_BulkOrderArchiveMode.successful),
                ),
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('中止合作'),
                  subtitle: const Text('逐个排单分别选择按节点结算或自定义退款'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_BulkOrderArchiveMode.terminatedIndividually),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || mode == null) return;

    switch (mode) {
      case _BulkOrderArchiveMode.successful:
        widget.store.archiveManyAsSettled(ids);
      case _BulkOrderArchiveMode.terminatedIndividually:
        await _bulkArchiveAsTerminated(ids);
    }
  }

  Future<void> _bulkArchiveAsTerminated(Set<String> ids) async {
    final selectedOrders = _visibleOrders()
        .where((order) => ids.contains(order.id))
        .toList();

    for (var index = 0; index < selectedOrders.length; index++) {
      if (!mounted) return;

      final order = selectedOrders[index];
      final stepLabel =
          '${index + 1}/${selectedOrders.length} · ${order.title}';

      final mode = await _pickTerminationSettlementMode(title: stepLabel);
      if (!mounted || mode == null) return;

      if (mode == _TerminationSettlementMode.node) {
        final settlementNodeId = await _pickTerminationNode(
          order,
          title: stepLabel,
        );
        if (!mounted || settlementNodeId == null) return;
        widget.store.archiveAsTerminated(order.id, settlementNodeId);
      } else {
        final refundAmount = await _pickCustomRefund(order, title: stepLabel);
        if (!mounted || refundAmount == null) return;
        widget.store.archiveAsTerminatedWithCustomRefund(
          order.id,
          refundAmount,
        );
      }
    }
  }

  Future<void> _showArchiveOptions(QueueOrder order) async {
    final outcome = await showModalBottomSheet<OrderArchiveOutcome>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: AppLayoutSpacing.bottomSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    '选择归档方式',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('顺利结算'),
                  subtitle: Text(
                    '按完整真实收入 ¥${_formatMoney(order.realIncome)} 结算',
                  ),
                  onTap: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(OrderArchiveOutcome.successful);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('中止合作'),
                  subtitle: const Text('可按节点结算，也可自定义实际退款金额'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(OrderArchiveOutcome.terminated);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || outcome == null) return;

    if (outcome == OrderArchiveOutcome.successful) {
      widget.store.archiveAsSettled(order.id);
      return;
    }

    final mode = await _pickTerminationSettlementMode();
    if (!mounted || mode == null) return;

    if (mode == _TerminationSettlementMode.node) {
      final settlementNodeId = await _pickTerminationNode(order);
      if (!mounted || settlementNodeId == null) return;
      widget.store.archiveAsTerminated(order.id, settlementNodeId);
      return;
    }

    final refundAmount = await _pickCustomRefund(order);
    if (!mounted || refundAmount == null) return;
    widget.store.archiveAsTerminatedWithCustomRefund(order.id, refundAmount);
  }

  Future<_TerminationSettlementMode?> _pickTerminationSettlementMode({
    String? title,
  }) {
    return showModalBottomSheet<_TerminationSettlementMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: AppLayoutSpacing.bottomSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    title ?? '中止合作如何结算',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: title == null ? null : const Text('选择这笔排单的结算方式'),
                ),
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('按节点结算'),
                  subtitle: const Text('选择最终节点，按节点比例计算最终收入'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_TerminationSettlementMode.node),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('自定义退款'),
                  subtitle: const Text('自行输入协商后的实际退款金额'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_TerminationSettlementMode.customRefund),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<double?> _pickCustomRefund(QueueOrder order, {String? title}) async {
    final controller = TextEditingController();
    String? errorText;
    var previewRefund = 0.0;

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final finalIncome = order.realIncome - previewRefund;

            return AlertDialog(
              title: Text(title ?? '自定义退款'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '实际退款金额',
                        prefixText: '¥ ',
                        hintText: '0',
                        errorText: errorText,
                      ),
                      onChanged: (value) {
                        final parsed = double.tryParse(value.trim());
                        setDialogState(() {
                          errorText = null;
                          previewRefund = parsed == null || parsed < 0
                              ? 0
                              : parsed;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '当前真实收入 ¥ ${_formatMoney(order.realIncome)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '退款后最终收入',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '¥ ${_formatMoney(finalIncome)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
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
                FilledButton(
                  onPressed: () {
                    final raw = controller.text.trim();
                    final parsed = double.tryParse(raw);
                    if (parsed == null || parsed < 0) {
                      setDialogState(() {
                        errorText = '请输入有效的退款金额';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(parsed);
                  },
                  child: const Text('确认归档'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<String?> _pickTerminationNode(QueueOrder order, {String? title}) {
    final nodes = order.nodePresetSnapshot.nodes;
    if (nodes.isEmpty) return Future<String?>.value(null);

    final validNodeIds = <String>{for (final node in nodes) node.id};
    var selectedNodeId = validNodeIds.contains(order.currentNodeId)
        ? order.currentNodeId
        : nodes.first.id;

    NodeDefinition selectedNode() {
      return order.nodePresetSnapshot.nodeById(selectedNodeId);
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final node = selectedNode();
            final finalIncome = order.incomeAtProgress(node.progressPercent);

            return AlertDialog(
              title: Text(title ?? '中止合作'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedNodeId,
                      decoration: const InputDecoration(labelText: '最终结算节点'),
                      items: [
                        for (final item in order.nodePresetSnapshot.nodes)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              '${item.name} · ${item.progressPercent}%',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedNodeId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('最终收入', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '¥ ${_formatMoney(finalIncome)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '按 ${node.progressPercent}% 的节点比例结算',
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
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selectedNodeId),
                  child: const Text('确认归档'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatMoney(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  Future<void> _confirmDelete(QueueOrder order) async {
    final confirmed = await confirmLocalDelete(
      context: context,
      noun: '订单',
      title: order.title,
    );
    if (confirmed) {
      widget.store.deleteOrder(order.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.store,
        widget.featureStore,
        widget.syncCoordinator,
      ]),
      builder: (context, _) {
        final orders = _visibleOrders();
        final useCardView = widget.featureStore.viewSwitch && widget.cardView;

        return Column(
          children: [
            if (widget.featureStore.search)
              CollectionSearchField(
                controller: _searchController,
                query: _query,
                hintText: '搜索排单',
                filters: [
                  const SearchFilterOption(id: 'all', label: '全部'),
                  const SearchFilterOption(id: 'title', label: '图名'),
                  if (widget.featureStore.clientInfo)
                    const SearchFilterOption(id: 'client', label: '单主'),
                  const SearchFilterOption(id: 'platform', label: '平台'),
                  const SearchFilterOption(id: 'node', label: '节点'),
                ],
                selectedFilter: _searchField,
                onFilterChanged: (value) {
                  setState(() => _searchField = value);
                },
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _searchField = 'all';
                  });
                },
              ),
            if (widget.featureStore.sorting || widget.featureStore.viewSwitch)
              CollectionToolbar(
                title: '排单',
                count: orders.length,
                summaryText:
                    '待收入 ¥${_formatMoney(orders.fold<double>(0, (sum, order) => sum + order.realIncome))}',
                helpMessage: '长按卡片，可快速进行置顶、归档、删除操作',
                sortControl: widget.featureStore.sorting
                    ? PopupMenuButton<_OrderSortMode>(
                        tooltip: '选择排序方式',
                        initialValue: _sortMode,
                        onSelected: (value) {
                          widget.onSortModeChanged(value.name);
                        },
                        itemBuilder: (context) {
                          return [
                            for (final mode in _OrderSortMode.values)
                              PopupMenuItem<_OrderSortMode>(
                                value: mode,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: _sortMode == mode
                                          ? const Icon(
                                              Icons.check_rounded,
                                              size: 19,
                                            )
                                          : null,
                                    ),
                                    Expanded(child: Text(mode.label)),
                                  ],
                                ),
                              ),
                          ];
                        },
                        icon: const Icon(Icons.sort_rounded),
                      )
                    : null,
                cardView: widget.cardView,
                onToggleView: widget.featureStore.viewSwitch
                    ? () {
                        widget.onCardViewChanged(!widget.cardView);
                      }
                    : null,
              ),
            Expanded(
              child: orders.isEmpty
                  ? Center(
                      child: Text(
                        widget.featureStore.search && _query.trim().isNotEmpty
                            ? '没有找到匹配的排单'
                            : '还没有排单，点右下角「新增排单」开始记录',
                      ),
                    )
                  : useCardView
                  ? CollectionCardGrid(
                      itemCount: orders.length,
                      mobileAspectRatio: widget.featureStore.nodeProgress
                          ? 0.43
                          : 0.52,
                      desktopMinHeight: widget.featureStore.nodeProgress
                          ? 320
                          : 260,
                      desktopAspectRatio: 1.05,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return OrderSummaryCard(
                          order: order,
                          hasSyncConflict: widget
                              .syncCoordinator
                              .conflictedOrderIds
                              .contains(order.id),
                          compact: true,
                          onTap: () => _openOrder(order),
                          onLongPress: () => _showQuickActions(order),
                          showClient: widget.featureStore.clientInfo,
                          showNodeProgress: widget.featureStore.nodeProgress,
                          onConfirmNode:
                              order.isCompleted ||
                                  order.nodePresetSnapshot.nodes.isEmpty
                              ? null
                              : () => _confirmNode(order),
                          onDecreaseNodeProgress:
                              !widget.featureStore.nodeProgress ||
                                  order.isCompleted ||
                                  order.currentNodeId == notStartedNodeId
                              ? null
                              : () => widget.store.adjustCurrentNodeProgress(
                                  order.id,
                                  -10,
                                ),
                          onIncreaseNodeProgress:
                              !widget.featureStore.nodeProgress ||
                                  order.isCompleted ||
                                  order.currentNodeId == notStartedNodeId
                              ? null
                              : () => widget.store.adjustCurrentNodeProgress(
                                  order.id,
                                  10,
                                ),
                        );
                      },
                    )
                  : ListView.separated(
                      padding: AppLayoutSpacing.tabScrollPaddingWithFab(
                        left: 14,
                        top: 0,
                        right: 14,
                      ),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return OrderSummaryCard(
                          order: order,
                          hasSyncConflict: widget
                              .syncCoordinator
                              .conflictedOrderIds
                              .contains(order.id),
                          onTap: () => _openOrder(order),
                          onLongPress: () => _showQuickActions(order),
                          showClient: widget.featureStore.clientInfo,
                          showNodeProgress: widget.featureStore.nodeProgress,
                          onConfirmNode:
                              order.isCompleted ||
                                  order.nodePresetSnapshot.nodes.isEmpty
                              ? null
                              : () => _confirmNode(order),
                          onDecreaseNodeProgress:
                              !widget.featureStore.nodeProgress ||
                                  order.isCompleted ||
                                  order.currentNodeId == notStartedNodeId
                              ? null
                              : () => widget.store.adjustCurrentNodeProgress(
                                  order.id,
                                  -10,
                                ),
                          onIncreaseNodeProgress:
                              !widget.featureStore.nodeProgress ||
                                  order.isCompleted ||
                                  order.currentNodeId == notStartedNodeId
                              ? null
                              : () => widget.store.adjustCurrentNodeProgress(
                                  order.id,
                                  10,
                                ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

int _compareDeadline(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}
