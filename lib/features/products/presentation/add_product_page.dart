import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../orders/domain/queue_order.dart';
import '../domain/finished_product.dart';
import '../state/product_store.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({
    required this.store,
    required this.featureStore,
    super.key,
  });

  final ProductStore store;
  final AppFeatureStore featureStore;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _onlineController = TextEditingController(text: '100');
  final _offlineController = TextEditingController(text: '0');

  CommissionPlatform _platform = CommissionPlatform.mihuashi;
  ProductSaleType _saleType = ProductSaleType.single;
  bool _feeEnabled = CommissionPlatform.mihuashi.defaultFeeEnabled;
  HuajiaLoveLevel _huajiaLoveLevel = HuajiaLoveLevel.none;
  double _onlinePercent = 100;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _onlineController.dispose();
    _offlineController.dispose();
    super.dispose();
  }

  void _setOnlinePercent(double value) {
    final clamped = value.clamp(0, 100).toDouble();
    setState(() {
      _onlinePercent = clamped;
      _onlineController.text = formatPercentValue(clamped);
      _offlineController.text = formatPercentValue(100 - clamped);
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写图名'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    widget.store.addProduct(
      FinishedProduct(
        id: 'product-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        platform: _platform,
        saleType: _saleType,
        price: double.tryParse(_priceController.text.trim()) ?? 0,
        feeEnabled: _feeEnabled,
        huajiaLoveLevel: _huajiaLoveLevel,
        onlinePercent: _onlinePercent,
        supplementFeeEnabled: _platform.defaultAdjustmentFeeEnabled,
        deductionFeeEnabled: _platform.defaultAdjustmentFeeEnabled,
        description: _descriptionController.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '新增成品',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
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
          const FormFieldLabel('图名'),
          TextField(
            controller: _titleController,
          ),
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
                const FormFieldLabel('原始稿价'),
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
              setState(() => _saleType = value.first);
            },
          ),
          const SizedBox(height: 14),
          const FormFieldLabel('描述'),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              hintText: '成品内容、说明或备注',
            ),
          ),
        ],
      ),
    );
  }
}
