enum AppUiTexture {
  classic(
    id: 'classic',
    label: '经典',
    description: '保留当前公会界面，不增加玻璃材质效果。',
  ),
  frosted(
    id: 'frosted',
    label: '毛玻璃',
    description: '柔和磨砂与半透明层次，背景会轻微虚化。',
  ),
  liquid(
    id: 'liquid',
    label: '液态玻璃',
    description: '更通透的玻璃、高光与边缘层次。',
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
