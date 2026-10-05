import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
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

class ArchivePage extends StatelessWidget {
  const ArchivePage({
    required this.accountId,
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.featureStore,
    super.key,
  });

  final String accountId;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;

  void _openOrder(BuildContext context, String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          accountId: accountId,
          store: orderStore,
          orderId: orderId,
          nodePresetStore: nodePresetStore,
          featureStore: featureStore,
        ),
      ),
    );
  }

  void _openProduct(BuildContext context, String productId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(
          store: productStore,
          productId: productId,
          featureStore: featureStore,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '归档',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          orderStore,
          productStore,
          featureStore,
        ]),
        builder: (context, _) {
          final orders = orderStore.orders
              .where((order) => order.isArchived)
              .toList();
          final products = featureStore.products
              ? productStore.products
                  .where((product) => product.isArchived)
                  .toList()
              : const <FinishedProduct>[];

          if (orders.isEmpty && products.isEmpty) {
            return const Center(
              child: Text('还没有归档内容'),
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
              if (orders.isNotEmpty) ...[
                const _SectionTitle('排单'),
                for (final order in orders) ...[
                  OrderSummaryCard(
                    order: order,
                    onTap: () => _openOrder(context, order.id),
                    showClient: featureStore.clientInfo,
                    showNodeProgress: featureStore.nodeProgress,
                  ),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('归档'),
                    subtitle: Text(_orderArchiveSubtitle(order)),
                    value: true,
                    onChanged: (value) {
                      if (!value) {
                        orderStore.restoreArchivedOrder(order.id);
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
                      productStore.setArchived(product.id, value);
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
