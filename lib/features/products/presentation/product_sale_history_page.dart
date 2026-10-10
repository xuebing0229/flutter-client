import 'package:flutter/material.dart';

import '../../shared/presentation/detail_form_widgets.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../domain/finished_product.dart';

class ProductSaleHistoryPage extends StatelessWidget {
  const ProductSaleHistoryPage({
    required this.product,
    super.key,
  });

  final FinishedProduct product;

  @override
  Widget build(BuildContext context) {
    final records = [...product.accountedSales]
      ..sort((a, b) => a.soldAt.compareTo(b.soldAt));
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
                : '共 ${records.length} 次售出',
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
              final receipt = records[occurrenceNumber - 1];

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
                      '${formatDateTimeValue(receipt.soldAt)} · '
                      '实收 ¥${receipt.netIncome.toStringAsFixed(2)}'
                      '${receipt.estimated ? '（按旧资料估算）' : ''}',
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
