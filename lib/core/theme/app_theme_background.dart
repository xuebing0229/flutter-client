enum AppAppearanceMode {
  color(id: 'color', label: '彩色主题'),
  image(id: 'image', label: '图片主题');

  const AppAppearanceMode({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  static AppAppearanceMode byId(String? id) {
    for (final value in AppAppearanceMode.values) {
      if (value.id == id) return value;
    }
    return AppAppearanceMode.color;
  }
}

enum AppImageBackgroundMode {
  cover(
    id: 'cover',
    label: '全图覆盖',
    description: '背景图直接铺满整个界面，控件底色隐藏，只保留文字、图标和必要边框。',
  ),
  glass(
    id: 'glass',
    label: '玻璃透明',
    description: '背景图位于最底层，卡片、面板和控件使用透明玻璃效果。',
  );

  const AppImageBackgroundMode({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  static AppImageBackgroundMode byId(String? id) {
    for (final value in AppImageBackgroundMode.values) {
      if (value.id == id) return value;
    }
    return AppImageBackgroundMode.glass;
  }
}
