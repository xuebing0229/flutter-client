// Reference mapping is intentionally locked to the HTML files supplied in
// "14种经典的 UI/UX 设计风格". Do not reinterpret these names into a generic
// design-system preset:
// relief       -> neumorphism-components.html
// minimal      -> minimalism-components.html
// bold         -> neo-brutalism-components.html
// geometric    -> bauhaus-components.html
// retroLight   -> retrofuturism-components-light.html
// retroDark    -> retrofuturism-components.html
// fluorescent  -> acid-graphics-components(.light).html
// collage      -> anti-design-components-lite.html
// monochrome   -> brutalism-components.html
// clay         -> claymorphism-components.html
// glass        -> liquid-glass-components(.light).html
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
  // UI style and light/dark mode are independent. Only the two presets that
  // explicitly name their brightness keep a fixed base.
  bool get forcesLight => this == AppUiStyle.retroLight;
  bool get forcesDark => this == AppUiStyle.retroDark;

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
