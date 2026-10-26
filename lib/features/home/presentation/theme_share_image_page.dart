import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/theme_palette_transfer.dart';

class ThemeShareImagePage extends StatefulWidget {
  const ThemeShareImagePage({
    required this.palette,
    super.key,
  });

  final AppThemePalette palette;

  @override
  State<ThemeShareImagePage> createState() => _ThemeShareImagePageState();
}

class _ThemeShareImagePageState extends State<ThemeShareImagePage> {
  static const _transfer = ThemePaletteTransferService();
  static const _fileBridge = DataPortabilityFileBridge();

  final GlobalKey _cardKey = GlobalKey();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final shareCode = _transfer.shareCode(widget.palette);

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题分享图片'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
        children: [
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: ThemeShareCard(
                palette: widget.palette,
                shareCode: shareCode,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '图片里的二维码包含完整配色数据。对方可以在「UI主题色 → 导入配色」里扫描或从相册选择这张图，不需要另外传文件。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('分享卡片还没有准备好，请稍后再试。');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('分享图片生成失败。');
      }

      final saved = await _fileBridge.exportImage(
        fileName: '${_safeFileName(widget.palette.name)}-主题分享.png',
        bytes: bytes,
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享图片已经保存。')),
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

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? '冒险者公会配色' : cleaned;
  }
}

class ThemeShareCard extends StatelessWidget {
  const ThemeShareCard({
    required this.palette,
    required this.shareCode,
    super.key,
  });

  final AppThemePalette palette;
  final String shareCode;

  @override
  Widget build(BuildContext context) {
    final light = palette.lightSemanticColors!;
    final dark = palette.darkSemanticColors!;
    final onPrimary = light.primary.computeLuminance() > 0.48
        ? Colors.black
        : Colors.white;

    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: light.background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: light.border, width: 1.5),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: light.foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: light.primary,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    color: onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '冒险者公会 · UI 配色',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        palette.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ShareColorStrip(colors: light),
            const SizedBox(height: 16),
            _MiniUiPreview(
              colors: light,
              onPrimary: onPrimary,
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: QrImageView(
                    data: shareCode,
                    size: 136,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫码导入这套配色',
                        style: TextStyle(
                          color: light.foreground,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '也可以把整张图保存到相册，再从冒险者公会里选择图片导入。',
                        style: TextStyle(
                          color: light.mutedForeground,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ModeChip(
                            label: palette.customAdvanced ? '高级配色' : '基础配色',
                            foreground: dark.foreground,
                            background: dark.surfaceAlt,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareColorStrip extends StatelessWidget {
  const _ShareColorStrip({required this.colors});

  final AppThemeSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final items = <Color>[
      colors.primary,
      colors.accent,
      colors.background,
      colors.surface,
      colors.surfaceAlt,
      colors.foreground,
      colors.mutedForeground,
      colors.border,
    ];
    return Container(
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final color in items)
            Expanded(child: ColoredBox(color: color)),
        ],
      ),
    );
  }
}

class _MiniUiPreview extends StatelessWidget {
  const _MiniUiPreview({
    required this.colors,
    required this.onPrimary,
  });

  final AppThemeSemanticColors colors;
  final Color onPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: 6),
                Text(
                  '搜索排单',
                  style: TextStyle(
                    color: colors.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '米画师',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '示例排单',
                  style: TextStyle(
                    color: colors.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '剩余 3天',
                style: TextStyle(
                  color: colors.mutedForeground,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '确认节点',
              style: TextStyle(
                color: onPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
