import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import 'custom_theme_color_page.dart';
import 'theme_color_page_common.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({
    required this.store,
    this.onBack,
    super.key,
  });

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
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text(
          'UI主题色',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ThemeColorPageBody(
        store: store,
        onEdit: _openEditor,
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
        builder: (_) => CustomThemeColorPage(
          store: store,
          palette: source,
        ),
      ),
    );
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
}
