import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/finance/pricing_adjustments.dart';
import '../../orders/domain/queue_order.dart';
import '../../products/domain/finished_product.dart';
import '../../home/presentation/theme_color_picker.dart';
import '../data/receipt_style_image_bridge.dart';
import '../domain/receipt_style_store.dart';
import '../domain/receipt_style_transfer.dart';
import 'layout_spacing.dart';
import 'receipt_style_share_image_page.dart';

class ReceiptData {
  const ReceiptData({
    required this.kindLabel,
    required this.title,
    required this.platform,
    required this.basePrice,
    required this.pricingAdjustments,
    required this.supplementAmount,
    required this.pricedSupplementAmount,
    required this.supplementPricingEnabled,
    required this.deductionAmount,
    required this.total,
    this.clientName,
  });

  factory ReceiptData.fromOrder(QueueOrder order) => ReceiptData(
        kindLabel: '排单',
        title: order.title,
        clientName: order.clientName,
        platform: order.platform.label,
        basePrice: order.price,
        pricingAdjustments: [
          for (final item in order.pricingAdjustments) item.snapshot(),
        ],
        supplementAmount: order.supplementAmount,
        pricedSupplementAmount: order.pricedSupplementAmountValue,
        supplementPricingEnabled: order.supplementPricingEnabled,
        deductionAmount: order.deductionAmount,
        total: order.originalTotal,
      );

  factory ReceiptData.fromProduct(FinishedProduct product) => ReceiptData(
        kindLabel: '成品',
        title: product.title,
        platform: product.platform.label,
        basePrice: product.price,
        pricingAdjustments: [
          for (final item in product.pricingAdjustments) item.snapshot(),
        ],
        supplementAmount: product.supplementAmount,
        pricedSupplementAmount: product.pricedSupplementAmountValue,
        supplementPricingEnabled: product.supplementPricingEnabled,
        deductionAmount: product.deductionAmount,
        total: product.originalTotal,
      );

  final String kindLabel;
  final String title;
  final String? clientName;
  final String platform;
  final double basePrice;
  final List<PricingAdjustment> pricingAdjustments;
  final double supplementAmount;
  final double pricedSupplementAmount;
  final bool supplementPricingEnabled;
  final double deductionAmount;
  final double total;
}


class AnnualReceiptEntry {
  const AnnualReceiptEntry({
    required this.title,
    required this.platform,
    required this.amount,
    required this.date,
  });

  final String title;
  final String platform;
  final double amount;
  final DateTime date;
}

class AnnualReceiptData {
  const AnnualReceiptData({
    required this.clientName,
    required this.year,
    required this.entries,
  });

  factory AnnualReceiptData.fromSources({
    required String clientName,
    required int year,
    required Iterable<QueueOrder> orders,
    required Iterable<FinishedProduct> products,
  }) {
    final normalizedClient = clientName.trim().toLowerCase();
    final entries = <AnnualReceiptEntry>[];

    for (final order in orders) {
      if (!order.isArchived) continue;
      final date = order.settledAt ?? order.completedAt;
      if (date == null ||
          date.year != year ||
          order.clientName.trim().toLowerCase() != normalizedClient) {
        continue;
      }
      entries.add(
        AnnualReceiptEntry(
          title: order.title,
          platform: order.platform.label,
          amount: annualReceiptAmountForOrder(order),
          date: date,
        ),
      );
    }

    for (final product in products) {
      if (!product.isArchived) continue;
      for (final soldAt in product.saleRecords) {
        if (soldAt.year != year) continue;
        final saleClient = product.clientNameForSale(soldAt);
        if (saleClient == null ||
            saleClient.trim().toLowerCase() != normalizedClient) {
          continue;
        }
        entries.add(
          AnnualReceiptEntry(
            title: product.title,
            platform: product.platform.label,
            amount: product.originalTotal,
            date: soldAt,
          ),
        );
      }
    }

    entries.sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      if (byDate != 0) return byDate;
      return left.title.compareTo(right.title);
    });

    return AnnualReceiptData(
      clientName: clientName.trim(),
      year: year,
      entries: List<AnnualReceiptEntry>.unmodifiable(entries),
    );
  }

  factory AnnualReceiptData.fromOrders({
    required String clientName,
    required int year,
    required Iterable<QueueOrder> orders,
  }) {
    return AnnualReceiptData.fromSources(
      clientName: clientName,
      year: year,
      orders: orders,
      products: const <FinishedProduct>[],
    );
  }

  final String clientName;
  final int year;
  final List<AnnualReceiptEntry> entries;

  double get total =>
      entries.fold<double>(0, (sum, entry) => sum + entry.amount);
}

