import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/theme_palette_transfer.dart';
import 'custom_theme_color_page.dart';
import 'theme_color_page_common.dart';
import 'theme_share_image_page.dart';

typedef ThemeShareImageImporter = Future<SharedThemePreset?> Function();
typedef ThemeQrScannerBuilder = Widget Function();

class SharedThemeColorPage extends StatelessWidget {
  const SharedThemeColorPage({
    required this.store,
    this.onBack,
    this.importFromShareImage,
    this.qrScannerBuilder,
    super.key,
  });

  static const _transfer = ThemePaletteTransferService();

  final AppThemeStore store;
  final VoidCallback? onBack;
  final ThemeShareImageImporter? importFromShareImage;
  final ThemeQrScannerBuilder? qrScannerBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: '返回设置',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
        title: const Text(
          'UI主题色',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '导入配色',
            onPressed: () => _showImportOptions(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: ThemeColorPageBody(
        store: store,
        onEdit: _openEditor,
        onShare: _showShareOptions,
        onDelete: _deletePalette,
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AppThemePalette? palette,
    bool forceCopy = false,
  }) async {
    AppThemePalette? source = palette;
    if (forceCopy && palette != null) {
      source = AppThemePalette.custom(
        id: 'custom:copy:${DateTime.now().microsecondsSinceEpoch}',
        name: '${palette.name} 副本',
        seed: palette.lightSeed,
        light: palette.lightSemanticColors!,
        dark: palette.darkSemanticColors!,
        advanced: palette.customAdvanced,
      );
    }
    await Navigator.of(context).push<AppThemePalette>(
      MaterialPageRoute(
        builder: (context) => CustomThemeColorPage(
          store: store,
          palette: source,
        ),
      ),
    );
  }

  Future<void> _showShareOptions(
    BuildContext context,
    AppThemePalette palette,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('生成分享图片'),
              subtitle: const Text('生成带配色预览和二维码的图片，适合直接发给别人'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('导出配色文件'),
              subtitle: const Text('生成 .agtheme 文件，发给别人后可以直接导入'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('复制分享码'),
              subtitle: const Text('适合直接粘贴到聊天里，对方在公会里粘贴导入'),
              onTap: () => Navigator.of(sheetContext).pop('code'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      if (action == 'image') {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ThemeShareImagePage(palette: palette),
          ),
        );
      } else if (action == 'file') {
        final saved = await _transfer.exportPalette(palette);
        if (!context.mounted) return;
        if (saved) {
          _showMessage(context, '配色文件已经导出，可以直接发给其他冒险者。');
        }
      } else if (action == 'code') {
        await Clipboard.setData(
          ClipboardData(text: _transfer.shareCode(palette)),
        );
        if (!context.mounted) return;
        _showMessage(context, '配色分享码已经复制。');
      }
    } catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _showImportOptions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (qrScannerBuilder != null)
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('扫描分享图二维码'),
                subtitle: const Text('用相机扫描别人分享图片里的二维码'),
                onTap: () => Navigator.of(sheetContext).pop('scan'),
              ),
            if (importFromShareImage != null)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从分享图片导入'),
                subtitle: const Text('从相册或图片文件中识别配色二维码'),
                onTap: () => Navigator.of(sheetContext).pop('image'),
              ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('从配色文件导入'),
              subtitle: const Text('选择别人发来的 .agtheme 文件'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('粘贴分享码'),
              subtitle: const Text('粘贴以 AGTHEME1: 开头的配色分享码'),
              onTap: () => Navigator.of(sheetContext).pop('code'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      SharedThemePreset? preset;
      if (action == 'scan') {
        final builder = qrScannerBuilder;
        if (builder == null) return;
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => builder()),
        );
        if (raw == null || raw.trim().isEmpty) return;
        preset = _transfer.decode(raw);
      } else if (action == 'image') {
        final importer = importFromShareImage;
        if (importer == null) return;
        preset = await importer();
      } else if (action == 'file') {
        preset = await _transfer.importFromFile();
      } else {
        final raw = await _askShareCode(context);
        if (raw == null || raw.trim().isEmpty) return;
        preset = _transfer.decode(raw);
      }

      if (preset == null || !context.mounted) return;
      await _confirmImport(context, preset);
    } catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }

  Future<String?> _askShareCode(BuildContext context) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return null;
    final initial = clipboard?.text?.trim() ?? '';
    final controller = TextEditingController(
      text: initial.startsWith(ThemePaletteTransferCodec.sharePrefix)
          ? initial
          : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴配色分享码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(hintText: 'AGTHEME1:……'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('识别'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _confirmImport(
    BuildContext context,
    SharedThemePreset preset,
  ) async {
    final preview = preset.toPalette();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入这套主题色？'),
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
            ThemePalettePreview(
              palette: preview,
              width: 180,
              height: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              '只会导入颜色方案，不会改变你的 UI 风格；导入后会保存到“我的配色”并立即使用。',
            ),
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
    if (confirmed != true) return;

    await store.saveCustomPalette(
      name: preset.name,
      seed: preset.seed,
      light: preset.light,
      dark: preset.dark,
      advanced: preset.advanced,
      select: true,
    );
    if (!context.mounted) return;
    _showMessage(context, '“${preset.name}”已经导入并启用。');
  }

  Future<void> _deletePalette(
    BuildContext context,
    AppThemePalette palette,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个配色？'),
        content: Text('“${palette.name}”会从我的配色中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.deleteCustomPalette(palette.id);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(BuildContext context, Object error) {
    final message = switch (error) {
      FormatException(:final message) => message,
      _ => '配色分享操作失败：$error',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
