enum AppUiTexture {
  classic(
    id: 'classic',
    label: '经典',
    description: '保留当前公会界面，不增加玻璃材质效果。',
  ),
  frosted(
    id: 'frosted',
    label: '毛玻璃',
    description: '仅导航与浮层使用磨砂玻璃，内容区域保持清晰。',
  ),
  liquid(
    id: 'liquid',
    label: '液态玻璃',
    description: '平台自适应高级质感；非 Apple 平台不伪造折射。',
  );

  const AppUiTexture({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  bool get isGlass => this != AppUiTexture.classic;

  static AppUiTexture byId(String? id) {
    for (final value in AppUiTexture.values) {
      if (value.id == id) return value;
    }
    return AppUiTexture.classic;
  }

  static bool containsId(String id) =>
      AppUiTexture.values.any((value) => value.id == id);
}
