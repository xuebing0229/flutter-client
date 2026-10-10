import 'package:flutter/material.dart';

import '../../shared/presentation/summary_card_widgets.dart';
import '../domain/finished_product.dart';
import '../domain/sale_receipt.dart';

class ProductSummaryCard extends StatelessWidget {
  const ProductSummaryCard({
    required this.product,
    required this.onTap,
    this.onLongPress,
    this.onMarkSold,
    this.saleTime,
    this.saleReceipt,
    this.showPlatform = true,
    this.compact = false,
    this.hasSyncConflict = false,
    super.key,
  });

  final FinishedProduct product;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMarkSold;
  final DateTime? saleTime;
  final SaleReceipt? saleReceipt;
  final bool showPlatform;
  final bool compact;
  final bool hasSyncConflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
                      SummaryTag(text: saleReceipt?.platform.label ?? product.platform.label, compact: true),
                    const Spacer(),
                    if (hasSyncConflict) ...[
                      const Tooltip(
                        message: '有同步冲突待确认',
                        child: _SyncConflictDot(),
                      ),
                      const SizedBox(width: 7),
                    ],
                    if (product.isPinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  product.title,
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
                      SummaryTag(text: saleReceipt?.platform.label ?? product.platform.label),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (hasSyncConflict) ...[
                      const SizedBox(width: 8),
                      const Tooltip(
                        message: '有同步冲突待确认',
                        child: _SyncConflictDot(),
                      ),
                    ],
                    if (product.isPinned) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              SizedBox(height: compact ? 10 : 14),
              Divider(height: 1, color: colors.outlineVariant),
              SizedBox(height: compact ? 9 : 13),
              SummaryMetaItem(
                icon: product.saleType == ProductSaleType.single
                    ? Icons.looks_one_outlined
                    : Icons.repeat_rounded,
                label: product.saleType.label,
                compact: compact,
              ),
              SizedBox(height: compact ? 7 : 9),
              SummaryMetaItem(
                icon: Icons.sell_outlined,
                label: product.saleStatusLabel,
                compact: compact,
              ),
              if (saleTime != null) ...[
                SizedBox(height: compact ? 7 : 9),
                SummaryMetaItem(
                  icon: Icons.schedule_rounded,
                  label: '本次售出 ${_formatSaleTime(saleTime!)}',
                  compact: compact,
                ),
              ],
              SizedBox(height: compact ? 7 : 9),
              SummaryMetaItem(
                icon: Icons.payments_outlined,
                label: saleReceipt != null
                    ? '实收 ¥ ${formatProductPrice(saleReceipt!.netIncome)}'
                      '${saleReceipt!.estimated ? '（历史估算）' : ''}'
                    : product.price == 0
                        ? '未定价'
                        : '实收 ¥ ${formatProductPrice(product.realIncome)}',
                compact: compact,
              ),
              if (onMarkSold != null) ...[
                SizedBox(height: compact ? 10 : 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onMarkSold,
                    icon: const Icon(Icons.sell_outlined),
                    label: const Text('售出'),
                  ),
                ),
              ],
        ],
      ),
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

String formatProductPrice(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}


String _formatSaleTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}
