import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../shared/presentation/collection_card_grid.dart';
import '../../shared/presentation/collection_widgets.dart';
import '../../orders/domain/queue_order.dart';
import '../domain/finished_product.dart';
import '../state/product_store.dart';
import 'product_detail_page.dart';
import 'product_summary_card.dart';

enum _ProductSortMode {
  defaultOrder('默认排序'),
  income('按收入金额'),
  soldCount('按售出数量');

  const _ProductSortMode(this.label);
  final String label;
}

class ProductPage extends StatefulWidget {
  const ProductPage({
    required this.accountId,
    required this.store,
    required this.featureStore,
    required this.syncCoordinator,
    required this.cardView,
    required this.onCardViewChanged,
    required this.sortModeName,
    required this.onSortModeChanged,
    super.key,
  });

  final String accountId;
  final ProductStore store;
  final AppFeatureStore featureStore;
  final SyncCoordinator syncCoordinator;
  final bool cardView;
  final ValueChanged<bool> onCardViewChanged;
  final String sortModeName;
  final ValueChanged<String> onSortModeChanged;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _searchField = 'all';

  _ProductSortMode get _sortMode => _ProductSortMode.values.firstWhere(
        (mode) => mode.name == widget.sortModeName,
        orElse: () => _ProductSortMode.defaultOrder,
      );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FinishedProduct> _visibleProducts() {
    final query = widget.featureStore.search
        ? _query.trim().toLowerCase()
        : '';

    final filtered = widget.store.products.where((product) {
      if (product.isArchived) return false;
      if (query.isEmpty) return true;

      final titleMatches = product.title.toLowerCase().contains(query);
      final platformMatches =
          product.platform.label.toLowerCase().contains(query);
      final saleTypeMatches =
          product.saleType.label.toLowerCase().contains(query);
      final statusMatches =
          product.saleStatusLabel.toLowerCase().contains(query);

      return switch (_searchField) {
        'title' => titleMatches,
        'platform' => platformMatches,
        'saleType' => saleTypeMatches,
        'status' => statusMatches,
        _ => titleMatches || platformMatches || saleTypeMatches || statusMatches,
      };
    }).toList();

    final pinned = filtered.where((product) => product.isPinned).toList();
    final regular = filtered.where((product) => !product.isPinned).toList();

    _sortGroup(pinned);
    _sortGroup(regular);

    return [...pinned, ...regular];
  }

  void _sortGroup(List<FinishedProduct> products) {
    if (!widget.featureStore.sorting) return;
    switch (_sortMode) {
      case _ProductSortMode.defaultOrder:
        return;
      case _ProductSortMode.income:
        products.sort((left, right) {
          final byIncome = right.realIncome.compareTo(left.realIncome);
          if (byIncome != 0) return byIncome;
          return right.soldCount.compareTo(left.soldCount);
        });
      case _ProductSortMode.soldCount:
        products.sort((left, right) {
          final byCount = right.soldCount.compareTo(left.soldCount);
          if (byCount != 0) return byCount;
          return right.realIncome.compareTo(left.realIncome);
        });
    }
  }

