import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

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

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    required this.store,
    required this.productStore,
    required this.nodePresetStore,
    required this.featureStore,
    super.key,
  });

  final OrderStore store;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  List<QueueOrder> _pendingOn(DateTime date) {
    return widget.store.orders.where((order) {
      final deadline = order.deadline;
      return !order.isCompleted && deadline != null && _sameDay(deadline, date);
    }).toList();
  }

  List<QueueOrder> _completedOn(DateTime date) {
    return widget.store.orders.where((order) {
      final completedAt = order.completedAt;
      return completedAt != null &&
          order.archiveOutcome != OrderArchiveOutcome.terminated &&
          _sameDay(completedAt, date);
    }).toList();
  }

  List<_ProductSaleOccurrence> _productSalesOn(DateTime date) {
    if (!widget.featureStore.products) {
      return const <_ProductSaleOccurrence>[];
    }

    final result = <_ProductSaleOccurrence>[];

    for (final product in widget.productStore.products) {
      for (final soldAt in product.saleRecords) {
        if (_sameDay(soldAt, date)) {
          result.add(_ProductSaleOccurrence(product: product, soldAt: soldAt));
        }
      }
    }

    result.sort((left, right) => left.soldAt.compareTo(right.soldAt));
    return result;
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedDate = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    });
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

  double _dailyIncomeOn(DateTime date) {
    var total = 0.0;

    for (final order in widget.store.orders) {
      if (!order.isArchived) continue;
      final incomeAt = order.settledAt ?? order.completedAt;
      if (incomeAt != null && _sameDay(incomeAt, date)) {
        total += order.settlementIncome;
      }
    }

    for (final sale in _productSalesOn(date)) {
      total += sale.product.realIncome;
    }

    return total;
  }

  void _openOrder(QueueOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          store: widget.store,
          orderId: order.id,
          nodePresetStore: widget.nodePresetStore,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  void _openProduct(FinishedProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(
          store: widget.productStore,
          productId: product.id,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.store,
        widget.productStore,
        widget.featureStore,
        widget.nodePresetStore,
      ]),
      builder: (context, _) {
        final pendingSelected = _pendingOn(_selectedDate);
        final completedSelected = _completedOn(_selectedDate);
        final productSalesSelected = _productSalesOn(_selectedDate);

        final dailyIncome = _dailyIncomeOn(_selectedDate);

        return ListView(
          padding: AppLayoutSpacing.tabScrollPadding(left: 0, top: 0, right: 0),
          children: [
            _MonthHeader(
              month: _visibleMonth,
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
            ),
            const _WeekdayHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _MonthGrid(
                month: _visibleMonth,
                selectedDate: _selectedDate,
                pendingCount: (date) => _pendingOn(date).length,
                completedCount: (date) => _completedOn(date).length,
                saleCount: (date) => _productSalesOn(date).length,
                onSelect: _selectDate,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatSelectedDate(_selectedDate),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '当日收入 ¥${_money(dailyIncome)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionTitle(
                    title: '待交稿',
                    count: pendingSelected.length,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  if (pendingSelected.isEmpty)
                    const _EmptySection(text: '这一天没有待交稿')
                  else
                    ..._cards(pendingSelected),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: '已交稿',
                    count: completedSelected.length,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 8),
                  if (completedSelected.isEmpty)
                    const _EmptySection(text: '这一天没有已交稿')
                  else
                    ..._cards(completedSelected),
                  if (widget.featureStore.products) ...[
                    const SizedBox(height: 18),
                    _SectionTitle(
                      title: '成品售出',
                      count: productSalesSelected.length,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    if (productSalesSelected.isEmpty)
                      const _EmptySection(text: '这一天没有成品售出')
                    else
                      ..._productSaleCards(productSalesSelected),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _cards(List<QueueOrder> orders) {
    final widgets = <Widget>[];
    for (var index = 0; index < orders.length; index++) {
      final order = orders[index];
      widgets.add(
        OrderSummaryCard(
          order: order,
          onTap: () => _openOrder(order),
          showClient: widget.featureStore.clientInfo,
          showNodeProgress: widget.featureStore.nodeProgress,
        ),
      );
      if (index != orders.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
  }

  List<Widget> _productSaleCards(List<_ProductSaleOccurrence> sales) {
    final widgets = <Widget>[];

    for (var index = 0; index < sales.length; index++) {
      final sale = sales[index];
      widgets.add(
        ProductSummaryCard(
          product: sale.product,
          saleTime: sale.soldAt,
          onTap: () => _openProduct(sale.product),
        ),
      );
      if (index != sales.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }

    return widgets;
  }

  String _formatSelectedDate(DateTime value) {
    return '${value.year}年${value.month}月${value.day}日';
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, desktop ? 6 : 10, 12, desktop ? 4 : 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '上个月',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${month.year} 年 ${month.month} 月',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: desktop ? 28 : null,
              ),
            ),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: desktop ? 2 : 4),
      child: Row(
        children: [
          for (final label in _labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: desktop ? 16 : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selectedDate,
    required this.pendingCount,
    required this.completedCount,
    required this.saleCount,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selectedDate;
  final int Function(DateTime date) pendingCount;
  final int Function(DateTime date) completedCount;
  final int Function(DateTime date) saleCount;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstOffset = firstDay.weekday % 7;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((firstOffset + dayCount + 6) ~/ 7) * 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = MediaQuery.sizeOf(context).width >= 900;
        // Desktop cells have much more horizontal room than a phone. Keep the
        // month compact vertically and spend that room on readable labels.
        final cellHeight = desktop
            ? (constraints.maxWidth / 7 * 0.45).clamp(64.0, 74.0).toDouble()
            : (constraints.maxWidth / 7 * 1.05).clamp(56.0, 96.0).toDouble();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: cellHeight,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - firstOffset + 1;
            if (dayNumber < 1 || dayNumber > dayCount) {
              return const SizedBox.shrink();
            }

            final date = DateTime(month.year, month.month, dayNumber);
            final pending = pendingCount(date);
            final completed = completedCount(date);
            final sold = saleCount(date);
            final selected = _sameDay(date, selectedDate);
            final today = _sameDay(date, DateTime.now());

            return _CalendarCell(
              date: date,
              pending: pending,
              completed: completed,
              sold: sold,
              selected: selected,
              today: today,
              onTap: () => onSelect(date),
            );
          },
        );
      },
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.pending,
    required this.completed,
    required this.sold,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final int pending;
  final int completed;
  final int sold;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.all(desktop ? 1 : 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(desktop ? 10 : 12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            vertical: desktop ? 3 : 5,
            horizontal: 3,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (today)
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: desktop ? 28 : 34,
                        color: colors.primary.withValues(alpha: 0.18),
                      ),
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: desktop ? 28 : 34,
                        color: colors.primary.withValues(alpha: 0.52),
                      ),
                    ],
                  ),
                ),
              Column(
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: desktop ? 18 : null,
                    ),
                  ),
                  SizedBox(height: desktop ? 1 : 3),
                  if (pending > 0)
                    Text(
                      '待 $pending',
                      style: TextStyle(
                        color: colors.error,
                        fontSize: desktop ? 13 : 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (completed > 0)
                    Text(
                      '已 $completed',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: desktop ? 13 : 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (sold > 0)
                    Text(
                      '售 $sold',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: desktop ? 13 : 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSaleOccurrence {
  const _ProductSaleOccurrence({required this.product, required this.soldAt});

  final FinishedProduct product;
  final DateTime soldAt;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          '$title $count',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _money(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
