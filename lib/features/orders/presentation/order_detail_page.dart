import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/adjustment_widgets.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../data/node_presets.dart';
import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';
import '../state/order_store.dart';
import 'order_reference_image_widgets.dart';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    required this.accountId,
    required this.store,
    required this.orderId,
    required this.nodePresetStore,
    required this.featureStore,
    super.key,
  });

  final String accountId;
  final OrderStore store;
  final String orderId;
  final NodePresetStore nodePresetStore;
  final AppFeatureStore featureStore;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final _referenceImageStore = OrderReferenceImageStore();
  final _referenceImages = <OrderReferenceImage>[];
  final _sessionAddedReferenceImages = <OrderReferenceImage>[];

  bool _editing = false;
  bool _pickingReferenceImages = false;

  late final TextEditingController _titleController;
  late final TextEditingController _clientController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _onlineController;
  late final TextEditingController _offlineController;

  late CommissionPlatform _platform;
  late String _presetId;
  late NodePreset _presetSnapshot;
  late String _currentNodeId;
  DateTime? _deadline;
  late QueueOrder _draftBaseline;

  bool _feeEnabled = false;
  HuajiaLoveLevel _huajiaLoveLevel = HuajiaLoveLevel.none;
  double _onlinePercent = 100;

  QueueOrder get _order => widget.store.byId(widget.orderId);

  @override
  void initState() {
    super.initState();
    final order = _order;
    _titleController = TextEditingController();
    _clientController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();
    _onlineController = TextEditingController();
    _offlineController = TextEditingController();
    _loadDraft(order);
  }

  @override
  void dispose() {
    if (_sessionAddedReferenceImages.isNotEmpty) {
      unawaited(
        _referenceImageStore.deleteImages(
          accountId: widget.accountId,
          images: List<OrderReferenceImage>.from(
            _sessionAddedReferenceImages,
          ),
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

  void _loadDraft(QueueOrder order) {
    _draftBaseline = order;
    _titleController.text = order.title;
    _clientController.text = order.clientName;
    _priceController.text = order.price == 0 ? '' : _formatPrice(order.price);
    _descriptionController.text = order.description;
    _referenceImages
      ..clear()
      ..addAll(order.referenceImages);
    _platform = order.platform;
    _presetId = order.nodePresetId;
    _presetSnapshot = order.nodePresetSnapshot.snapshot();
    _currentNodeId = order.currentNodeId;
    _deadline = order.deadline;
    _feeEnabled = order.feeEnabled;
    _huajiaLoveLevel = order.huajiaLoveLevel;
    _onlinePercent = order.normalizedOnlinePercent;
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
    _sessionAddedReferenceImages.clear();
    _loadDraft(_order);
    setState(() => _editing = true);
  }

  Future<void> _cancelEditing() async {
    final added = List<OrderReferenceImage>.from(
      _sessionAddedReferenceImages,
    );
    _sessionAddedReferenceImages.clear();
    if (added.isNotEmpty) {
      await _referenceImageStore.deleteImages(
        accountId: widget.accountId,
        images: added,
      );
    }
    if (!mounted) return;
    _loadDraft(_order);
    setState(() => _editing = false);
  }

  Future<void> _addReferenceImages() async {
    if (_pickingReferenceImages) return;
    setState(() => _pickingReferenceImages = true);

    try {
      final accountId = widget.accountId;
      final imported = await _referenceImageStore.pickAndImport(
        accountId: accountId,
        orderId: widget.orderId,
      );
      if (!mounted || !_editing) {
        if (imported.isNotEmpty) {
          await _referenceImageStore.deleteImages(
            accountId: accountId,
            images: imported,
          );
        }
        return;
      }
      if (imported.isEmpty) return;
      setState(() {
        _referenceImages.addAll(imported);
        _sessionAddedReferenceImages.addAll(imported);
      });
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

    final addedIndex = _sessionAddedReferenceImages.indexWhere(
      (item) => item.id == image.id,
    );
    if (addedIndex != -1) {
      final added = _sessionAddedReferenceImages.removeAt(addedIndex);
      unawaited(
        _referenceImageStore.deleteImages(
          accountId: widget.accountId,
          images: <OrderReferenceImage>[added],
        ),
      );
    }
  }

  bool _sameReferenceImages(
    List<OrderReferenceImage> left,
    List<OrderReferenceImage> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.fileName != b.fileName ||
          a.relativePath != b.relativePath ||
          a.addedAt != b.addedAt ||
          a.sizeBytes != b.sizeBytes) {
        return false;
      }
    }
    return true;
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    final current = _order;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final titleChanged = _titleController.text.trim() != _draftBaseline.title;
    final clientChanged =
        _clientController.text.trim() != _draftBaseline.clientName;
    final platformChanged = _platform != _draftBaseline.platform;
    final deadlineChanged = _deadline != _draftBaseline.deadline;
    final presetChanged = _presetId != _draftBaseline.nodePresetId;
    final nodeChanged =
        _currentNodeId != _draftBaseline.currentNodeId || presetChanged;
    final descriptionChanged =
        _descriptionController.text.trim() != _draftBaseline.description;
    final priceChanged = price != _draftBaseline.price;
    final feeChanged = _feeEnabled != _draftBaseline.feeEnabled;
    final loveLevelChanged = _huajiaLoveLevel != _draftBaseline.huajiaLoveLevel;
    final onlinePercentChanged =
        _onlinePercent != _draftBaseline.normalizedOnlinePercent;
    final referenceImagesChanged = !_sameReferenceImages(
      _referenceImages,
      _draftBaseline.referenceImages,
    );
    final removedReferenceImages = referenceImagesChanged
        ? <OrderReferenceImage>[
            for (final image in _draftBaseline.referenceImages)
              if (!_referenceImages.any((item) => item.id == image.id)) image,
          ]
        : const <OrderReferenceImage>[];
    final reopenDeliveredOrder =
        current.isCompleted && !current.isArchived && nodeChanged;

    final updated = current.copyWith(
      title: titleChanged ? _titleController.text.trim() : current.title,
      clientName: clientChanged
          ? _clientController.text.trim()
          : current.clientName,
      platform: platformChanged ? _platform : current.platform,
      deadline: deadlineChanged ? _deadline : current.deadline,
      clearDeadline: deadlineChanged && _deadline == null,
      nodePresetId: presetChanged ? _presetId : current.nodePresetId,
      nodePresetSnapshot: presetChanged
          ? _presetSnapshot.snapshot()
          : current.nodePresetSnapshot,
      currentNodeId: nodeChanged ? _currentNodeId : current.currentNodeId,
      currentNodeProgress: nodeChanged ? 0 : current.currentNodeProgress,
      clearCompletedAt: reopenDeliveredOrder,
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
      referenceImages: referenceImagesChanged
          ? List<OrderReferenceImage>.unmodifiable(_referenceImages)
          : current.referenceImages,
    );

    widget.store.updateOrder(updated);
    _sessionAddedReferenceImages.clear();
    if (removedReferenceImages.isNotEmpty) {
      unawaited(
        _referenceImageStore.deleteImages(
          accountId: widget.accountId,
          images: removedReferenceImages,
        ),
      );
    }
    setState(() => _editing = false);
  }

  Future<void> _editSupplement(QueueOrder order) async {
    final result = await showAdjustmentDialog(
      context: context,
      label: '补款',
      amount: order.supplementAmount,
      feeEnabled: order.supplementFeeEnabled,
    );
    if (!mounted || result == null) return;

    final current = widget.store.byId(widget.orderId);
    widget.store.updateOrder(
      current.copyWith(
        supplementAmount: result.amount,
        supplementFeeEnabled: result.feeEnabled,
      ),
    );
  }

  Future<void> _editDeduction(QueueOrder order) async {
    final result = await showAdjustmentDialog(
      context: context,
      label: '减款',
      amount: order.deductionAmount,
      feeEnabled: order.deductionFeeEnabled,
    );
    if (!mounted || result == null) return;

    final current = widget.store.byId(widget.orderId);
    widget.store.updateOrder(
      current.copyWith(
        deductionAmount: result.amount,
        deductionFeeEnabled: result.feeEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.featureStore]),
      builder: (context, _) {
        if (!widget.store.contains(widget.orderId)) {
          return const Scaffold();
        }

        final order = _order;
        final preset = order.nodePresetSnapshot;
        final node = order.currentNode;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              '订单详情',
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
                  onPressed: _pickingReferenceImages
                      ? null
                      : () => unawaited(_cancelEditing()),
                  icon: const Icon(Icons.close_rounded),
                ),
                IconButton(
                  tooltip: '保存',
                  onPressed: _pickingReferenceImages ? null : _save,
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
                ReadOnlyDetailRow(label: '图名', value: order.title),
                if (widget.featureStore.clientInfo)
                  ReadOnlyDetailRow(
                    label: '单主',
                    value: order.clientName.isEmpty ? '未填写' : order.clientName,
                  ),
                ReadOnlyDetailRow(label: '平台', value: order.platform.label),
                ReadOnlyDetailRow(
                  label: '截稿时间',
                  value: order.deadline == null
                      ? '未设置'
                      : formatDateTimeValue(order.deadline!),
                ),
                ReadOnlyDetailRow(
                  label: '节点',
                  value:
                      '${preset.name} · ${node.name} ${node.progressPercent}%',
                ),
                ReadOnlyDetailRow(
                  label: '原始稿价',
                  value: order.price == 0
                      ? '未填写'
                      : '¥ ${_formatPrice(order.price)}',
                ),
                ReadOnlyDetailRow(
                  label: '手续费',
                  value: order.feeEnabled
                      ? '开启 · ¥ ${_formatPrice(order.serviceFeeAmount)}'
                      : '关闭',
                ),
                if (order.platform == CommissionPlatform.huajia &&
                    order.feeEnabled)
                  ReadOnlyDetailRow(
                    label: '真爱永恒',
                    value: order.huajiaLoveLevel == HuajiaLoveLevel.none
                        ? '无折扣'
                        : '${order.huajiaLoveLevel.label} · '
                              '手续费${(order.huajiaLoveLevel.feeMultiplier * 10).toStringAsFixed(0)}折',
                  ),
                if (order.platform.usesOnlineOfflineSplit)
                  ReadOnlyDetailRow(
                    label: '线上/线下',
                    value:
                        '${formatPercentValue(order.normalizedOnlinePercent)}% / '
                        '${formatPercentValue(order.offlinePercent)}%',
                  ),
                AdjustmentDetailRow(
                  label: '补款',
                  amount: order.supplementAmount,
                  feeEnabled: order.supplementFeeEnabled,
                  sign: '+',
                  onTap: () => _editSupplement(order),
                ),
                AdjustmentDetailRow(
                  label: '减款',
                  amount: order.deductionAmount,
                  feeEnabled: order.deductionFeeEnabled,
                  sign: '-',
                  onTap: () => _editDeduction(order),
                ),
                ReadOnlyDetailRow(
                  label: '真实收入',
                  value: '¥ ${_formatPrice(order.realIncome)}',
                ),
                if (order.archiveOutcome != null) ...[
                  ReadOnlyDetailRow(
                    label: '归档结果',
                    value: order.archiveOutcome!.label,
                  ),
                  if (order.archiveOutcome == OrderArchiveOutcome.terminated &&
                      order.settlementNode != null)
                    ReadOnlyDetailRow(
                      label: '结算节点',
                      value:
                          '${order.settlementNode!.name} · '
                          '${order.settlementNode!.progressPercent}%',
                    ),
                  if (order.archiveOutcome == OrderArchiveOutcome.terminated &&
                      order.customRefundAmount != null)
                    ReadOnlyDetailRow(
                      label: '退款金额',
                      value:
                          '¥ ${_formatPrice(order.customRefundAmount!)} · 自定义退款',
                    ),
                  ReadOnlyDetailRow(
                    label: '最终收入',
                    value: '¥ ${_formatPrice(order.settlementIncome)}',
                  ),
                  if (order.completedAt != null)
                    ReadOnlyDetailRow(
                      label: '归档时间',
                      value: formatDateTimeValue(order.completedAt!),
                    ),
                ] else
                  ReadOnlyDetailRow(
                    label: '交稿状态',
                    value: order.completedAt == null
                        ? '待交稿'
                        : '已交稿 · ${formatDateTimeValue(order.completedAt!)}',
                  ),
                const SizedBox(height: 8),
                OrderReferenceImagesSection(
                  accountId: widget.accountId,
                  images: order.referenceImages,
                  store: _referenceImageStore,
                ),
                const SizedBox(height: 8),
                ReadOnlyDetailRow(
                  label: '描述',
                  value: order.description.trim().isEmpty
                      ? '未填写'
                      : order.description,
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
                if (widget.featureStore.clientInfo) ...[
                  const SizedBox(height: 14),
                  const FormFieldLabel('单主'),
                  TextField(controller: _clientController),
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
                const FormFieldLabel('截稿时间'),
                DateTimePickerButton(
                  value: _deadline,
                  onChanged: (value) => setState(() => _deadline = value),
                ),
                const SizedBox(height: 14),
                const FormFieldLabel('节点预设'),
                DropdownButtonFormField<String>(
                  initialValue: _presetId,
                  items: [
                    if (!widget.nodePresetStore.presets.any(
                      (preset) => preset.id == _presetId,
                    ))
                      DropdownMenuItem(
                        value: _presetId,
                        child: Text('${_presetSnapshot.name}（旧订单快照）'),
                      ),
                    ...widget.nodePresetStore.presets.map(
                      (preset) => DropdownMenuItem(
                        value: preset.id,
                        child: Text(preset.name),
                      ),
                    ),
                  ],
                  selectedItemBuilder: (context) {
                    final currentPresetStillExists = widget
                        .nodePresetStore
                        .presets
                        .any((preset) => preset.id == _presetId);

                    return [
                      if (!currentPresetStillExists)
                        Text('${_presetSnapshot.name}（旧订单快照）'),
                      ...widget.nodePresetStore.presets.map(
                        (preset) => Text(
                          preset.id == _presetId
                              ? _presetSnapshot.name
                              : preset.name,
                        ),
                      ),
                    ];
                  },
                  onChanged: (value) {
                    if (value == null) return;

                    final presetChanged = value != _presetId;
                    final selected = widget.nodePresetStore
                        .byId(value)
                        .snapshot();
                    final currentNodeStillExists = selected.nodes.any(
                      (node) => node.id == _currentNodeId,
                    );

                    setState(() {
                      _presetId = value;
                      _presetSnapshot = selected;
                      _currentNodeId = !presetChanged && currentNodeStillExists
                          ? _currentNodeId
                          : selected.nodes.first.id;
                    });
                  },
                ),
                const SizedBox(height: 14),
                const FormFieldLabel('当前节点'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _presetSnapshot.nodes)
                      ChoiceChip(
                        label: Text('${item.name} ${item.progressPercent}%'),
                        selected: _currentNodeId == item.id,
                        onSelected: (_) {
                          setState(() => _currentNodeId = item.id);
                        },
                      ),
                  ],
                ),
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
                const SizedBox(height: 14),
                const FormFieldLabel('描述'),
                TextField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(hintText: '订单内容、要求或备注'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _pickingReferenceImages ? null : _save,
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

  String _formatPrice(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}
