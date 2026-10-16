enum AppUiStyle {
  classic(id: 'classic', label: '经典'),
  relief(id: 'relief', label: '浮雕'),
  minimal(id: 'minimal', label: '极简'),
  bold(id: 'bold', label: '粗边'),
  geometric(id: 'geometric', label: '几何'),
  retroLight(id: 'retro-light', label: '复古浅色'),
  retroDark(id: 'retro-dark', label: '复古深色'),
  fluorescent(id: 'fluorescent', label: '荧光'),
  collage(id: 'collage', label: '拼贴'),
  monochrome(id: 'monochrome', label: '黑白'),
  clay(id: 'clay', label: '黏土'),
  glass(id: 'glass', label: '玻璃');

  const AppUiStyle({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  bool get isClassic => this == AppUiStyle.classic;
  bool get isGlass => this == AppUiStyle.glass;
  bool get forcesLight =>
      this == AppUiStyle.relief ||
      this == AppUiStyle.minimal ||
      this == AppUiStyle.bold ||
      this == AppUiStyle.geometric ||
      this == AppUiStyle.retroLight ||
      this == AppUiStyle.collage ||
      this == AppUiStyle.monochrome ||
      this == AppUiStyle.clay;
  bool get forcesDark =>
      this == AppUiStyle.retroDark ||
      this == AppUiStyle.fluorescent ||
      this == AppUiStyle.glass;

  static AppUiStyle byId(String? id) {
    for (final value in AppUiStyle.values) {
      if (value.id == id) return value;
    }
    return AppUiStyle.classic;
  }

  static bool containsId(String id) =>
      AppUiStyle.values.any((value) => value.id == id);

  static AppUiStyle fromLegacyTextureId(String? id) {
    return switch (id) {
      'frosted' || 'liquid' => AppUiStyle.glass,
      _ => AppUiStyle.classic,
    };
  }
}
