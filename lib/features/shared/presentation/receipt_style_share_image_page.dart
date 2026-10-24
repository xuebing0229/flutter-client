import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/receipt_style_image_bridge.dart';
import '../domain/receipt_style_store.dart';
import '../domain/receipt_style_transfer.dart';

class ReceiptStyleShareImagePage extends StatefulWidget {
  const ReceiptStyleShareImagePage({
    required this.preset,
    super.key,
  });

  final ReceiptStylePreset preset;

  @override
  State<ReceiptStyleShareImagePage> createState() =>
      _ReceiptStyleShareImagePageState();
}

class _ReceiptStyleShareImagePageState
    extends State<ReceiptStyleShareImagePage> {
  static const _imageBridge = ReceiptStyleImageBridge();
  static const _transfer = ReceiptStyleTransfer();

  final GlobalKey _cardKey = GlobalKey();
  bool _saving = false;

  MemoryImage? _backgroundImage() {
    final raw = widget.preset.backgroundImageBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = _backgroundImage();
    return Scaffold(
      appBar: AppBar(title: const Text('小票预设分享图片')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
        children: [
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: _ReceiptStyleShareCard(
                preset: widget.preset,
                backgroundImage: background,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '这张 PNG 自带完整小票预设，包含字体颜色和自定义背景。对方可在「样式预设 → 从分享图片导入」中选择这张图恢复。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：部分聊天软件会重新压缩图片并抹掉附带数据。分享时优先发送原图或作为文件发送。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton.icon(
          onPressed: _saving ? null : _saveImage,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: Text(_saving ? '正在生成…' : '保存分享图片'),
        ),
      ),
    );
  }

  Future<void> _saveImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final background = _backgroundImage();
      if (background != null) {
        await precacheImage(background, context);
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('分享卡片还没有准备好。');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final png = byteData?.buffer.asUint8List();
      if (png == null || png.isEmpty) {
        throw StateError('分享图片生成失败。');
      }

      final bytes = _transfer.attachPresetToPng(png, widget.preset);
      final saved = await _imageBridge.exportImage(
        fileName: '${_safeName(widget.preset.name)}-小票预设.png',
        bytes: bytes,
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('小票预设分享图片已经保存。')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成分享图片失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _safeName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? '冒险者公会小票预设' : cleaned;
  }
}

class _ReceiptStyleShareCard extends StatelessWidget {
  const _ReceiptStyleShareCard({
    required this.preset,
    required this.backgroundImage,
  });

  final ReceiptStylePreset preset;
  final ImageProvider? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final fontColor = Color(preset.fontColorValue);
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '冒险者公会 · 小票样式',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preset.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 260,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              image: backgroundImage == null
                  ? null
                  : DecorationImage(
                      image: backgroundImage!,
                      fit: BoxFit.cover,
                    ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: fontColor,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '冒险者公会',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fontColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('米画师', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Divider(color: fontColor.withValues(alpha: 0.5)),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Text('项目'),
                      Spacer(),
                      Text(
                        '示例稿件',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Text('基础价格'),
                      Spacer(),
                      Text('¥ 200'),
                    ],
                  ),
                  const Spacer(),
                  Divider(color: fontColor.withValues(alpha: 0.5)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        '合计',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Text(
                        '¥ 200',
                        style: TextStyle(
                          color: fontColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                preset.backgroundImageBase64 == null
                    ? Icons.image_not_supported_outlined
                    : Icons.image_outlined,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  preset.backgroundImageBase64 == null
                      ? '不含自定义背景'
                      : '包含自定义背景：${preset.backgroundImageName ?? '背景图'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '从冒险者公会选择这张原图即可导入预设',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
