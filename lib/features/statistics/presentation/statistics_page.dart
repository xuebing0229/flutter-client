import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../products/domain/finished_product.dart';
import '../../products/state/product_store.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({
    required this.store,
    required this.productStore,
    super.key,
  });

  final OrderStore store;
  final ProductStore productStore;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  List<QueueOrder> _incomeOrdersFor(DateTime month) {
    return widget.store.orders.where((order) {
      final incomeAt = _incomeDate(order);
      return order.isArchived &&
          incomeAt != null &&
          incomeAt.year == month.year &&
          incomeAt.month == month.month;
    }).toList();
  }

  List<FinishedProduct> _productSalesFor(DateTime month) {
    final sales = <FinishedProduct>[];
    for (final product in widget.productStore.products) {
      for (final soldAt in product.saleRecords) {
        if (_sameMonth(soldAt, month)) sales.add(product);
      }
    }
    return sales;
  }

  double _totalFor(
    Iterable<QueueOrder> orders,
    Iterable<FinishedProduct> sales,
  ) {
    final orderIncome = orders.fold<double>(
      0,
      (sum, order) => sum + order.settlementIncome,
    );
    final productIncome = sales.fold<double>(
      0,
      (sum, product) => sum + product.realIncome,
    );
    return orderIncome + productIncome;
  }

  Map<CommissionPlatform, double> _platformTotals(
    Iterable<QueueOrder> orders,
    Iterable<FinishedProduct> sales,
  ) {
    final result = <CommissionPlatform, double>{};

    for (final order in orders) {
      final platform = _statisticsPlatform(order.platform);
      result[platform] = (result[platform] ?? 0) + order.settlementIncome;
    }

    for (final product in sales) {
      final platform = _statisticsPlatform(product.platform);
      result[platform] = (result[platform] ?? 0) + product.realIncome;
    }

    return result;
  }

  Future<void> _pickMonth() async {
    var year = _selectedMonth.year;
    var month = _selectedMonth.month;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择月份'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setDialogState(() => year -= 1);
                          },
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(
                            '$year 年',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setDialogState(() => year += 1);
                          },
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.15,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        final value = index + 1;
                        return ChoiceChip(
                          label: Text('$value 月'),
                          selected: month == value,
                          onSelected: (_) {
                            setDialogState(() => month = value);
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(DateTime(year, month));
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedMonth = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.store,
        widget.productStore,
      ]),
      builder: (context, _) {
        final monthOrders = _incomeOrdersFor(_selectedMonth);
        final monthSales = _productSalesFor(_selectedMonth);
        // Reuse the filtered lists instead of traversing all history again.
        final total = _totalFor(monthOrders, monthSales);
        final platformTotals = _platformTotals(monthOrders, monthSales);

        return ListView(
          padding: AppLayoutSpacing.tabScrollPadding(
            left: 14,
            top: 12,
            right: 14,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickMonth,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(
                  '${_selectedMonth.year}年${_selectedMonth.month}月',
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SummaryCard(
              count: monthOrders.length + monthSales.length,
              total: total,
            ),
            const SizedBox(height: 12),
            _PlatformCategoryCard(
              totals: platformTotals,
              total: total,
            ),
            const SizedBox(height: 12),
            _DistributionCard(
              totals: platformTotals,
              total: total,
            ),
            const SizedBox(height: 12),
            _MonthlyChangeCard(
              selectedMonth: _selectedMonth,
              store: widget.store,
              productStore: widget.productStore,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.total,
  });

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收入总计',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '收入 $count 笔，共计金额',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '¥ ${_money(total)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlatformCategoryCard extends StatelessWidget {
  const _PlatformCategoryCard({
    required this.totals,
    required this.total,
  });

  final Map<CommissionPlatform, double> totals;
  final double total;

  @override
  Widget build(BuildContext context) {
    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收入分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          if (totals.isEmpty)
            Text(
              '本月暂无收入分类',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < totals.entries.length; index++) ...[
              Builder(
                builder: (context) {
                  final entry = totals.entries.elementAt(index);
                  return _PlatformIncomeRow(
                    platform: entry.key,
                    amount: entry.value,
                    total: total,
                    color: _platformColor(
                      CommissionPlatform.values.indexOf(entry.key),
                    ),
                  );
                },
              ),
              if (index != totals.entries.length - 1)
                const SizedBox(height: 17),
            ],
        ],
      ),
    );
  }
}

class _PlatformIncomeRow extends StatelessWidget {
  const _PlatformIncomeRow({
    required this.platform,
    required this.amount,
    required this.total,
    required this.color,
  });

  final CommissionPlatform platform;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            Icons.sell_outlined,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      platform.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '¥${_money(amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  color: color,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.totals,
    required this.total,
  });

  final Map<CommissionPlatform, double> totals;
  final double total;

  @override
  Widget build(BuildContext context) {
    final active = <_DistributionItem>[];
    for (final entry in totals.entries) {
      if (entry.value > 0) {
        active.add(
          _DistributionItem(
            platform: entry.key,
            amount: entry.value,
            color: _platformColor(
              CommissionPlatform.values.indexOf(entry.key),
            ),
          ),
        );
      }
    }

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收入分布',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: _DonutPainter(
                  items: active,
                  total: total,
                  emptyColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    total <= 0 ? '暂无收入' : '¥${_money(total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (active.isEmpty)
            Text(
              '本月暂无收入分布',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...active.map((item) {
              final percent =
                  total <= 0 ? 0.0 : item.amount / total * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${item.platform.label} '
                        '${percent.toStringAsFixed(1)}%',
                      ),
                    ),
                    Text(
                      '¥${_money(item.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MonthlyChangeCard extends StatelessWidget {
  const _MonthlyChangeCard({
    required this.selectedMonth,
    required this.store,
    required this.productStore,
  });

  final DateTime selectedMonth;
  final OrderStore store;
  final ProductStore productStore;

  @override
  Widget build(BuildContext context) {
    final months = List.generate(
      5,
      (index) => DateTime(
        selectedMonth.year,
        selectedMonth.month - 4 + index,
      ),
    );

    // Bucket each event once rather than rescanning the entire order and
    // sale history separately for every bar in the five-month chart.
    final monthIndexes = <int, int>{
      for (var index = 0; index < months.length; index++)
        months[index].year * 12 + months[index].month: index,
    };
    final values = List<double>.filled(months.length, 0);
    for (final order in store.orders) {
      if (!order.isArchived) continue;
      final at = _incomeDate(order);
      if (at == null) continue;
      final index = monthIndexes[at.year * 12 + at.month];
      if (index != null) values[index] += order.settlementIncome;
    }
    for (final product in productStore.products) {
      final income = product.realIncome;
      for (final soldAt in product.saleRecords) {
        final index = monthIndexes[soldAt.year * 12 + soldAt.month];
        if (index != null) values[index] += income;
      }
    }

    final maxValue = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收入月度变化',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 210,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < months.length; i++)
                  Expanded(
                    child: _MonthBar(
                      month: months[i],
                      value: values[i],
                      maxValue: maxValue,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.value,
    required this.maxValue,
  });

  final DateTime month;
  final double value;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
    final barHeight = 135.0 * ratio;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 28,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value <= 0 ? '' : '¥${_compactMoney(value)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 24,
          height: math.max(4, barHeight),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${month.year}.${month.month}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

class _DistributionItem {
  const _DistributionItem({
    required this.platform,
    required this.amount,
    required this.color,
  });

  final CommissionPlatform platform;
  final double amount;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.items,
    required this.total,
    required this.emptyColor,
  });

  final List<_DistributionItem> items;
  final double total;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 28.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    if (total <= 0 || items.isEmpty) {
      basePaint.color = emptyColor;
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        math.pi * 2,
        false,
        basePaint,
      );
      return;
    }

    var start = -math.pi / 2;
    for (final item in items) {
      final sweep = item.amount / total * math.pi * 2;
      basePaint.color = item.color;
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        basePaint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.total != total ||
        oldDelegate.emptyColor != emptyColor;
  }
}

Color _platformColor(int index) {
  const colors = [
    Color(0xFF2F6BFF),
    Color(0xFF1FA9E5),
    Color(0xFF57B77C),
    Color(0xFFF0A24B),
    Color(0xFF8B6FD9),
    Color(0xFFD96F9A),
  ];
  return colors[index % colors.length];
}

String _money(double value) {
  return value.toStringAsFixed(2);
}

String _compactMoney(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}


DateTime? _incomeDate(QueueOrder order) {
  return order.settledAt ?? order.completedAt;
}

bool _sameMonth(DateTime value, DateTime month) {
  return value.year == month.year && value.month == month.month;
}


CommissionPlatform _statisticsPlatform(CommissionPlatform platform) {
  return platform == CommissionPlatform.archivedOffline
      ? CommissionPlatform.offline
      : platform;
}
