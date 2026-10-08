import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/portability/data_portability_file_bridge.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../products/domain/finished_product.dart';
import '../../products/state/product_store.dart';
import '../data/screenshot_ocr_service.dart';
import '../domain/screenshot_duplicate_review.dart';
import '../domain/screenshot_import_draft.dart';
import '../domain/screenshot_import_rules.dart';
import '../domain/screenshot_layout_parser.dart';
import '../domain/screenshot_product_layout_parser.dart';

enum ScreenshotImportKind { orders, products }

/// One preview across many images. The OCR engine never writes business data.
/// Every record is validated before one atomic store replacement.
class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({
    required this.kind,
    required this.orderStore,
    required this.productStore,
    required this.presetStore,
    super.key,
  });

  final ScreenshotImportKind kind;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore presetStore;

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _ocr = const ScreenshotOcrService();
  final _pick = const DataPortabilityFileBridge();
  final _ordersParser = const ScreenshotLayoutParser();
  final _productsParser = const ScreenshotProductLayoutParser();
  final List<ScreenshotImportDraft> _rows = [];
  int _imageSerial = 0;
  int _rowSerial = 0;
  bool _working = false;
  ProductSaleType _defaultSaleType = ProductSaleType.single;

  bool get _products => widget.kind == ScreenshotImportKind.products;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickAndRecognize() async {
    if (_working) return;
    if (!_ocr.supported) {
      _message('当前平台的离线 OCR 引擎仍在适配中；暂时请使用手动导入。');
      return;
    }

    try {
      final selected = await _pick.pickImages();
      if (selected.isEmpty) return;
      setState(() => _working = true);

      final generated = <ScreenshotImportDraft>[];
      var unreadable = 0;
      for (final image in selected) {
        final imageId = 'shot-' + (++_imageSerial).toString();
        try {
          final recognized = await _ocr.recognize(image.path);
          final guess = preselectImportPlatform(
            recognized.lines.map((line) => line.text),
          );
          final platform = guess.platform;
          if (_products) {
            final found = _productsParser.parse(
              lines: recognized.lines,
              imageHeight: recognized.height,
            );
            for (final candidate in found) {
              generated.add(_draft(
                imageId: imageId,
                title: candidate.title,
                client: '',
                price: candidate.price,
                platform: platform,
              ));
            }
          } else {
            final found = _ordersParser.parse(
              lines: recognized.lines,
              imageHeight: recognized.height,
              imageWidth: recognized.width,
            );
            for (final candidate in found) {
              generated.add(_draft(
                imageId: imageId,
                title: candidate.title,
                client: candidate.clientName,
                price: candidate.price,
                platform: platform,
                date: candidate.detectedDate,
                hasTime: candidate.deadlineHasTime,
                percentage: candidate.progressPercent,
                relative: candidate.relativeDeadlineText,
              ));
            }
          }
        } catch (_) {
          unreadable++;
        }
      }

      if (!mounted) return;
      setState(() {
        _rows.addAll(generated);
        _refreshDuplicateWarnings();
        _working = false;
      });
      if (generated.isEmpty) {
        _message('没有提取到可确认的单子，请换一张清晰的完整列表截图。');
      } else if (unreadable > 0) {
        _message('有 ' + unreadable.toString() + ' 张截图识别失败，其余已保留。');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      _message('读取截图失败：' + error.toString());
    }
  }

  ScreenshotImportDraft _draft({
    required String imageId,
    required String title,
    required String client,
    required double? price,
    required CommissionPlatform? platform,
    DateTime? date,
    bool hasTime = false,
    int? percentage,
    String? relative,
  }) {
    final suggestedPreset = platform == null
        ? widget.presetStore.presets.first
        : resolveImportPreset(
            platform: platform,
            title: title,
            presets: widget.presetStore.presets,
            existingOrders: widget.orderStore.orders,
          );
    final selectedNode = resolveImportNode(
      preset: suggestedPreset,
      recognizedPercent: percentage,
    );
    return ScreenshotImportDraft(
      id: 'preview-' + DateTime.now().microsecondsSinceEpoch.toString() +
          '-' + (++_rowSerial).toString(),
      sourceImageId: imageId,
      title: title,
      clientName: client,
      price: price,
      platform: platform,
      detectedDate: date,
      recognizedPercent: percentage,
      relativeDeadline: relative,
      deadline: hasTime ? date : null,
      deadlineConfirmed: hasTime,
      feeEnabled: platform?.defaultFeeEnabled ?? false,
      saleType: _defaultSaleType,
      presetId: suggestedPreset.id,
      nodeId: selectedNode.id,
    );
  }

  void _refreshDuplicateWarnings() {
    for (final row in _rows) {
      row.duplicateWarning = null;
    }
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      final platform = row.platform;
      if (platform == null || row.title.trim().isEmpty) continue;
      if (_products) {
        final duplicateInStore = widget.productStore.products.any(
          (existing) => existing.platform == platform &&
              normalizedImportTitle(existing.title) ==
                  normalizedImportTitle(row.title),
        );
        final duplicateInPreview = _rows.take(index).any(
          (other) => other.platform == platform &&
              normalizedImportTitle(other.title) ==
                  normalizedImportTitle(row.title),
        );
        if (duplicateInStore || duplicateInPreview) {
          row.duplicateWarning = duplicateInStore
              ? '已有同名成品，默认跳过' : '本批次同名橱窗，默认跳过';
          row.selected = false;
        }
        continue;
      }
      final existing = widget.orderStore.orders.any((order) =>
          order.platform == platform &&
          normalizedImportTitle(order.title) ==
              normalizedImportTitle(row.title) &&
          normalizedImportTitle(order.clientName) ==
              normalizedImportTitle(row.clientName) &&
          row.clientName.trim().isNotEmpty &&
          row.detectedDate != null &&
          order.deadline != null &&
          _sameDay(order.deadline!, row.detectedDate!));
      var acrossScreenshots = false;
      for (final other in _rows.take(index)) {
        if (other.platform == null || other.platform != platform) continue;
        final comparison = reviewScreenshotDuplicate(
          ScreenshotImportIdentity(
            platform: platform,
            title: row.title,
            clientName: row.clientName,
            imageInstanceId: row.sourceImageId,
            cardInstanceId: row.id,
            sourceDate: row.detectedDate,
            datePrecision: row.deadlineConfirmed
                ? ScreenshotDatePrecision.minute
                : ScreenshotDatePrecision.day,
          ),
          ScreenshotImportIdentity(
            platform: other.platform!,
            title: other.title,
            clientName: other.clientName,
            imageInstanceId: other.sourceImageId,
            cardInstanceId: other.id,
            sourceDate: other.detectedDate,
            datePrecision: other.deadlineConfirmed
                ? ScreenshotDatePrecision.minute
                : ScreenshotDatePrecision.day,
          ),
        );
        if (comparison == ScreenshotDuplicateReview.possibleDuplicate ||
            comparison == ScreenshotDuplicateReview.insufficientEvidence) {
          acrossScreenshots = true;
          break;
        }
      }
      if (existing || acrossScreenshots) {
        row.duplicateWarning = existing
            ? '与已有排单疑似重复' : '与其他截图的排单疑似重复';
        row.selected = false;
      }
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _editDeadline(ScreenshotImportDraft row) async {
    final basis = row.deadline ?? row.detectedDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: basis,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(basis),
    );
    if (!mounted || time == null) return;
    setState(() {
      row.deadline = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
      row.deadlineConfirmed = true;
    });
  }

  void _changePlatform(ScreenshotImportDraft row, CommissionPlatform value) {
    setState(() {
      row.platform = value;
      row.feeEnabled = value.defaultFeeEnabled;
      if (!_products && !row.presetManuallyChanged) {
        final preset = resolveImportPreset(
          platform: value,
          title: row.title,
          presets: widget.presetStore.presets,
          existingOrders: widget.orderStore.orders,
        );
        row.presetId = preset.id;
        row.nodeId = resolveImportNode(
          preset: preset,
          recognizedPercent: row.recognizedPercent,
        ).id;
      }
      _refreshDuplicateWarnings();
    });
  }

  Future<void> _confirm() async {
    final selected = _rows.where((row) => row.selected).toList();
    if (selected.isEmpty) {
      _message('没有选中要导入的记录');
      return;
    }
    for (final row in selected) {
      final issue = row.validate(importingProducts: _products);
      if (issue != null) {
        _message('「' + row.title + '」：' + issue);
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认批量导入？'),
        content: Text('将新增 ' + selected.length.toString() +
            ' 条' + (_products ? '成品' : '排单') +
            '。重复项只有手动勾选才会导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    if (_products) {
      final created = <FinishedProduct>[];
      final keys = <String>{};
      for (var i = 0; i < selected.length; i++) {
        final row = selected[i];
        final key = orderPresetMemoryKey(row.platform!, row.title);
        if (!keys.add(key)) continue; // one product per storefront
        created.add(FinishedProduct(
          id: 'product-import-' + (now + i).toString(),
          title: row.title.trim(),
          platform: row.platform!,
          saleType: row.saleType,
          price: row.price!,
          feeEnabled: row.feeEnabled,
          supplementFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          deductionFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          defaultOrder: now + i,
          // A storefront screenshot is NOT an individual sale.
          soldCount: 0,
          saleRecords: const [],
        ));
      }
      widget.productStore.replaceAll([
        ...widget.productStore.products,
        ...created,
      ]);
    } else {
      final created = <QueueOrder>[];
      for (var i = 0; i < selected.length; i++) {
        final row = selected[i];
        final preset = widget.presetStore.byId(row.presetId);
        created.add(QueueOrder(
          id: 'order-import-' + (now + i).toString(),
          title: row.title.trim(),
          clientName: row.clientName.trim(),
          platform: row.platform!,
          deadline: row.deadline,
          nodePresetId: preset.id,
          nodePresetSnapshot: preset.snapshot(),
          currentNodeId: row.nodeId,
          price: row.price!,
          feeEnabled: row.feeEnabled,
          supplementFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          deductionFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          defaultOrder: now + i,
        ));
      }
      widget.orderStore.replaceAll([
        ...widget.orderStore.orders,
        ...created,
      ]);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final count = _rows.where((r) => r.selected).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_products ? '截图导入成品' : '截图导入排单'),
        actions: [
          TextButton.icon(
            onPressed: _working ? null : _pickAndRecognize,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('选择截图'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_working) const LinearProgressIndicator(),
          if (_products)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<ProductSaleType>(
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
                selected: {_defaultSaleType},
                onSelectionChanged: (selection) => setState(() {
                  _defaultSaleType = selection.first;
                  for (final row in _rows) {
                    row.saleType = _defaultSaleType;
                  }
                }),
              ),
            ),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已识别 ' + _rows.length.toString() +
                          ' 条，选中 ' + count.toString() + ' 条',
                    ),
                  ),
                  PopupMenuButton<CommissionPlatform>(
                    tooltip: '批量设置平台',
                    onSelected: (value) => setState(() {
                      for (final row in _rows) {
                        row.platform = value;
                        row.feeEnabled = value.defaultFeeEnabled;
                      }
                      _refreshDuplicateWarnings();
                    }),
                    itemBuilder: (context) => [
                      for (final platform in CommissionPlatform.values)
                        PopupMenuItem(
                          value: platform,
                          child: Text(platform.label),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('批量设平台 ▾'),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _working
                            ? '正在本机识别截图…'
                            : '选择一张或多张平台订单截图，先识别并检查，确认后才会写入。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) =>
                        _buildRow(_rows[index], index),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: FilledButton.icon(
          onPressed: _working || count == 0 ? null : _confirm,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text('确认导入（' + count.toString() + '）'),
        ),
      ),
    );
  }

  Widget _buildRow(ScreenshotImportDraft row, int index) {
    final theme = Theme.of(context);
    final preset = widget.presetStore.byId(row.presetId);
    final dateValue = row.deadline;
    final dateLabel = dateValue == null
        ? (row.detectedDate == null ? '截稿时间待补充'
            : '已识别日期，时间待确认')
        : dateValue.year.toString() + '-' +
            dateValue.month.toString().padLeft(2, '0') + '-' +
            dateValue.day.toString().padLeft(2, '0') + ' ' +
            dateValue.hour.toString().padLeft(2, '0') + ':' +
            dateValue.minute.toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 5, 9, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.selected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (checked) =>
                      setState(() => row.selected = checked ?? false),
                ),
                Expanded(
                  child: Text(
                    '识别 ' + (index + 1).toString() +
                        (row.duplicateWarning == null
                            ? ' · 待确认' : ' · 疑似重复'),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  tooltip: '删除这条识别结果',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _rows.remove(row)),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
            if (row.duplicateWarning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  row.duplicateWarning! + '（勾选可仍然导入）',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            TextFormField(
              key: ValueKey(row.id + '-title'),
              initialValue: row.title,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: '图名', isDense: true,
              ),
              onChanged: (value) => row.title = value,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (!_products) ...[
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: ValueKey(row.id + '-client'),
                      initialValue: row.clientName,
                      decoration: const InputDecoration(
                        labelText: '单主', isDense: true,
                      ),
                      onChanged: (value) => row.clientName = value,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: TextFormField(
                    key: ValueKey(row.id + '-price'),
                    initialValue: row.price?.toString() ?? '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '稿价 ¥', isDense: true,
                    ),
                    onChanged: (value) => row.price =
                        double.tryParse(value.trim()),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<CommissionPlatform>(
                    key: ValueKey(row.id + '-platform-' +
                        (row.platform?.name ?? 'unknown')),
                    initialValue: row.platform,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '平台', isDense: true,
                    ),
                    hint: const Text('请选择'),
                    items: [
                      for (final p in CommissionPlatform.values)
                        DropdownMenuItem(
                          value: p, child: Text(p.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _changePlatform(row, value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_products)
              Row(
                children: [
                  Expanded(
                    child: Text('成品不自动记录售出次数',
                        style: theme.textTheme.bodySmall),
                  ),
                  DropdownButton<ProductSaleType>(
                    value: row.saleType,
                    isDense: true,
                    items: [
                      for (final type in ProductSaleType.values)
                        DropdownMenuItem(
                          value: type, child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => row.saleType = value);
                      }
                    },
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_editDeadline(row)),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(dateLabel),
                  ),
                  if (!row.deadlineConfirmed &&
                      row.detectedDate != null &&
                      row.relativeDeadline == null &&
                      row.platform == CommissionPlatform.mihuashi)
                    TextButton(
                      onPressed: () => setState(() {
                        final d = row.detectedDate!;
                        row.deadline = DateTime(d.year, d.month, d.day, 23, 59);
                        row.deadlineConfirmed = true;
                      }),
                      child: const Text('确认普通按日 23:59'),
                    ),
                  if (!row.deadlineConfirmed)
                    TextButton(
                      onPressed: () => setState(() {
                        row.deadline = null;
                        row.deadlineConfirmed = true;
                      }),
                      child: const Text('主动设为未设置'),
                    ),
                  if (row.relativeDeadline != null)
                    Text(
                      row.relativeDeadline!,
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(row.id + '-preset-' + row.presetId),
                      initialValue: row.presetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '节点预设', isDense: true,
                      ),
                      items: [
                        for (final choice in widget.presetStore.presets)
                          DropdownMenuItem(
                            value: choice.id, child: Text(choice.name),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() => cascadeScreenshotPreset(
                          changed: row,
                          rows: _rows,
                          selectedPreset: widget.presetStore.byId(id),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(row.id + '-node-' + row.nodeId),
                      initialValue: row.nodeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '当前节点', isDense: true,
                      ),
                      items: [
                        for (final node in preset.nodes)
                          DropdownMenuItem(
                            value: node.id,
                            child: Text(node.name + ' ' +
                                node.progressPercent.toString() + '%'),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          row.nodeId = id;
                          row.nodeManuallyChanged = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
            Row(
              children: [
                const Text('收取平台手续费', style: TextStyle(fontSize: 12)),
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: row.feeEnabled,
                  onChanged: (value) =>
                      setState(() => row.feeEnabled = value ?? false),
                ),
                const Spacer(),
                if (row.recognizedPercent != null && !_products)
                  Text('截图进度 ' +
                      row.recognizedPercent.toString() + '%',
                      style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
