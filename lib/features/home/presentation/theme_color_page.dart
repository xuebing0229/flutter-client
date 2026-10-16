import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/theme_palette_transfer.dart';
import '../../shared/presentation/layout_spacing.dart';
import 'custom_theme_color_page.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({
    required this.store,
    this.onBack,
    super.key,
  });

  static const _transfer = ThemePaletteTransferService();

  final AppThemeStore store;
  final VoidCallback? onBack;

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
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final custom = store.customPalettes;
          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 10,
              right: 16,
            ),
            children: [
              _CustomColorEntry(
                onTap: () => _openEditor(context),
              ),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _SectionTitle(title: '我的配色'),
                const SizedBox(height: 8),
                for (final palette in custom) ...[
                  _PaletteTile(
                    palette: palette,
                    selected: palette.id == store.paletteId,
                    onTap: () => store.setPaletteId(palette.id),
                    trailing: PopupMenuButton<String>(
                      tooltip: '配色操作',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openEditor(context, palette: palette);
                        } else if (value == 'copy') {
                          _openEditor(
                            context,
                            palette: AppThemePalette.custom(
                              id: 'custom:copy-preview',
                              name: '${palette.name} 副本',
                              seed: palette.lightSeed,
                              light: palette.lightSemanticColors!,
                              dark: palette.darkSemanticColors!,
                              advanced: palette.customAdvanced,
                            ),
                            forceCopy: true,
                          );
                        } else if (value == 'share') {
                          _showShareOptions(context, palette);
                        } else if (value == 'delete') {
                          _deletePalette(context, palette);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('复制为新方案'),
                        ),
                        PopupMenuItem(
                          value: 'share',
                          child: Text('分享配色'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              const _SectionTitle(title: '预设主题色'),
              const SizedBox(height: 8),
              for (final palette in AppThemePalettes.all) ...[
                _PaletteTile(
                  palette: palette,
                  selected: palette.id == store.paletteId,
                  onTap: () => store.setPaletteId(palette.id),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
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
        name: palette.name,
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
      if (action == 'file') {
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
      if (action == 'file') {
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
          decoration: const InputDecoration(
            hintText: 'AGTHEME1:……',
          ),
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
      builder: (context) => AlertDialog(
        title: const Text('删除这个配色？'),
        content: Text('“${palette.name}”会从我的配色中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(BuildContext context, Object error) {
    final message = switch (error) {
      FormatException(:final message) => message,
      _ => '配色分享操作失败：$error',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _CustomColorEntry extends StatelessWidget {
  const _CustomColorEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.40),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        leading: Container(
          width: 52,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const SweepGradient(
              colors: <Color>[
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.red,
              ],
            ),
          ),
          child: const Icon(
            Icons.colorize_rounded,
            color: Colors.white,
          ),
        ),
        title: const Text(
          '自定义调色',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('自己决定主色、背景、卡片、文字、边框等颜色'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final AppThemePalette palette;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colors.secondaryContainer.withValues(alpha: 0.55)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minTileHeight: 66,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: ThemePalettePreview(
            palette: palette,
            width: 76,
            height: 42,
          ),
          title: Text(
            palette.name,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          subtitle: selected ? const Text('当前使用') : null,
          trailing: trailing ??
              (selected
                  ? Icon(Icons.check_circle_rounded, color: colors.primary)
                  : const Icon(Icons.chevron_right_rounded)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class ThemePalettePreview extends StatelessWidget {
  const ThemePalettePreview({
    required this.palette,
    this.width = 58,
    this.height = 32,
    super.key,
  });

  final AppThemePalette palette;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = palette.previewColors;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final color in colors)
            Expanded(
              child: ColoredBox(color: color),
            ),
        ],
      ),
    );
  }
}