class _ReceiptEditableSpec {
  const _ReceiptEditableSpec({
    required this.id,
    required this.name,
    required this.defaultText,
    required this.defaultFontSize,
  });

  final String id;
  final String name;
  final String defaultText;
  final double defaultFontSize;
}

class _ReceiptContentDraft {
  const _ReceiptContentDraft({
    this.textOverrides = const <String, String>{},
    this.fontSizeOverrides = const <String, double>{},
  });

  final Map<String, String> textOverrides;
  final Map<String, double> fontSizeOverrides;

  String text(String id, String fallback) => textOverrides[id] ?? fallback;

  double fontSize(String id, double fallback) =>
      fontSizeOverrides[id] ?? fallback;

  _ReceiptContentDraft withText(String id, String value) {
    return _ReceiptContentDraft(
      textOverrides: <String, String>{...textOverrides, id: value},
      fontSizeOverrides: fontSizeOverrides,
    );
  }

  _ReceiptContentDraft withFontSize(String id, double value) {
    return _ReceiptContentDraft(
      textOverrides: textOverrides,
      fontSizeOverrides: <String, double>{
        ...fontSizeOverrides,
        id: value.clamp(8, 42).toDouble(),
      },
    );
  }
}

double annualReceiptAmountForOrder(QueueOrder order) {
  if (order.archiveOutcome != OrderArchiveOutcome.terminated) {
    return order.originalTotal;
  }

  final refund = order.customRefundAmount;
  if (refund != null) {
    return (order.originalTotal - refund).clamp(0, double.infinity).toDouble();
  }

  final settlementNode = order.settlementNode;
  if (settlementNode != null) {
    final ratio = settlementNode.progressPercent.clamp(0, 100) / 100;
    return order.originalTotal * ratio;
  }

  return order.originalTotal;
}

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    required this.data,
    required this.styleStore,
    required this.defaultHeaderText,
    super.key,
  }) : annualData = null;

  const ReceiptPage.annual({
    required this.annualData,
    required this.styleStore,
    required this.defaultHeaderText,
    super.key,
  }) : data = null;

  final ReceiptData? data;
  final AnnualReceiptData? annualData;
  final ReceiptStyleStore styleStore;
  final String defaultHeaderText;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _receiptKey = GlobalKey();
  static const ReceiptStyleImageBridge _imageBridge =
      ReceiptStyleImageBridge();
  static const ReceiptStyleTransfer _styleTransfer = ReceiptStyleTransfer();
  bool _exporting = false;
  bool _transparentBackground = false;
  _ReceiptContentDraft _contentDraft = const _ReceiptContentDraft();
  String? _cachedBackgroundBase64;
  MemoryImage? _cachedBackgroundImage;

  Future<void> _pickBackground() async {
    try {
      final picked = await _imageBridge.pickImage();
      if (picked == null) return;
      if (!mounted) return;
      if (picked.bytes.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('背景图请控制在 5 MB 以内'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      widget.styleStore.setBackgroundImage(
        base64: base64Encode(picked.bytes),
        name: picked.name,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入背景图失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickFontColor() async {
    final picked = await showThemeColorPicker(
      context: context,
      initialColor: Color(widget.styleStore.fontColorValue),
      title: '字体颜色',
    );
    if (picked != null && mounted) {
      widget.styleStore.setFontColorValue(picked.toARGB32());
    }
  }

  List<_ReceiptEditableSpec> _contentSpecs() {
    final header = widget.styleStore.effectiveHeaderText(
      widget.defaultHeaderText,
    );
    if (widget.annualData != null) {
      final data = widget.annualData!;
      return <_ReceiptEditableSpec>[
        _ReceiptEditableSpec(
          id: 'header',
          name: '抬头',
          defaultText: header,
          defaultFontSize: 22,
        ),
        _ReceiptEditableSpec(
          id: 'annual.subtitle',
          name: '副标题',
          defaultText: '${data.year} 年度业务小票',
          defaultFontSize: 14,
        ),
        const _ReceiptEditableSpec(
          id: 'annual.client.label',
          name: '单主字段名',
          defaultText: '单主',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'annual.client.value',
          name: '单主内容',
          defaultText: data.clientName,
          defaultFontSize: 14,
        ),
        const _ReceiptEditableSpec(
          id: 'annual.count.label',
          name: '业务数字段名',
          defaultText: '业务数',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'annual.count.value',
          name: '业务数内容',
          defaultText: '${data.entries.length} 单',
          defaultFontSize: 14,
        ),
        for (var index = 0; index < data.entries.length; index++) ...[
          _ReceiptEditableSpec(
            id: 'annual.entry.$index.index',
            name: '第 ${index + 1} 条编号',
            defaultText: (index + 1).toString().padLeft(2, '0'),
            defaultFontSize: 14,
          ),
          _ReceiptEditableSpec(
            id: 'annual.entry.$index.title',
            name: '第 ${index + 1} 条项目',
            defaultText: data.entries[index].title,
            defaultFontSize: 14,
          ),
          _ReceiptEditableSpec(
            id: 'annual.entry.$index.platform',
            name: '第 ${index + 1} 条平台',
            defaultText: data.entries[index].platform,
            defaultFontSize: 14,
          ),
          _ReceiptEditableSpec(
            id: 'annual.entry.$index.amount',
            name: '第 ${index + 1} 条金额',
            defaultText: '¥ ${_money(data.entries[index].amount)}',
            defaultFontSize: 14,
          ),
        ],
        const _ReceiptEditableSpec(
          id: 'annual.total.label',
          name: '总额字段名',
          defaultText: '全年总额',
          defaultFontSize: 18,
        ),
        _ReceiptEditableSpec(
          id: 'annual.total.value',
          name: '总额内容',
          defaultText: '¥ ${_money(data.total)}',
          defaultFontSize: 22,
        ),
        const _ReceiptEditableSpec(
          id: 'footer',
          name: '底部文字',
          defaultText: 'THANK YOU',
          defaultFontSize: 14,
        ),
      ];
    }

    final data = widget.data!;
    final pricedBase = applyPricingAdjustments(
      data.basePrice,
      data.pricingAdjustments,
    );
    return <_ReceiptEditableSpec>[
      _ReceiptEditableSpec(
        id: 'header',
        name: '抬头',
        defaultText: header,
        defaultFontSize: 22,
      ),
      _ReceiptEditableSpec(
        id: 'platform',
        name: '平台',
        defaultText: data.platform,
        defaultFontSize: 14,
      ),
      const _ReceiptEditableSpec(
        id: 'item.label',
        name: '项目字段名',
        defaultText: '项目',
        defaultFontSize: 14,
      ),
      _ReceiptEditableSpec(
        id: 'item.value',
        name: '项目内容',
        defaultText: data.title,
        defaultFontSize: 14,
      ),
      if (data.clientName != null && data.clientName!.trim().isNotEmpty) ...[
        const _ReceiptEditableSpec(
          id: 'client.label',
          name: '单主字段名',
          defaultText: '单主',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'client.value',
          name: '单主内容',
          defaultText: data.clientName!,
          defaultFontSize: 14,
        ),
      ],
      const _ReceiptEditableSpec(
        id: 'base.label',
        name: '基础价格字段名',
        defaultText: '基础价格',
        defaultFontSize: 14,
      ),
      _ReceiptEditableSpec(
        id: 'base.value',
        name: '基础价格内容',
        defaultText: '¥ ${_money(data.basePrice)}',
        defaultFontSize: 14,
      ),
      for (var index = 0; index < data.pricingAdjustments.length; index++) ...[
        _ReceiptEditableSpec(
          id: 'adjustment.$index.label',
          name: '第 ${index + 1} 条加价名称',
          defaultText: data.pricingAdjustments[index].name,
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'adjustment.$index.value',
          name: '第 ${index + 1} 条加价内容',
          defaultText: data.pricingAdjustments[index].formulaLabel,
          defaultFontSize: 14,
        ),
      ],
      if (data.pricingAdjustments.isNotEmpty) ...[
        const _ReceiptEditableSpec(
          id: 'priced.label',
          name: '加价后字段名',
          defaultText: '加价后',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'priced.value',
          name: '加价后内容',
          defaultText: '¥ ${_money(pricedBase)}',
          defaultFontSize: 14,
        ),
      ],
      if (data.supplementAmount != 0) ...[
        _ReceiptEditableSpec(
          id: 'supplement.label',
          name: '补款字段名',
          defaultText: data.supplementPricingEnabled ? '补款原额' : '补款',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'supplement.value',
          name: '补款内容',
          defaultText: '+¥ ${_money(data.supplementAmount)}',
          defaultFontSize: 14,
        ),
        if (data.supplementPricingEnabled) ...[
          const _ReceiptEditableSpec(
            id: 'supplementPriced.label',
            name: '补款加价后字段名',
            defaultText: '补款加价后',
            defaultFontSize: 14,
          ),
          _ReceiptEditableSpec(
            id: 'supplementPriced.value',
            name: '补款加价后内容',
            defaultText: '+¥ ${_money(data.pricedSupplementAmount)}',
            defaultFontSize: 14,
          ),
        ],
      ],
      if (data.deductionAmount != 0) ...[
        const _ReceiptEditableSpec(
          id: 'deduction.label',
          name: '减款字段名',
          defaultText: '减款',
          defaultFontSize: 14,
        ),
        _ReceiptEditableSpec(
          id: 'deduction.value',
          name: '减款内容',
          defaultText: '-¥ ${_money(data.deductionAmount)}',
          defaultFontSize: 14,
        ),
      ],
      const _ReceiptEditableSpec(
        id: 'total.label',
        name: '合计字段名',
        defaultText: '合计',
        defaultFontSize: 18,
      ),
      _ReceiptEditableSpec(
        id: 'total.value',
        name: '合计内容',
        defaultText: '¥ ${_money(data.total)}',
        defaultFontSize: 22,
      ),
      const _ReceiptEditableSpec(
        id: 'footer',
        name: '底部文字',
        defaultText: 'THANK YOU',
        defaultFontSize: 14,
      ),
    ];
  }

  Future<void> _editContent() async {
    final result = await Navigator.of(context).push<_ReceiptContentDraft>(
      MaterialPageRoute<_ReceiptContentDraft>(
        builder: (_) => _ReceiptContentEditorPage(
          specs: _contentSpecs(),
          initial: _contentDraft,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _contentDraft = result);
    }
  }

  MemoryImage? _backgroundImage() {
    final raw = widget.styleStore.backgroundImageBase64;
    if (raw == null || raw.isEmpty) {
      _cachedBackgroundBase64 = null;
      _cachedBackgroundImage = null;
      return null;
    }
    if (_cachedBackgroundBase64 == raw && _cachedBackgroundImage != null) {
      return _cachedBackgroundImage;
    }
    try {
      final image = MemoryImage(base64Decode(raw));
      _cachedBackgroundBase64 = raw;
      _cachedBackgroundImage = image;
      return image;
    } catch (_) {
      _cachedBackgroundBase64 = null;
      _cachedBackgroundImage = null;
      return null;
    }
  }

  Future<void> _resetStyle() async {
    widget.styleStore.resetDefault();
  }

  Future<void> _saveCurrentStylePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存样式预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    widget.styleStore.saveCurrentPreset(
      name,
      resolvedHeaderText: widget.styleStore.effectiveHeaderText(
        widget.defaultHeaderText,
      ),
    );
  }

  Future<void> _shareStylePreset(ReceiptStylePreset preset) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReceiptStyleShareImagePage(preset: preset),
      ),
    );
  }

  Future<void> _importStylePresetFromImage() async {
    try {
      final picked = await _imageBridge.pickImage();
      if (picked == null) return;
      final preset = _styleTransfer.decodePresetFromImage(picked.bytes);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入这个小票预设？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preset.name,
                style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                preset.backgroundImageBase64 == null
                    ? '包含字体颜色，不含自定义背景。'
                    : '包含字体颜色和自定义背景：${preset.backgroundImageName ?? '背景图'}',
              ),
              const SizedBox(height: 8),
              const Text('导入后会保存到样式预设并立即应用。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('导入并使用'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      widget.styleStore.importPreset(preset);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${preset.name}”已经导入并启用。')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : '导入小票预设失败：$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  Future<void> _showStylePresets() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: widget.styleStore,
        builder: (context, _) {
          final presets = widget.styleStore.presets;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '样式预设',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (presets.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: presets.length,
                      itemBuilder: (context, index) {
                        final preset = presets[index];
                        return ListTile(
                          onTap: () {
                            widget.styleStore.applyPreset(preset.id);
                            Navigator.of(sheetContext).pop();
                          },
                          leading: CircleAvatar(
                            backgroundColor: Color(preset.fontColorValue),
                            radius: 13,
                          ),
                          title: Text(preset.name),
                          trailing: PopupMenuButton<String>(
                            tooltip: '预设操作',
                            onSelected: (value) {
                              if (value == 'share') {
                                Navigator.of(sheetContext).pop();
                                _shareStylePreset(preset);
                              } else if (value == 'delete') {
                                widget.styleStore.deletePreset(preset.id);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'share',
                                child: Text('生成分享图片'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _importStylePresetFromImage();
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从分享图片导入'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _saveCurrentStylePreset();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('保存当前样式'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportReceipt() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final backgroundImage =
          _transparentBackground ? null : _backgroundImage();
      if (backgroundImage != null) {
        await precacheImage(backgroundImage, context);
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _receiptKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('小票预览还没有准备好');
      }
      final longestSide = math.max(
        boundary.size.width,
        boundary.size.height,
      );
      final pixelRatio = longestSide <= 0
          ? 3.0
          : (12000 / longestSide).clamp(1.0, 3.0).toDouble();
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法生成小票图片');
      final bytes = data.buffer.asUint8List();
      final documentTitle = widget.annualData == null
          ? widget.data!.title
          : '${widget.annualData!.clientName}-${widget.annualData!.year}年度';
      final safeTitle = documentTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final fileName = '${safeTitle.isEmpty ? '小票' : safeTitle}-小票.png';
      final saved = await _imageBridge.exportImage(
        fileName: fileName,
        bytes: bytes,
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('小票图片已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成小票失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.styleStore,
      builder: (context, _) {
        final style = widget.styleStore;
        final backgroundImage =
            _transparentBackground ? null : _backgroundImage();

        return Scaffold(
          appBar: AppBar(
            title: const Text('生成小票'),
          ),
          body: ListView(
            padding: AppLayoutSpacing.pageScrollPaddingWithAction(
              context,
              left: 18,
              top: 16,
              right: 18,
            ),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickBackground,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      style.backgroundImageName == null
                          ? '导入背景图'
                          : '更换背景图',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickFontColor,
                    icon: Icon(
                      Icons.palette_outlined,
                      color: Color(style.fontColorValue),
                    ),
                    label: const Text('字体颜色'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editHeaderText,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('抬头文字'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showStylePresets,
                    icon: const Icon(Icons.bookmarks_outlined),
                    label: const Text('样式预设'),
                  ),
                  OutlinedButton.icon(
                    onPressed: style.isDefault ? null : _resetStyle,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _transparentBackground,
                onChanged: _exporting
                    ? null
                    : (value) {
                        setState(() {
                          _transparentBackground = value ?? false;
                        });
                      },
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('透明底导出'),
                subtitle: const Text(
                  '导出不包含背景图的纯内容',
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: widget.annualData == null
                      ? _ReceiptPaper(
                          data: widget.data!,
                          headerText: style.effectiveHeaderText(
                            widget.defaultHeaderText,
                          ),
                          fontColor: Color(style.fontColorValue),
                          backgroundImage: backgroundImage,
                          transparentBackground: _transparentBackground,
                        )
                      : _AnnualReceiptPaper(
                          data: widget.annualData!,
                          headerText: style.effectiveHeaderText(
                            widget.defaultHeaderText,
                          ),
                          fontColor: Color(style.fontColorValue),
                          backgroundImage: backgroundImage,
                          transparentBackground: _transparentBackground,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _exporting ? null : _exportReceipt,
                icon: _exporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_exporting ? '正在生成…' : '保存小票图片'),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _ReceiptHeaderEditResult {
  const _ReceiptHeaderEditResult.custom(this.text) : followAccount = false;
  const _ReceiptHeaderEditResult.followAccount()
      : followAccount = true,
        text = '';

  final bool followAccount;
  final String text;
}

class _ReceiptPaperFrame extends StatelessWidget {
  const _ReceiptPaperFrame({
    required this.fontColor,
    required this.backgroundImage,
    required this.transparentBackground,
    required this.child,
  });

  final Color fontColor;
  final ImageProvider? backgroundImage;
  final bool transparentBackground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(minHeight: 500),
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 34),
      decoration: transparentBackground
          ? null
          : BoxDecoration(
              color: Colors.white,
              image: backgroundImage == null
                  ? null
                  : DecorationImage(
                      image: backgroundImage!,
                      fit: BoxFit.cover,
                    ),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: Offset(0, 6),
                  color: Color(0x22000000),
                ),
              ],
            ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: fontColor,
          fontSize: 14,
          height: 1.45,
          fontFamily: 'monospace',
        ),
        child: child,
      ),
    );
  }
}

class _AnnualReceiptPaper extends StatelessWidget {
  const _AnnualReceiptPaper({
    required this.data,
    required this.headerText,
    required this.fontColor,
    required this.backgroundImage,
    required this.transparentBackground,
  });

  final AnnualReceiptData data;
  final String headerText;
  final Color fontColor;
  final ImageProvider? backgroundImage;
  final bool transparentBackground;

  @override
  Widget build(BuildContext context) {
    return _ReceiptPaperFrame(
      fontColor: fontColor,
      backgroundImage: backgroundImage,
      transparentBackground: transparentBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerText.isNotEmpty) ...[
            Text(
              headerText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fontColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            '${data.year} 年度业务小票',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          _DashedDivider(color: fontColor),
          const SizedBox(height: 14),
          _ReceiptTextRow(label: '单主', value: data.clientName),
          _ReceiptTextRow(label: '业务数', value: '${data.entries.length} 单'),
          const SizedBox(height: 12),
          for (var index = 0; index < data.entries.length; index++) ...[
            if (index > 0) const SizedBox(height: 13),
            _AnnualReceiptEntryRow(
              index: index + 1,
              entry: data.entries[index],
            ),
          ],
          const SizedBox(height: 16),
          _DashedDivider(color: fontColor),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '全年总额',
                  style: TextStyle(
                    color: fontColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '¥ ${_money(data.total)}',
                style: TextStyle(
                  color: fontColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'THANK YOU',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fontColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnualReceiptEntryRow extends StatelessWidget {
  const _AnnualReceiptEntryRow({
    required this.index,
    required this.entry,
  });

  final int index;
  final AnnualReceiptEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(index.toString().padLeft(2, '0')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Row(
            children: [
              Expanded(child: Text(entry.platform)),
              Text('¥ ${_money(entry.amount)}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.data,
    required this.headerText,
    required this.fontColor,
    required this.backgroundImage,
    required this.transparentBackground,
  });

  final ReceiptData data;
  final String headerText;
  final Color fontColor;
  final ImageProvider? backgroundImage;
  final bool transparentBackground;

  @override
  Widget build(BuildContext context) {
    final pricedBase = applyPricingAdjustments(
      data.basePrice,
      data.pricingAdjustments,
    );
    return _ReceiptPaperFrame(
      fontColor: fontColor,
      backgroundImage: backgroundImage,
      transparentBackground: transparentBackground,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headerText.isNotEmpty) ...[
              Text(
                headerText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fontColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              data.platform,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _DashedDivider(color: fontColor),
            const SizedBox(height: 14),
            _ReceiptTextRow(label: '项目', value: data.title),
            if (data.clientName != null && data.clientName!.trim().isNotEmpty)
              _ReceiptTextRow(label: '单主', value: data.clientName!),
            const SizedBox(height: 10),
            _ReceiptMoneyRow(label: '基础价格', amount: data.basePrice),
            for (final adjustment in data.pricingAdjustments)
              _ReceiptFormulaRow(adjustment: adjustment),
            if (data.pricingAdjustments.isNotEmpty)
              _ReceiptMoneyRow(label: '加价后', amount: pricedBase),
            if (data.supplementAmount != 0) ...[
              _ReceiptMoneyRow(
                label: data.supplementPricingEnabled ? '补款原额' : '补款',
                amount: data.supplementAmount,
                prefix: '+',
              ),
              if (data.supplementPricingEnabled)
                _ReceiptMoneyRow(
                  label: '补款加价后',
                  amount: data.pricedSupplementAmount,
                  prefix: '+',
                ),
            ],
            if (data.deductionAmount != 0)
              _ReceiptMoneyRow(
                label: '减款',
                amount: data.deductionAmount,
                prefix: '-',
              ),
            const SizedBox(height: 14),
            _DashedDivider(color: fontColor),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '合计',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '¥ ${_money(data.total)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'THANK YOU',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fontColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
    );
  }
}

class _ReceiptTextRow extends StatelessWidget {
  const _ReceiptTextRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 62, child: Text(label)),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _ReceiptMoneyRow extends StatelessWidget {
  const _ReceiptMoneyRow({
    required this.label,
    required this.amount,
    this.prefix = '',
  });
  final String label;
  final double amount;
  final String prefix;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text('$prefix¥ ${_money(amount)}'),
          ],
        ),
      );
}

class _ReceiptFormulaRow extends StatelessWidget {
  const _ReceiptFormulaRow({required this.adjustment});
  final PricingAdjustment adjustment;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(adjustment.name)),
            Text(adjustment.formulaLabel),
          ],
        ),
      );
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: CustomPaint(painter: _DashedDividerPainter(color)),
      );
}

class _DashedDividerPainter extends CustomPainter {
  const _DashedDividerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + dash).clamp(0, size.width).toDouble(), 0),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}

String _money(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
