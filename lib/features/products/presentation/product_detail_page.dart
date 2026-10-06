import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/adjustment_widgets.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../../orders/domain/queue_order.dart';
import '../domain/finished_product.dart';
import '../state/product_store.dart';
import 'product_sale_history_page.dart';
import 'product_summary_card.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    required this.store,
    required this.productId,
    required this.featureStore,
    super.key,
  });

  final ProductStore store;
  final String productId;
  final AppFeatureStore featureStore;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _editing = false;

  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _soldCountController;
  late final TextEditingController _onlineController;
  late final TextEditingController _offlineController;

  late CommissionPlatform _platform;
  late ProductSaleType _saleType;
  late int _soldCount;
  late FinishedProduct _draftBaseline;
  bool _feeEnabled = false;
  HuajiaLoveLevel _huajiaLoveLevel = HuajiaLoveLevel.none;
  double _onlinePercent = 100;

  FinishedProduct get _product => widget.store.byId(widget.productId);

  @override
  void initState() {
    super.initState();
    final product = _product;
    _titleController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();
    _soldCountController = TextEditingController();
    _onlineController = TextEditingController();
    _offlineController = TextEditingController();
    _loadDraft(product);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _soldCountController.dispose();
    _onlineController.dispose();
    _offlineController.dispose();
    super.dispose();
  }

  void _loadDraft(FinishedProduct product) {
    _draftBaseline = product;
    _titleController.text = product.title;
    _priceController.text = product.price == 0
        ? ''
        : formatProductPrice(product.price);
    _descriptionController.text = product.description;
    _soldCountController.text = product.soldCount.toString();
    _platform = product.platform;
    _saleType = product.saleType;
    _soldCount = product.soldCount;
    _feeEnabled = product.feeEnabled;
    _huajiaLoveLevel = product.huajiaLoveLevel;
    _onlinePercent = product.normalizedOnlinePercent;
    _onlineController.text = formatPercentValue(_onlinePercent);
    _offlineController.text = formatPercentValue(100 - _onlinePercent);
  }

  void _setOnlinePercent(double value) {
    final clamped = value.clamp(0, 100).toDouble();
    setState(() {
      _onlinePercent = clamped;
      _onlineController.text = formatPercentValue(clamped);
      _offlineController.text = formatPercentValue(100 - clamped);
    });
  }

  void _startEditing() {
    _loadDraft(_product);
    setState(() => _editing = true);
  }

  void _cancelEditing() {
    _loadDraft(_product);
    setState(() => _editing = false);
  }

  Future<void> _editSupplement(FinishedProduct product) async {
    final result = await showAdjustmentDialog(
      context: context,
      label: '补款',
      amount: product.supplementAmount,
      feeEnabled: product.supplementFeeEnabled,
    );
    if (!mounted || result == null) return;

    final current = widget.store.byId(widget.productId);
    widget.store.updateProduct(
      current.copyWith(
        supplementAmount: result.amount,
        supplementFeeEnabled: result.feeEnabled,
      ),
    );
  }

  Future<void> _editDeduction(FinishedProduct product) async {
    final result = await showAdjustmentDialog(
      context: context,
      label: '减款',
      amount: product.deductionAmount,
      feeEnabled: product.deductionFeeEnabled,
    );
    if (!mounted || result == null) return;

    final current = widget.store.byId(widget.productId);
    widget.store.updateProduct(
      current.copyWith(
        deductionAmount: result.amount,
        deductionFeeEnabled: result.feeEnabled,
      ),
    );
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    var soldCount = _saleType == ProductSaleType.multiple
        ? int.tryParse(_soldCountController.text.trim()) ?? 0
        : _soldCount;

    if (soldCount < 0) soldCount = 0;
    if (_saleType == ProductSaleType.single && soldCount > 1) {
      soldCount = 1;
    }

    final current = _product;
    final titleChanged = _titleController.text.trim() != _draftBaseline.title;
    final platformChanged = _platform != _draftBaseline.platform;
    final saleTypeChanged = _saleType != _draftBaseline.saleType;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final priceChanged = price != _draftBaseline.price;
    final feeChanged = _feeEnabled != _draftBaseline.feeEnabled;
    final loveLevelChanged = _huajiaLoveLevel != _draftBaseline.huajiaLoveLevel;
    final onlinePercentChanged =
        _onlinePercent != _draftBaseline.normalizedOnlinePercent;
    final descriptionChanged =
        _descriptionController.text.trim() != _draftBaseline.description;
    final soldCountChanged = soldCount != _draftBaseline.soldCount;
    final saleRecords = [...current.saleRecords];

    if (soldCountChanged && soldCount > current.soldCount) {
      final added = soldCount - current.soldCount;
      final now = DateTime.now();
      for (var index = 0; index < added; index++) {
        saleRecords.add(now.add(Duration(microseconds: index)));
      }
    } else if (soldCountChanged && soldCount < current.soldCount) {
      var removeCount = current.soldCount - soldCount;
      while (removeCount > 0 && saleRecords.isNotEmpty) {
        saleRecords.removeLast();
        removeCount -= 1;
      }
    }

    widget.store.updateProduct(
      current.copyWith(
        title: titleChanged ? _titleController.text.trim() : current.title,
        platform: platformChanged ? _platform : current.platform,
        saleType: saleTypeChanged ? _saleType : current.saleType,
        price: priceChanged ? price : current.price,
        feeEnabled: feeChanged ? _feeEnabled : current.feeEnabled,
        huajiaLoveLevel: loveLevelChanged
            ? _huajiaLoveLevel
            : current.huajiaLoveLevel,
        onlinePercent: onlinePercentChanged
            ? _onlinePercent
            : current.onlinePercent,
        description: descriptionChanged
            ? _descriptionController.text.trim()
            : current.description,
        soldCount: soldCountChanged ? soldCount : current.soldCount,
        saleRecords: soldCountChanged ? saleRecords : current.saleRecords,
      ),
    );

    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.featureStore]),
      builder: (context, _) {
        if (!widget.store.contains(widget.productId)) {
          return const Scaffold();
        }

        final product = _product;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              '成品详情',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              if (!_editing)
                IconButton(
                  tooltip: '编辑',
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_outlined),
                )
              else ...[
                IconButton(
                  tooltip: '取消编辑',
                  onPressed: _cancelEditing,
                  icon: const Icon(Icons.close_rounded),
                ),
                IconButton(
                  tooltip: '保存',
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                ),
              ],
              const SizedBox(width: 6),
            ],
          ),
          body: ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 18,
              top: 8,
              right: 18,
            ),
            children: [
              if (!_editing) ...[
                ReadOnlyDetailRow(label: '图名', value: product.title),
                ReadOnlyDetailRow(label: '平台', value: product.platform.label),
                ReadOnlyDetailRow(label: '售卖方式', value: product.saleType.label),
                ReadOnlyDetailRow(
                  label: '原始稿价',
                  value: product.price == 0
                      ? '未填写'
                      : '¥ ${formatProductPrice(product.price)}',
                ),
                ReadOnlyDetailRow(
                  label: '手续费',
                  value: product.feeEnabled
                      ? '开启 · ¥ ${formatProductPrice(product.serviceFeeAmount)}'
                      : '关闭',
                ),
                if (product.platform == CommissionPlatform.huajia &&
                    product.feeEnabled)
                  ReadOnlyDetailRow(
                    label: '真爱永恒',
                    value: product.huajiaLoveLevel == HuajiaLoveLevel.none
                        ? '无折扣'
                        : '${product.huajiaLoveLevel.label} · '
                              '手续费${(product.huajiaLoveLevel.feeMultiplier * 10).toStringAsFixed(0)}折',
                  ),
                if (product.platform.usesOnlineOfflineSplit)
                  ReadOnlyDetailRow(
                    label: '线上/线下',
                    value:
                        '${formatPercentValue(product.normalizedOnlinePercent)}% / '
                        '${formatPercentValue(product.offlinePercent)}%',
                  ),
                AdjustmentDetailRow(
                  label: '补款',
                  amount: product.supplementAmount,
                  feeEnabled: product.supplementFeeEnabled,
                  sign: '+',
                  onTap: () => _editSupplement(product),
                ),
                AdjustmentDetailRow(
                  label: '减款',
                  amount: product.deductionAmount,
                  feeEnabled: product.deductionFeeEnabled,
                  sign: '-',
                  onTap: () => _editDeduction(product),
                ),
                ReadOnlyDetailRow(
                  label: '真实收入',
                  value: '¥ ${formatProductPrice(product.realIncome)}',
                ),
                ReadOnlyDetailRow(
                  label: '售出状态',
                  value: product.saleStatusLabel,
                ),
                if (product.saleType == ProductSaleType.multiple)
                  _SaleHistoryDetailRow(
                    count: product.saleRecords.length,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductSaleHistoryPage(
                            product: product,
                          ),
                        ),
                      );
                    },
                  ),
                ReadOnlyDetailRow(
                  label: '描述',
                  value: product.description.trim().isEmpty
                      ? '未填写'
                      : product.description,
                  multiline: true,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回'),
                  ),
                ),
              ] else ...[
                const FormFieldLabel('图名'),
                TextField(controller: _titleController),
                const SizedBox(height: 14),
                CommissionSettingsEditor(
                  platform: _platform,
                  feeEnabled: _feeEnabled,
                  huajiaLoveLevel: _huajiaLoveLevel,
                  onlineController: _onlineController,
                  offlineController: _offlineController,
                  onPlatformChanged: (value) {
                    setState(() {
                      _platform = value;
                      _feeEnabled = value.defaultFeeEnabled;
                      _huajiaLoveLevel = HuajiaLoveLevel.none;
                      if (!value.usesOnlineOfflineSplit) {
                        _onlinePercent = 100;
                        _onlineController.text = '100';
                        _offlineController.text = '0';
                      }
                    });
                  },
                  onFeeEnabledChanged: (value) {
                    setState(() => _feeEnabled = value);
                  },
                  onHuajiaLoveLevelChanged: (value) {
                    setState(() => _huajiaLoveLevel = value);
                  },
                  onOnlinePercentChanged: _setOnlinePercent,
                  afterPlatform: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormFieldLabel('基础稿价'),
                      TextField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(prefixText: '¥ '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const FormFieldLabel('售卖方式'),
                SegmentedButton<ProductSaleType>(
                  segments: const [
                    ButtonSegment(
                      value: ProductSaleType.single,
                      label: Text('单次售卖'),
                    ),
                    ButtonSegment(
                      value: ProductSaleType.multiple,
                      label: Text('多次售卖'),
                    ),
                  ],
                  selected: {_saleType},
                  onSelectionChanged: (value) {
                    setState(() {
                      _saleType = value.first;
                      if (_saleType == ProductSaleType.single &&
                          _soldCount > 1) {
                        _soldCount = 1;
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                if (_saleType == ProductSaleType.single)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('已售出'),
                    value: _soldCount > 0,
                    onChanged: (value) {
                      setState(() => _soldCount = value ? 1 : 0);
                    },
                  )
                else ...[
                  const FormFieldLabel('售出数量'),
                  TextField(
                    controller: _soldCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ],
                const SizedBox(height: 14),
                const FormFieldLabel('描述'),
                TextField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(hintText: '成品内容、说明或备注'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('确认'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}


class _SaleHistoryDetailRow extends StatelessWidget {
  const _SaleHistoryDetailRow({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 82,
              child: Text(
                '售出记录',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                count == 0 ? '暂无记录' : '$count 条记录',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
