import 'package:flutter/material.dart';

import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../products/domain/finished_product.dart';
import '../../products/state/product_store.dart';
import '../domain/receipt_style_store.dart';
import 'collection_widgets.dart';
import 'receipt_page.dart';

enum _ArchiveFilter {
  all('全部'),
  active('未归档'),
  archived('已归档');

  const _ArchiveFilter(this.label);
  final String label;
}

enum _ContentFilter {
  all('全部'),
  orders('排单'),
  products('成品');

  const _ContentFilter(this.label);
  final String label;
}

class ReceiptCenterPage extends StatefulWidget {
  const ReceiptCenterPage({
    required this.orderStore,
    required this.productStore,
    required this.receiptStyleStore,
    super.key,
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final ReceiptStyleStore receiptStyleStore;

  @override
  State<ReceiptCenterPage> createState() => _ReceiptCenterPageState();
}

class _ReceiptCenterPageState extends State<ReceiptCenterPage> {
  final TextEditingController _singleSearchController = TextEditingController();
  final TextEditingController _clientSearchController = TextEditingController();

  _ArchiveFilter _archiveFilter = _ArchiveFilter.all;
  _ContentFilter _contentFilter = _ContentFilter.all;
  DateTimeRange? _singleDateRange;
  String _singleQuery = '';
  String _singleSearchField = 'all';
  String _clientQuery = '';
  int? _selectedYear;

  @override
  void dispose() {
    _singleSearchController.dispose();
    _clientSearchController.dispose();
    super.dispose();
  }

  DateTime? _orderDate(QueueOrder order) {
    return order.settledAt ?? order.completedAt ?? order.deadline;
  }

  DateTime? _productDate(FinishedProduct product) {
    if (product.saleRecords.isNotEmpty) {
      final records = [...product.saleRecords]..sort();
      return records.last;
    }
    return product.archivedAt;
  }

  bool _matchesRange(DateTime? value) {
    final range = _singleDateRange;
    if (range == null) return true;
    if (value == null) return false;
    final day = DateTime(value.year, value.month, value.day);
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    );
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool _matchesArchive(bool isArchived) {
    return switch (_archiveFilter) {
      _ArchiveFilter.all => true,
      _ArchiveFilter.active => !isArchived,
      _ArchiveFilter.archived => isArchived,
    };
  }

  bool _matchesSingleQuery({
    required String title,
    required Iterable<String> clients,
    required String platform,
    Iterable<String> extra = const <String>[],
  }) {
    final query = _singleQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final titleMatches = title.toLowerCase().contains(query);
    final clientMatches = clients.any(
      (client) => client.toLowerCase().contains(query),
    );
    final platformMatches = platform.toLowerCase().contains(query);
    final extraMatches = extra.any(
      (value) => value.toLowerCase().contains(query),
    );

    return switch (_singleSearchField) {
      'title' => titleMatches,
      'client' => clientMatches,
      'platform' => platformMatches,
      _ => titleMatches || clientMatches || platformMatches || extraMatches,
    };
  }

  List<_SingleReceiptItem> _singleItems() {
    final items = <_SingleReceiptItem>[];

    if (_contentFilter != _ContentFilter.products) {
      for (final order in widget.orderStore.orders) {
        final date = _orderDate(order);
      if (!_matchesArchive(order.isArchived) ||
          !_matchesRange(date) ||
          !_matchesSingleQuery(
            title: order.title,
            clients: [order.clientName],
            platform: order.platform.label,
            extra: const ['排单'],
          )) {
        continue;
      }
        items.add(
          _SingleReceiptItem.order(
            order: order,
            date: date,
          ),
        );
      }
    }

    if (_contentFilter != _ContentFilter.orders) {
      for (final product in widget.productStore.products) {
      final date = _productDate(product);
      final saleClients = <String>[];
      for (final soldAt in product.saleRecords) {
        final name = product.clientNameForSale(soldAt);
        if (name != null) saleClients.add(name);
      }
      if (!_matchesArchive(product.isArchived) ||
          !_matchesRange(date) ||
          !_matchesSingleQuery(
            title: product.title,
            clients: saleClients,
            platform: product.platform.label,
            extra: [product.saleType.label, '成品'],
          )) {
        continue;
      }
        items.add(
          _SingleReceiptItem.product(
            product: product,
            date: date,
          ),
        );
      }
    }

    items.sort((left, right) {
      final leftDate = left.date;
      final rightDate = right.date;
      if (leftDate == null && rightDate == null) {
        return left.title.compareTo(right.title);
      }
      if (leftDate == null) return 1;
      if (rightDate == null) return -1;
      final byDate = rightDate.compareTo(leftDate);
      if (byDate != 0) return byDate;
      return left.title.compareTo(right.title);
    });
    return items;
  }

  Map<String, List<int>> _annualClientYears() {
    final yearsByKey = <String, Set<int>>{};
    final displayName = <String, String>{};

    void add(String rawName, int year) {
      final name = rawName.trim();
      if (name.isEmpty) return;
      final key = name.toLowerCase();
      displayName.putIfAbsent(key, () => name);
      yearsByKey.putIfAbsent(key, () => <int>{}).add(year);
    }

    for (final order in widget.orderStore.orders) {
      if (!order.isArchived) continue;
      final date = order.settledAt ?? order.completedAt;
      if (date == null) continue;
      add(order.clientName, date.year);
    }

    for (final product in widget.productStore.products) {
      if (!product.isArchived) continue;
      for (final soldAt in product.saleRecords) {
        final client = product.clientNameForSale(soldAt);
        if (client != null) add(client, soldAt.year);
      }
    }

    final keys = yearsByKey.keys.toList()
      ..sort((a, b) => displayName[a]!.compareTo(displayName[b]!));
    return <String, List<int>>{
      for (final key in keys)
        displayName[key]!: (yearsByKey[key]!.toList()
          ..sort((a, b) => b.compareTo(a))),
    };
  }

  Future<void> _pickSingleRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
      initialDateRange: _singleDateRange,
    );
    if (!mounted || picked == null) return;
    setState(() => _singleDateRange = picked);
  }

