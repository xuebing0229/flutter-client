import 'package:flutter/material.dart';

import '../../shared/presentation/detail_form_widgets.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../domain/finished_product.dart';
import '../state/product_store.dart';

class ProductSaleHistoryPage extends StatefulWidget {
  const ProductSaleHistoryPage({
    required this.store,
    required this.productId,
    super.key,
  });

  final ProductStore store;
  final String productId;

  @override
  State<ProductSaleHistoryPage> createState() => _ProductSaleHistoryPageState();
}

class _ProductSaleHistoryPageState extends State<ProductSaleHistoryPage> {
  Future<void> _editClient(FinishedProduct product, DateTime soldAt) async {
    final controller = TextEditingController(
      text: product.clientNameForSale(soldAt) ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('售出单主'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '单主',
            hintText: '留空表示不归入单主年度统计',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              controller.text.trim(),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null || !widget.store.contains(widget.productId)) {
      return;
    }

    final current = widget.store.byId(widget.productId);
    if (!current.saleRecords.any((item) => item.isAtSameMomentAs(soldAt))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这条售出记录已经不存在。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final key = soldAt.toUtc().toIso8601String();
    final next = <String, String>{...current.saleClientNames};
    if (result.isEmpty) {
      next.remove(key);
    } else {
      next[key] = result;
    }
    widget.store.updateProduct(current.copyWith(saleClientNames: next));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        if (!widget.store.contains(widget.productId)) {
          return const Scaffold();
        }

        final product = widget.store.byId(widget.productId);
        final records = [...product.saleRecords]..sort();
        final colors = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              '售出记录',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 18,
              top: 8,
              right: 18,
            ),
            children: [
              Text(
                product.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                records.isEmpty
                    ? '暂无售出时间记录'
                    : '共 ${records.length} 次售出 · 可补填单主用于年度小票',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              if (records.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 32,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '这个成品还没有可查看的售出时间记录',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                ...List.generate(records.length, (index) {
                  final occurrenceNumber = records.length - index;
                  final soldAt = records[occurrenceNumber - 1];
                  final client = product.clientNameForSale(soldAt);

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == records.length - 1 ? 0 : 10,
                    ),
                    child: Material(
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(
                          Icons.sell_outlined,
                          color: colors.primary,
                        ),
                        title: Text(
                          product.saleType == ProductSaleType.single
                              ? '售出时间'
                              : '第 $occurrenceNumber 次售出',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${formatDateTimeValue(soldAt)}\n'
                          '单主：${client ?? '未标记'}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => _editClient(product, soldAt),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
