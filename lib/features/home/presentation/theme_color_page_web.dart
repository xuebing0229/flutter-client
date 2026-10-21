import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/app_ui_style.dart';
import 'custom_theme_color_page.dart';

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
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text('UI主题'),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text(
                '自定义调色',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('直接复用客户端的完整调色编辑器'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CustomThemeColorPage(store: store),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('明暗模式', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: <ThemeMode>{store.mode},
              onSelectionChanged: (value) => store.setMode(value.first),
            ),
            const SizedBox(height: 24),
            const Text('主题色', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final palette in AppThemePalettes.all)
              ListTile(
                selected: store.paletteId == palette.id,
                onTap: () => store.setPaletteId(palette.id),
                leading: Icon(
                  store.paletteId == palette.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(palette.name),
                trailing: Wrap(
                  spacing: 3,
                  children: [
                    for (final color in palette.previewColors.take(4))
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            const Text('界面风格', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final style in AppUiStyle.values)
              ListTile(
                selected: store.style == style,
                onTap: () => store.setStyle(style),
                leading: Icon(
                  store.style == style
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(style.label),
              ),
            if (store.customPalettes.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('已保存自定义配色',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (final palette in store.customPalettes)
                ListTile(
                  selected: store.paletteId == palette.id,
                  onTap: () => store.setPaletteId(palette.id),
                  leading: Icon(
                    store.paletteId == palette.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(palette.name),
                  trailing: IconButton(
                    tooltip: '编辑配色',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomThemeColorPage(
                          store: store,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