  Future<void> _openSingle(_SingleReceiptItem item) async {
    final data = item.order != null
        ? ReceiptData.fromOrder(item.order!)
        : ReceiptData.fromProduct(item.product!);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReceiptPage(
          data: data,
          styleStore: widget.receiptStyleStore,
        ),
      ),
    );
  }

  Future<void> _openAnnual(String clientName, int year) async {
    final data = AnnualReceiptData.fromSources(
      clientName: clientName,
      year: year,
      orders: widget.orderStore.orders,
      products: widget.productStore.products,
    );
    if (data.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这个单主在所选年份没有已归档业务。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReceiptPage.annual(
          annualData: data,
          styleStore: widget.receiptStyleStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '生成小票',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: '按单子生成'),
              Tab(text: '按单主生成'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            widget.orderStore,
            widget.productStore,
          ]),
          builder: (context, _) {
            return TabBarView(
              children: [
                _buildSingleTab(context),
                _buildAnnualTab(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSingleTab(BuildContext context) {
    final items = _singleItems();
    return Column(
      children: [
        CollectionSearchField(
          controller: _singleSearchController,
          query: _singleQuery,
          hintText: '搜索图名、单主、平台',
          filters: const [
            SearchFilterOption(id: 'all', label: '全部'),
            SearchFilterOption(id: 'title', label: '图名'),
            SearchFilterOption(id: 'client', label: '单主'),
            SearchFilterOption(id: 'platform', label: '平台'),
          ],
          selectedFilter: _singleSearchField,
          onFilterChanged: (value) {
            setState(() => _singleSearchField = value);
          },
          onChanged: (value) => setState(() => _singleQuery = value),
          onClear: () {
            _singleSearchController.clear();
            setState(() => _singleQuery = '');
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_ArchiveFilter>(
                      value: _archiveFilter,
                      decoration: const InputDecoration(
                        labelText: '归档状态',
                        isDense: true,
                      ),
                      items: [
                        for (final filter in _ArchiveFilter.values)
                          DropdownMenuItem(
                            value: filter,
                            child: Text(filter.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _archiveFilter = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<_ContentFilter>(
                      value: _contentFilter,
                      decoration: const InputDecoration(
                        labelText: '内容类型',
                        isDense: true,
                      ),
                      items: [
                        for (final filter in _ContentFilter.values)
                          DropdownMenuItem(
                            value: filter,
                            child: Text(filter.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _contentFilter = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_singleDateRange == null)
                    ActionChip(
                      avatar: const Icon(Icons.date_range_outlined, size: 18),
                      label: const Text('筛选时间'),
                      onPressed: _pickSingleRange,
                    )
                  else
                    InputChip(
                      avatar: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        '${_date(_singleDateRange!.start)} ～ '
                        '${_date(_singleDateRange!.end)}',
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 18),
                      deleteButtonTooltipMessage: '清除时间',
                      onDeleted: () =>
                          setState(() => _singleDateRange = null),
                      onSelected: (_) => _pickSingleRange(),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('没有符合条件的排单或成品'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            item.order != null
                                ? Icons.assignment_outlined
                                : Icons.image_outlined,
                            size: 19,
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            item.kindLabel,
                            item.platform,
                            item.isArchived ? '已归档' : '未归档',
                            if (item.date != null) _date(item.date!),
                          ].join(' · '),
                        ),
                        trailing: Text(
                          '¥${_money(item.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => _openSingle(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAnnualTab(BuildContext context) {
    final options = _annualClientYears();
    final allYears = options.values.expand((value) => value).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final selectedYear = allYears.isEmpty
        ? DateTime.now().year
        : (_selectedYear != null && allYears.contains(_selectedYear)
            ? _selectedYear!
            : allYears.first);
    if (_selectedYear != selectedYear && allYears.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedYear != selectedYear) {
          setState(() => _selectedYear = selectedYear);
        }
      });
    }

    final query = _clientQuery.trim().toLowerCase();
    final clients = options.keys.where((client) {
      if (!options[client]!.contains(selectedYear)) return false;
      return query.isEmpty || client.toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _clientSearchController,
                  decoration: InputDecoration(
                    hintText: '搜索单主',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _clientQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
                            onPressed: () {
                              _clientSearchController.clear();
                              setState(() => _clientQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) => setState(() => _clientQuery = value),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: allYears.isEmpty ? null : selectedYear,
                hint: const Text('年份'),
                items: [
                  for (final year in allYears)
                    DropdownMenuItem(
                      value: year,
                      child: Text('$year 年'),
                    ),
                ],
                onChanged: allYears.isEmpty
                    ? null
                    : (value) => setState(() => _selectedYear = value),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '年度小票只统计已归档业务；成品仅统计已记录单主的售出记录。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ),
        Expanded(
          child: clients.isEmpty
              ? const Center(child: Text('所选年份暂无可生成年度小票的单主'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    final data = AnnualReceiptData.fromSources(
                      clientName: client,
                      year: selectedYear,
                      orders: widget.orderStore.orders,
                      products: widget.productStore.products,
                    );
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline_rounded),
                        ),
                        title: Text(client),
                        subtitle: Text(
                          '${data.entries.length} 单 · $selectedYear 年',
                        ),
                        trailing: Text(
                          '¥${_money(data.total)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => _openAnnual(client, selectedYear),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SingleReceiptItem {
  const _SingleReceiptItem._({
    required this.title,
    required this.platform,
    required this.amount,
    required this.isArchived,
    required this.date,
    this.order,
    this.product,
  });

  factory _SingleReceiptItem.order({
    required QueueOrder order,
    required DateTime? date,
  }) {
    return _SingleReceiptItem._(
      title: order.title,
      platform: order.platform.label,
      amount: order.originalTotal,
      isArchived: order.isArchived,
      date: date,
      order: order,
    );
  }

  factory _SingleReceiptItem.product({
    required FinishedProduct product,
    required DateTime? date,
  }) {
    return _SingleReceiptItem._(
      title: product.title,
      platform: product.platform.label,
      amount: product.originalTotal,
      isArchived: product.isArchived,
      date: date,
      product: product,
    );
  }

  final String title;
  final String platform;
  final double amount;
  final bool isArchived;
  final DateTime? date;
  final QueueOrder? order;
  final FinishedProduct? product;

  String get kindLabel => order != null ? '排单' : '成品';
}

String _date(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _money(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