  void _openProduct(FinishedProduct product) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(
          accountId: widget.accountId,
          store: widget.store,
          productId: product.id,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  Future<void> _showQuickActions(FinishedProduct product) {
    return showCollectionQuickActions(
      context: context,
      title: product.title,
      isPinned: product.isPinned,
      onTogglePinned: () {
        widget.store.setPinned(product.id, !product.isPinned);
      },
      onArchive: () {
        widget.store.setArchived(product.id, true);
      },
      onBulkArchive: () {
        _bulkArchive(product);
      },
      onDelete: () {
        _confirmDelete(product);
      },
      onBulkDelete: () {
        _bulkDelete(product);
      },
    );
  }

  Future<Set<String>?> _pickProductsForBulk({
    required FinishedProduct initial,
    required String title,
    required String confirmLabel,
    bool destructive = false,
  }) {
    final products = _visibleProducts();
    return showCollectionBulkPicker(
      context: context,
      title: title,
      confirmLabel: confirmLabel,
      destructive: destructive,
      initialSelection: <String>{initial.id},
      items: [
        for (final product in products)
          CollectionBulkItem(
            id: product.id,
            title: product.title,
            subtitle:
                '${product.platform.label} · ${product.saleType.label}',
          ),
      ],
    );
  }

  Future<void> _bulkArchive(FinishedProduct initial) async {
    final ids = await _pickProductsForBulk(
      initial: initial,
      title: '批量归档成品',
      confirmLabel: '批量归档',
    );
    if (!mounted || ids == null || ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '归档 ${ids.length} 个成品？',
        ),
        content: const Text('归档后可以在归档页中查看和恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('批量归档'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.store.setArchivedMany(ids, true);
    }
  }

  Future<void> _bulkDelete(FinishedProduct initial) async {
    final ids = await _pickProductsForBulk(
      initial: initial,
      title: '批量删除成品',
      confirmLabel: '继续删除',
      destructive: true,
    );
    if (!mounted || ids == null || ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '删除 ${ids.length} 个成品？',
        ),
        content: const Text('删除后会从本地数据中移除，无法从归档页恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(dialogContext).colorScheme.error,
              foregroundColor:
                  Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('批量删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Removing a committed product removes its sync metadata but must not
      // delete shared image binaries while other bound devices may be offline.
      widget.store.deleteProducts(ids);
    }
  }

  Future<void> _confirmSale(FinishedProduct product) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final isMultiple = product.saleType == ProductSaleType.multiple;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认售出'),
          content: Text(
            isMultiple
                ? '确认“${product.title}”新增 1 次售出？\n\n'
                    '售出数量将从 ${product.soldCount} 次变为 ${product.soldCount + 1} 次，'
                    '并记录到本次售出时间对应的日程。'
                : '确认将“${product.title}”标记为已售出？\n\n'
                    '确认后会记录本次售出时间，并显示在日程中。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认售出'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    widget.store.markSold(product.id);

    if (!mounted) return;
    final updated = widget.store.byId(product.id);
    final message = updated.saleType == ProductSaleType.multiple
        ? '已记录第 ${updated.soldCount} 次售出'
        : '已标记为售出';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(FinishedProduct product) async {
    final confirmed = await confirmLocalDelete(
      context: context,
      noun: '成品',
      title: product.title,
    );
    if (confirmed) {
      // Keep committed binaries until an acknowledgement-aware asset GC can
      // prove no offline device still references them.
      widget.store.deleteProduct(product.id);
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
        final products = _visibleProducts();
        final useCardView =
            widget.featureStore.viewSwitch && widget.cardView;

        return Column(
          children: [
            if (widget.featureStore.search)
              CollectionSearchField(
                controller: _searchController,
                query: _query,
                hintText: '搜索图名、平台、售卖方式或状态',
                filters: const [
                  SearchFilterOption(id: 'all', label: '全部'),
                  SearchFilterOption(id: 'title', label: '图名'),
                  SearchFilterOption(id: 'platform', label: '平台'),
                  SearchFilterOption(id: 'saleType', label: '售卖方式'),
                  SearchFilterOption(id: 'status', label: '状态'),
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
            if (widget.featureStore.sorting ||
                widget.featureStore.viewSwitch)
              CollectionToolbar(
              title: '成品',
              count: products.length,
              helpMessage: '长按卡片，可快速进行置顶、归档、删除操作',
              sortControl: widget.featureStore.sorting
                  ? PopupMenuButton<_ProductSortMode>(
                tooltip: '选择排序方式',
                initialValue: _sortMode,
                onSelected: (value) {
                  widget.onSortModeChanged(value.name);
                },
                itemBuilder: (context) {
                  return [
                    for (final mode in _ProductSortMode.values)
                      PopupMenuItem<_ProductSortMode>(
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
              child: products.isEmpty
                  ? Center(
                      child: Text(
                        widget.featureStore.search && _query.trim().isNotEmpty
                            ? '没有找到匹配的成品'
                            : '还没有成品，点右下角「新增成品」开始记录',
                      ),
                    )
                  : useCardView
                      ? CollectionCardGrid(
                          itemCount: products.length,
                          mobileAspectRatio: 0.70,
                          desktopMinHeight: 260,
                          desktopAspectRatio: 1.15,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return ProductSummaryCard(
                              product: product,
                              hasSyncConflict: widget.syncCoordinator
                                  .conflictedProductIds
                                  .contains(product.id),
                              compact: true,
                              onTap: () => _openProduct(product),
                              onLongPress: () =>
                                  _showQuickActions(product),
                              onMarkSold:
                                  product.saleType == ProductSaleType.single &&
                                          product.isSold
                                      ? null
                                      : () => _confirmSale(product),
                            );
                          },
                        )
                      : ListView.separated(
                          padding:
                              AppLayoutSpacing.tabScrollPaddingWithFab(
                            left: 14,
                            top: 0,
                            right: 14,
                          ),
                          itemCount: products.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return ProductSummaryCard(
                              product: product,
                              hasSyncConflict: widget.syncCoordinator.conflicts
                                  .any((item) =>
                                      item.kind.name == 'product' &&
                                      item.recordId == product.id),
                              onTap: () => _openProduct(product),
                              onLongPress: () =>
                                  _showQuickActions(product),
                              onMarkSold:
                                  product.saleType == ProductSaleType.single &&
                                          product.isSold
                                      ? null
                                      : () => _confirmSale(product),
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
