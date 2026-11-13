import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_background.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/guild_visual_theme.dart';
import '../../shared/data/receipt_style_image_bridge.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../shared/presentation/screen_aspect_image_crop_page.dart';
import 'theme_color_picker.dart';

class ImageThemePage extends StatefulWidget {
  const ImageThemePage({
    required this.store,
    this.onBack,
    super.key,
  });

  final AppThemeStore store;
  final VoidCallback? onBack;

  @override
  State<ImageThemePage> createState() => _ImageThemePageState();
}

class _ImageThemePageState extends State<ImageThemePage> {
  static const ReceiptStyleImageBridge _imageBridge =
      ReceiptStyleImageBridge();

  Future<void> _pickBackground() async {
    try {
      final picked = await _imageBridge.pickImage();
      if (picked == null) return;
      if (!mounted) return;
      final cropped = await showScreenAspectImageCropper(
        context: context,
        image: picked.bytes,
        title: '调整背景图',
      );
      if (cropped == null || !mounted) return;
      if (cropped.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('裁切后的背景图仍超过 5 MB，请换一张尺寸稍小的图片'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await widget.store.setImageBackground(
        base64: base64Encode(cropped),
        name: picked.name,
      );
      await widget.store.setImageFitMode(AppImageFitMode.fit);
      await widget.store.setAppearanceMode(AppAppearanceMode.image);
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
      initialColor: widget.store.imageFontColor,
      title: '图片主题字体颜色',
    );
    if (picked != null && mounted) {
      await widget.store.setImageFontColorValue(picked.toARGB32());
    }
  }

  Future<void> _clearBackground() async {
    await widget.store.clearImageBackground();
    await widget.store.setAppearanceMode(AppAppearanceMode.color);
  }

  MemoryImage? _imageProvider() {
    final raw = widget.store.imageBackgroundBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                tooltip: '返回设置',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text(
          '图片主题',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final image = _imageProvider();
          final mode = widget.store.imageBackgroundMode;
          final fitMode = widget.store.imageFitMode;
          final font = widget.store.imageFontColor;
          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 10,
              right: 16,
            ),
            children: [
              _ImageThemePreview(
                image: image,
                mode: mode,
                fitMode: fitMode,
                fontColor: font,
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: _pickBackground,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  widget.store.hasImageBackground ? '更换背景图' : '选择背景图',
                ),
              ),
              if (widget.store.imageBackgroundName != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.store.imageBackgroundName!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 22),
              Text(
                '显示方式',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<AppImageBackgroundMode>(
                segments: const [
                  ButtonSegment<AppImageBackgroundMode>(
                    value: AppImageBackgroundMode.cover,
                    icon: Icon(Icons.layers_clear_outlined),
                    label: Text('全图覆盖'),
                  ),
                  ButtonSegment<AppImageBackgroundMode>(
                    value: AppImageBackgroundMode.glass,
                    icon: Icon(Icons.blur_on_rounded),
                    label: Text('玻璃透明'),
                  ),
                ],
                selected: <AppImageBackgroundMode>{mode},
                onSelectionChanged: (value) =>
                    widget.store.setImageBackgroundMode(value.first),
              ),
              const SizedBox(height: 8),
              Text(
                mode.description,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '图片适配',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<AppImageFitMode>(
                segments: const [
                  ButtonSegment<AppImageFitMode>(
                    value: AppImageFitMode.fit,
                    icon: Icon(Icons.fit_screen_outlined),
                    label: Text('完整适应'),
                  ),
                  ButtonSegment<AppImageFitMode>(
                    value: AppImageFitMode.fill,
                    icon: Icon(Icons.fullscreen_rounded),
                    label: Text('铺满屏幕'),
                  ),
                ],
                selected: <AppImageFitMode>{fitMode},
                onSelectionChanged: (value) =>
                    widget.store.setImageFitMode(value.first),
              ),
              const SizedBox(height: 8),
              Text(
                fitMode.description,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  onTap: _pickFontColor,
                  leading: const Icon(Icons.format_color_text_rounded),
                  title: const Text('字体颜色'),
                  subtitle: const Text('图片主题单独使用，不会改动彩色主题的文字颜色'),
                  trailing: Container(
                    width: 44,
                    height: 34,
                    decoration: BoxDecoration(
                      color: font,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.store.hasImageBackground) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _clearBackground,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('清除图片背景'),
                ),
              ],
              const SizedBox(height: 26),
            ],
          );
        },
      ),
    );
  }
}

class _ImageThemePreview extends StatelessWidget {
  const _ImageThemePreview({
    required this.image,
    required this.mode,
    required this.fitMode,
    required this.fontColor,
  });

  final MemoryImage? image;
  final AppImageBackgroundMode mode;
  final AppImageFitMode fitMode;
  final Color fontColor;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) {
      return Container(
        height: 210,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 40),
            SizedBox(height: 10),
            Text('先选择一张背景图'),
          ],
        ),
      );
    }

    final darkText = fontColor.computeLuminance() < 0.55;
    final glassColor = darkText
        ? Colors.white.withValues(alpha: 0.58)
        : Colors.black.withValues(alpha: 0.34);
    final surfaceStyle = GuildStyleTheme.of(context);

    final screenAspectRatio = MediaQuery.sizeOf(context).aspectRatio;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 240,
          maxHeight: 320,
        ),
        child: AspectRatio(
          aspectRatio: screenAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF121212)
                      : const Color(0xFFF4F4F4),
                  child: Image(
                    image: image,
                    fit: switch (fitMode) {
                      AppImageFitMode.fit => BoxFit.contain,
                      AppImageFitMode.fill => BoxFit.cover,
                    },
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    '冒险者公会',
                    style: TextStyle(
                      color: fontColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: const [
                        Shadow(
                          blurRadius: 4,
                          color: Color(0x66000000),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: mode == AppImageBackgroundMode.glass
                          ? glassColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: fontColor.withValues(alpha: 0.36),
                      ),
                      boxShadow: mode == AppImageBackgroundMode.cover
                          ? surfaceStyle.shadows
                          : const <BoxShadow>[],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode == AppImageBackgroundMode.glass
                              ? '玻璃透明模式'
                              : '全图覆盖模式',
                          style: TextStyle(
                            color: fontColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '示例排单 · 剩余 3 天',
                          style: TextStyle(
                            color: fontColor.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
