import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/detail_form_widgets.dart';
import '../../../core/finance/pricing_adjustments.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../shared/presentation/pricing_preset_selector.dart';
import '../../shared/presentation/spotlight_guide.dart';
import '../data/node_presets.dart';
import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';
import '../state/order_store.dart';
import 'order_reference_image_widgets.dart';
import 'order_tags_editor.dart';

class AddOrderPage extends StatefulWidget {
  const AddOrderPage({
    required this.accountId,
    required this.store,
    required this.nodePresetStore,
    required this.featureStore,
    this.pricingPresetStore,
    this.guideTargets,
    super.key,
  });

  final String accountId;
  final OrderStore store;
  final NodePresetStore nodePresetStore;
  final PricingPresetStore? pricingPresetStore;
  final AppFeatureStore featureStore;
  final QuickStartGuideTargets? guideTargets;

  @override
  State<AddOrderPage> createState() => _AddOrderPageState();
}

class _AddOrderPageState extends State<AddOrderPage> {
  final _referenceImageStore = OrderReferenceImageStore();
  final _referenceImages = <OrderReferenceImage>[];
  final _tags = <String>[];
  final _pricingAdjustments = <PricingAdjustment>[];
  late final PricingPresetStore _effectivePricingPresetStore;

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
    _effectivePricingPresetStore =
        widget.pricingPresetStore ?? PricingPresetStore();
    _draftOrderId = 'order-${DateTime.now().microsecondsSinceEpoch}';
    final preset = widget.nodePresetStore.byId(_presetId);
    _currentNodeId = preset.nodes.first.id;
    if (widget.guideTargets != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showGuide());
      });
    }
  }

  Future<void> _showGuide() async {
    final targets = widget.guideTargets;
    if (targets == null || !mounted) return;
    final theme = Theme.of(context);
    final saveShape =
        TextButtonTheme.of(context).style?.shape?.resolve(const <WidgetState>{}) ??
        (theme.useMaterial3
            ? const StadiumBorder()
            : const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ));
    await showSpotlightGuide(
      context,
      steps: [
        SpotlightGuideStep(
          targetKey: targets.addOrderTitleKey,
          icon: Icons.title_rounded,
          title: '先填图名',
          body: '图名是这笔排单最主要的识别信息，之后搜索和小票都会用到。',
          targetPadding: 0,
          borderRadius: 0,
        ),
        if (widget.featureStore.clientInfo)
          SpotlightGuideStep(
            targetKey: targets.addOrderClientKey,
            icon: Icons.person_outline_rounded,
            title: '再记下单主',
            body: '单主信息可以用于搜索，也会用于按单主生成年度小票。',
            targetPadding: 0,
            borderRadius: 0,
          ),
        SpotlightGuideStep(
          targetKey: targets.addOrderPlatformKey,
          icon: Icons.storefront_outlined,
          title: '选择平台',
          body: '平台会影响手续费规则，也会用于后续统计和筛选。',
          targetPadding: 0,
          borderRadius: 0,
        ),
        SpotlightGuideStep(
          targetKey: targets.addOrderPriceKey,
          icon: Icons.payments_outlined,
          title: '填写原始稿价',
          body: '这里填写基础稿价；加价预设和其他调整项会在此基础上计算。',
          targetPadding: 0,
          borderRadius: 0,
        ),
        SpotlightGuideStep(
          targetKey: targets.addOrderSaveKey,
          icon: Icons.check_rounded,
          title: '填完后保存',
          body: '基础信息确认后就可以保存，截稿、节点、参考图、标签等都可以继续补充。',
          targetShape: saveShape,
          targetPadding: 0,
        ),
      ].where((step) => step.targetKey.currentContext != null).toList(),
    );
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
            key: widget.guideTargets?.addOrderSaveKey,
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
            key: widget.guideTargets?.addOrderTitleKey,
            controller: _titleController,
            textInputAction: TextInputAction.next,
          ),
          if (widget.featureStore.clientInfo) ...[
            const SizedBox(height: 14),
            const FormFieldLabel('单主'),
            TextField(
              key: widget.guideTargets?.addOrderClientKey,
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
            platformKey: widget.guideTargets?.addOrderPlatformKey,
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
                  key: widget.guideTargets?.addOrderPriceKey,
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
          PricingPresetSelector(
            store: _effectivePricingPresetStore,
            selected: _pricingAdjustments,
            onChanged: (value) => setState(() {
              _pricingAdjustments
                ..clear()
                ..addAll(value);
            }),
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
          if (widget.featureStore.customTags) ...[
            const SizedBox(height: 14),
            OrderTagsEditor(
              selectedTags: _tags,
              availableTags: widget.store.orders.expand((order) => order.tags),
              onChanged: (tags) => setState(() {
                _tags..clear()..addAll(tags);
              }),
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
