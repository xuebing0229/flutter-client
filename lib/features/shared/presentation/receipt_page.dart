import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/finance/pricing_adjustments.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../orders/domain/queue_order.dart';
import '../../products/domain/finished_product.dart';
import '../domain/receipt_style_store.dart';
import 'layout_spacing.dart';

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

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    required this.data,
    required this.styleStore,
    super.key,
  });

  final ReceiptData data;
  final ReceiptStyleStore styleStore;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _receiptKey = GlobalKey();
  final DataPortabilityFileBridge _fileBridge =
      const DataPortabilityFileBridge();
  bool _exporting = false;

  Future<void> _pickBackground() async {
    try {
      final path = await _fileBridge.pickImage();
      if (path == null) return;
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('背景图请控制在 5 MB 以内'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final normalized = path.replaceAll('\\', '/');
      widget.styleStore.setBackgroundImage(
        base64: base64Encode(bytes),
        name: normalized.split('/').last,
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
    final initial = Color(widget.styleStore.fontColorValue);
    var hsv = HSVColor.fromColor(initial);
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final color = hsv.toColor();
          return AlertDialog(
            title: const Text('字体颜色'),
            content: SizedBox(
              width: 330,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ColorSlider(
                    label: '色相',
                    value: hsv.hue,
                    max: 360,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  _ColorSlider(
                    label: '饱和',
                    value: hsv.saturation * 100,
                    max: 100,
                    onChanged: (value) => setDialogState(
                      () => hsv = hsv.withSaturation(value / 100),
                    ),
                  ),
                  _ColorSlider(
                    label: '明度',
                    value: hsv.value * 100,
                    max: 100,
                    onChanged: (value) => setDialogState(
                      () => hsv = hsv.withValue(value / 100),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(color.toARGB32()),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (picked != null) widget.styleStore.setFontColorValue(picked);
  }

  Future<void> _exportReceipt() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _receiptKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('小票预览还没有准备好');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法生成小票图片');
      final bytes = data.buffer.asUint8List();
      final safeTitle = widget.data.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final fileName = '${safeTitle.isEmpty ? '小票' : safeTitle}-小票.png';
      final saved = await _fileBridge.exportImage(
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
        final background = style.backgroundImageBase64;
        MemoryImage? backgroundImage;
        if (background != null && background.isNotEmpty) {
          try {
            backgroundImage = MemoryImage(base64Decode(background));
          } catch (_) {
            backgroundImage = null;
          }
        }

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
                  if (style.backgroundImageBase64 != null)
                    OutlinedButton.icon(
                      onPressed: style.clearBackgroundImage,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('恢复白底'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickFontColor,
                    icon: Icon(
                      Icons.palette_outlined,
                      color: Color(style.fontColorValue),
                    ),
                    label: const Text('字体颜色'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: _ReceiptPaper(
                    data: widget.data,
                    fontColor: Color(style.fontColorValue),
                    backgroundImage: backgroundImage,
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

class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.data,
    required this.fontColor,
    required this.backgroundImage,
  });

  final ReceiptData data;
  final Color fontColor;
  final ImageProvider? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final pricedBase = applyPricingAdjustments(
      data.basePrice,
      data.pricingAdjustments,
    );
    return Container(
      width: 360,
      constraints: const BoxConstraints(minHeight: 500),
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 34),
      decoration: BoxDecoration(
        color: Colors.white,
        image: backgroundImage == null
            ? null
            : DecorationImage(image: backgroundImage!, fit: BoxFit.cover),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '冒险者公会',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fontColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${data.kindLabel} · ${data.platform}',
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
        Offset((x + dash).clamp(0, size.width), 0),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 44, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(0, max).toDouble(),
              min: 0,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(value.round().toString(), textAlign: TextAlign.right),
          ),
        ],
      );
}

String _money(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
