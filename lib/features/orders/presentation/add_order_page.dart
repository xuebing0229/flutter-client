import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../data/node_presets.dart';
import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';
import '../state/order_store.dart';
import 'order_reference_image_widgets.dart';

class AddOrderPage extends StatefulWidget {
  const AddOrderPage({
    required this.accountId,
    required this.store,
    required this.nodePresetStore,
    required this.featureStore,
    super.key,
  });

  final String accountId;
  final OrderStore store;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;

  @override
  State<AddOrderPage> createState() => _AddOrderPageState();
}

class _AddOrderPageState extends State<AddOrderPage> {
  final _referenceImageStore = OrderReferenceImageStore();
  final _referenceImages = <OrderReferenceImage>[];

  final _titleController = TextEditingController();
  final _clientController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _onlineController = TextEditingController(text: '100');
  final _offlineController = TextEditingController(text: '0');

  CommissionPlatform _platform = CommissionPlatform.mihuashi;
  bool _feeEnabled = CommissionPlatform.mihuashi.defaultFeeEnabled;
  HuajiaLoveLevel _huajiaLoveLevel = HuajiaLoveLevel.none;
  double _onlinePercent = 100;
  String _presetId = defaultNodePreset.id;
  late String _currentNodeId;
  DateTime? _deadline;
  late final String _draftOrderId;
  bool _saved = false;
  bool _pickingReferenceImages = false;

  @override
  void initState() {
    super.initState();
    _draftOrderId = 'order-${DateTime.now().microsecondsSinceEpoch}';
    final preset = widget.nodePresetStore.byId(_presetId);
    _currentNodeId = preset.nodes.first.id;
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
    _clientController.dispose();
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
      final accountId = widget.accountId;
      final imported = await _referenceImageStore.pickAndImport(
        accountId: accountId,
        orderId: _draftOrderId,
      );
      if (!mounted) {
        if (imported.isNotEmpty) {
          await _referenceImageStore.deleteImages(
            accountId: accountId,
            images: imported,
          );
        }
        return;
      }
      if (imported.isEmpty) return;
      setState(() => _referenceImages.addAll(imported));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('添加参考图失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pickingReferenceImages = false);
      }
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
    final client = _clientController.text.trim();

    if (title.isEmpty ||
        (widget.featureStore.clientInfo && client.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.featureStore.clientInfo
                ? '图名和单主需要填写'
                : '图名需要填写',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final preset = widget.nodePresetStore.byId(_presetId).snapshot();
    final currentNodeId = preset.nodes.any((node) => node.id == _currentNodeId)
        ? _currentNodeId
        : preset.nodes.first.id;

    final order = QueueOrder(
      id: _draftOrderId,
      platform: _platform,
      title: title,
      clientName: client,
      deadline: _deadline,
      nodePresetId: _presetId,
      nodePresetSnapshot: preset,
      currentNodeId: currentNodeId,
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      feeEnabled: _feeEnabled,
      huajiaLoveLevel: _huajiaLoveLevel,
      onlinePercent: _onlinePercent,
      supplementFeeEnabled: _platform.defaultAdjustmentFeeEnabled,
      deductionFeeEnabled: _platform.defaultAdjustmentFeeEnabled,
      description: _descriptionController.text.trim(),
      defaultOrder: DateTime.now().microsecondsSinceEpoch,
      referenceImages: List<OrderReferenceImage>.unmodifiable(
        _referenceImages,
      ),
    );

    _saved = true;
    widget.store.addOrder(order);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.nodePresetStore.byId(_presetId);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '新增排单',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _pickingReferenceImages ? null : _save,
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
            textInputAction: TextInputAction.next,
          ),
          if (widget.featureStore.clientInfo) ...[
            const SizedBox(height: 14),
            const FormFieldLabel('单主'),
            TextField(
              controller: _clientController,
              textInputAction: TextInputAction.next,
            ),
          ],
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
          const FormFieldLabel('截稿时间'),
          DateTimePickerButton(
            value: _deadline,
            onChanged: (value) => setState(() => _deadline = value),
          ),
          const SizedBox(height: 14),
          const FormFieldLabel('节点预设'),
          DropdownButtonFormField<String>(
            initialValue: _presetId,
            items: widget.nodePresetStore.presets
                .map(
                  (preset) => DropdownMenuItem(
                    value: preset.id,
                    child: Text(preset.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                final selectedPreset = widget.nodePresetStore.byId(value);
                setState(() {
                  _presetId = value;
                  _currentNodeId = selectedPreset.nodes.first.id;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          const FormFieldLabel('当前节点'),
          _NodeChoices(
            preset: preset,
            currentNodeId: _currentNodeId,
            onChanged: (nodeId) {
              setState(() => _currentNodeId = nodeId);
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
            decoration: const InputDecoration(
              hintText: '订单内容、要求或备注',
            ),
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

class _NodeChoices extends StatelessWidget {
  const _NodeChoices({
    required this.preset,
    required this.currentNodeId,
    required this.onChanged,
  });

  final NodePreset preset;
  final String currentNodeId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final node in preset.nodes)
          ChoiceChip(
            label: Text('${node.name} ${node.progressPercent}%'),
            selected: currentNodeId == node.id,
            onSelected: (_) => onChanged(node.id),
          ),
      ],
    );
  }
}
