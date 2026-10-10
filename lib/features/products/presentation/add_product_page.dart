import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../orders/data/order_reference_image_store.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/presentation/order_reference_image_widgets.dart';
import '../domain/finished_product.dart';
import '../state/product_store.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({
    required this.accountId,
    required this.store,
    required this.featureStore,
    super.key,
  });

  final String accountId;
  final ProductStore store;
  final AppFeatureStore featureStore;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _referenceImageStore = OrderReferenceImageStore();
  final _referenceImages = <OrderReferenceImage>[];
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
  late final String _draftProductId;
  bool _saved = false;
  bool _pickingReferenceImages = false;

  @override
  void initState() {
    super.initState();
    _draftProductId = 'product-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    if (!_saved && _referenceImages.isNotEmpty) {
      unawaited(
        _referenceImageStore.deleteImages(
          accountId: widget.accountId,
          images: List<OrderReferenceImage>.from(_referenceImages),
        ),
      );
    }
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

  Future<void> _addReferenceImages() async {
    if (_pickingReferenceImages) return;
    setState(() => _pickingReferenceImages = true);
    try {
      final imported = await _referenceImageStore.pickAndImport(
        accountId: widget.accountId,
        orderId: _draftProductId,
      );
      if (!mounted) {
        if (imported.isNotEmpty) {
          await _referenceImageStore.deleteImages(
            accountId: widget.accountId,
            images: imported,
          );
        }
        return;
      }
      if (imported.isNotEmpty) {
        setState(() => _referenceImages.addAll(imported));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('添加参考图失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingReferenceImages = false);
    }
  }

  void _removeReferenceImage(OrderReferenceImage image) {
    setState(() {
      _referenceImages.removeWhere((item) => item.id == image.id);
    });
    unawaited(
      _referenceImageStore.deleteImages(
        accountId: widget.accountId,
        images: <OrderReferenceImage>[image],
      ),
    );
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
        id: _draftProductId,
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
        referenceImages: List<OrderReferenceImage>.unmodifiable(_referenceImages),
        defaultOrder: DateTime.now().microsecondsSinceEpoch,
      ),
    );
    _saved = true;
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
          TextButton(onPressed: _pickingReferenceImages ? null : _save, child: const Text('保存')),
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
              ButtonSegment(value: ProductSaleType.single, label: Text('单次售卖')),
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
          if (widget.featureStore.referenceImages) ...[
            const SizedBox(height: 14),
            OrderReferenceImagesSection(
              accountId: widget.accountId,
              images: _referenceImages,
              store: _referenceImageStore,
              editable: true,
              onAdd: _pickingReferenceImages
                  ? null
                  : () => unawaited(_addReferenceImages()),
              onRemove: _removeReferenceImage,
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
              onPressed: _pickingReferenceImages ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
