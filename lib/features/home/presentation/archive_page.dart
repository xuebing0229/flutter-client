import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/presentation/order_detail_page.dart';
import '../../orders/presentation/order_summary_card.dart';
import '../../orders/state/order_store.dart';
import '../../products/domain/finished_product.dart';
import '../../products/presentation/product_detail_page.dart';
import '../../products/presentation/product_summary_card.dart';
import '../../products/state/product_store.dart';
import '../../shared/presentation/layout_spacing.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({
    required this.accountId,
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.featureStore,
    required this.syncCoordinator,
    super.key,
  });

  final String accountId;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;
  final SyncCoordinator syncCoordinator;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  bool _cleaning = false;

  void _openOrder(BuildContext context, String orderId) {
    Navigator.of(context).push(
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

  void _openProduct(BuildContext context, String productId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(
          accountId: widget.accountId,
          store: widget.productStore,
          productId: productId,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  String _orderArchiveSubtitle(QueueOrder order) {
    final outcome = order.archiveOutcome;
    if (outcome == OrderArchiveOutcome.terminated) {
      final refund = order.customRefundAmount;
      if (refund != null) {
        return '中止合作 · 自定义退款 ¥${_money(refund)}'
            ' · 最终收入 ¥${_money(order.settlementIncome)}\n'
            '关闭后恢复到正常订单列表';
      }

      final node = order.settlementNode;
      final nodeText = node == null
          ? ''
          : ' · ${node.name} ${node.progressPercent}%';
      return '中止合作$nodeText · 最终收入 ¥${_money(order.settlementIncome)}\n'
          '关闭后恢复到正常订单列表';
    }

    if (outcome == OrderArchiveOutcome.successful) {
      return '顺利结算 · 最终收入 ¥${_money(order.settlementIncome)}\n'
          '关闭后恢复到正常订单列表';
    }

    return '关闭后恢复到正常订单列表';
  }

  String _money(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  DateTime? _orderArchiveTime(QueueOrder order) {
    return order.settledAt ?? order.completedAt;
  }

  bool _insideRange(DateTime value, DateTimeRange range) {
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final endExclusive = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));
    return !value.isBefore(start) && value.isBefore(endExclusive);
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  Future<void> _cleanupArchivedRange() async {
    if (_cleaning) return;

    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: DateTime(now.year - 1, now.month, now.day),
        end: now,
      ),
      helpText: '选择要永久删除的归档时间',
      saveText: '下一步',
      cancelText: '取消',
      confirmText: '确定',
      fieldStartHintText: '开始日期',
      fieldEndHintText: '结束日期',
    );
    if (range == null || !mounted) return;

    final orders = <QueueOrder>[
      for (final order in widget.orderStore.orders)
        if (order.isArchived &&
            _orderArchiveTime(order) != null &&
            _insideRange(_orderArchiveTime(order)!, range))
          order,
    ];
    final products = <FinishedProduct>[
      for (final product in widget.productStore.products)
        if (product.isArchived &&
            product.archivedAt != null &&
            _insideRange(product.archivedAt!, range))
          product,
    ];
    final undatedLegacyProducts = widget.productStore.products
        .where((product) => product.isArchived && product.archivedAt == null)
        .length;

    final images = <OrderReferenceImage>[
      for (final order in orders) ...order.referenceImages,
      for (final product in products) ...product.referenceImages,
    ];
    final imageBytes = images.fold<int>(
      0,
      (sum, image) => sum + image.sizeBytes,
    );

    if (orders.isEmpty && products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            undatedLegacyProducts == 0
                ? '这个时间范围内没有可清理的归档内容。'
                : '这个时间范围内没有带归档日期的内容；'
                    '另有 $undatedLegacyProducts 个旧版成品没有归档日期，未自动删除。',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('永久删除这段时间的归档？'),
          content: Text(
            '归档时间：${_formatDate(range.start)} ～ '
            '${_formatDate(range.end)}\n\n'
            '排单：${orders.length} 个\n'
            '成品：${products.length} 个\n'
            '参考图：${images.length} 张'
            '${imageBytes > 0 ? '（约 ${_formatBytes(imageBytes)}）' : ''}'
            '${undatedLegacyProducts > 0 ? '\n\n有 $undatedLegacyProducts 个旧版成品没有归档日期，'
                '本次不会删除。' : ''}'
            '\n\n删除后无法从归档恢复，相关历史收入、日程记录和参考图关联会一起移除，'
            '并同步到其他设备。参考图原文件不会立即删除：只有全部绑定设备确认'
            '最新数据、经过至少 30 天保护期后才会自动清理，否则继续占用空间。'
            '如需长期留存，建议先导出完整备份。',
          ),
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
              child: const Text('永久删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cleaning = true);
    String? syncWarning;
    try {
      // The order/product references are removed from the shared metadata.
      // Do not remove their files yet: an offline Syncthing peer can still
      // have a live reference and might reintroduce it on reconnection.
      widget.orderStore.deleteOrders(orders.map((order) => order.id));
      widget.productStore.deleteProducts(
        products.map((product) => product.id),
      );

      try {
        await widget.syncCoordinator.flushNow();
      } catch (_) {
        syncWarning = '本机已删除，但这次同步没有立即完成，之后联网会继续同步删除记录。';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncWarning ??
                '已永久删除 ${orders.length} 个排单、${products.length} 个成品'
                    '${images.isEmpty ? '' : '及 ${images.length} 条参考图关联'}。',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '归档',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '按时间清理归档',
            onPressed: _cleaning ? null : _cleanupArchivedRange,
            icon: _cleaning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.orderStore,
          widget.productStore,
          widget.featureStore,
        ]),
        builder: (context, _) {
          final orders = widget.orderStore.orders
              .where((order) => order.isArchived)
              .toList();
          final products = widget.featureStore.products
              ? widget.productStore.products
                  .where((product) => product.isArchived)
                  .toList()
              : const <FinishedProduct>[];

          if (orders.isEmpty && products.isEmpty) {
            return ListView(
              padding: AppLayoutSpacing.pageScrollPadding(
                context,
                left: 14,
                top: 10,
                right: 14,
              ),
              children: [
                _CleanupCard(
                  busy: _cleaning,
                  onPressed: _cleanupArchivedRange,
                ),
                const SizedBox(height: 80),
                const Center(child: Text('还没有归档内容')),
              ],
            );
          }

          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 14,
              top: 10,
              right: 14,
            ),
            children: [
              _CleanupCard(
                busy: _cleaning,
                onPressed: _cleanupArchivedRange,
              ),
              const SizedBox(height: 14),
              if (orders.isNotEmpty) ...[
                const _SectionTitle('排单'),
                for (final order in orders) ...[
                  OrderSummaryCard(
                    order: order,
                    onTap: () => _openOrder(context, order.id),
                    showClient: widget.featureStore.clientInfo,
                    showNodeProgress: widget.featureStore.nodeProgress,
                  ),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('归档'),
                    subtitle: Text(_orderArchiveSubtitle(order)),
                    value: true,
                    onChanged: (value) {
                      if (!value) {
                        widget.orderStore.restoreArchivedOrder(order.id);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (products.isNotEmpty) ...[
                if (orders.isNotEmpty) const SizedBox(height: 12),
                const _SectionTitle('成品'),
                for (final product in products) ...[
                  ProductSummaryCard(
                    product: product,
                    onTap: () => _openProduct(context, product.id),
                  ),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('归档'),
                    subtitle: const Text('关闭后恢复到成品列表'),
                    value: true,
                    onChanged: (value) {
                      widget.productStore.setArchived(product.id, value);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CleanupCard extends StatelessWidget {
  const _CleanupCard({
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: const Icon(Icons.delete_sweep_outlined),
        title: const Text(
          '清理旧归档',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('自选归档时间范围，永久删除记录并解除参考图关联。'),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: busy ? null : onPressed,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
