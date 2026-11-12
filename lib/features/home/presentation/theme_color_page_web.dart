import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_store.dart';
import 'theme_color_page_shared.dart';

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
    return SharedThemeColorPage(
      store: store,
      onBack: onBack,
    );
  }
}
