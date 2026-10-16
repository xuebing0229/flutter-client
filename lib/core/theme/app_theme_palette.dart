import 'package:flutter/material.dart';

class AppThemeSemanticColors {
  const AppThemeSemanticColors({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.foreground,
    required this.mutedForeground,
    required this.border,
  });

  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color foreground;
  final Color mutedForeground;
  final Color border;

  factory AppThemeSemanticColors.fromSeed(
    Color seed,
    Brightness brightness,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return AppThemeSemanticColors(
      primary: scheme.primary,
      accent: scheme.secondary,
      background: scheme.surface,
      surface: scheme.surfaceContainerLow,
      surfaceAlt: scheme.surfaceContainer,
      foreground: scheme.onSurface,
      mutedForeground: scheme.onSurfaceVariant,
      border: scheme.outlineVariant,
    );
  }

  AppThemeSemanticColors copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? foreground,
    Color? mutedForeground,
    Color? border,
  }) {
    return AppThemeSemanticColors(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      border: border ?? this.border,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'primary': primary.toARGB32(),
        'accent': accent.toARGB32(),
        'background': background.toARGB32(),
        'surface': surface.toARGB32(),
        'surfaceAlt': surfaceAlt.toARGB32(),
        'foreground': foreground.toARGB32(),
        'mutedForeground': mutedForeground.toARGB32(),
        'border': border.toARGB32(),
      };

  static AppThemeSemanticColors? fromJson(Object? raw) {
    if (raw is! Map) return null;
    Color? color(String key) {
      final value = raw[key];
      return value is int ? Color(value) : null;
    }

    final primary = color('primary');
    final accent = color('accent');
    final background = color('background');
    final surface = color('surface');
    final surfaceAlt = color('surfaceAlt');
    final foreground = color('foreground');
    final mutedForeground = color('mutedForeground');
    final border = color('border');
    if (primary == null ||
        accent == null ||
        background == null ||
        surface == null ||
        surfaceAlt == null ||
        foreground == null ||
        mutedForeground == null ||
        border == null) {
      return null;
    }

    return AppThemeSemanticColors(
      primary: primary,
      accent: accent,
      background: background,
      surface: surface,
      surfaceAlt: surfaceAlt,
      foreground: foreground,
      mutedForeground: mutedForeground,
      border: border,
    );
  }

  List<Color> get previewColors => <Color>[
        primary,
        accent,
        background,
        surface,
        foreground,
      ];
}

class AppThemePalette {
  const AppThemePalette({
    required this.id,
    required this.name,
    required this.lightSeed,
    required this.previewColors,
    this.darkSeed,
    this.lightSemanticColors,
    this.darkSemanticColors,
    this.customAdvanced = false,
  });

  final String id;
  final String name;
  final Color lightSeed;
  final Color? darkSeed;
  final List<Color> previewColors;
  final AppThemeSemanticColors? lightSemanticColors;
  final AppThemeSemanticColors? darkSemanticColors;
  final bool customAdvanced;

  Color get effectiveDarkSeed => darkSeed ?? lightSeed;
  bool get isCustom => id.startsWith('custom:');

  AppThemeSemanticColors? semanticColorsFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? darkSemanticColors
          : lightSemanticColors;

  Map<String, dynamic> toCustomJson() {
    if (!isCustom ||
        lightSemanticColors == null ||
        darkSemanticColors == null) {
      throw StateError('Only complete custom palettes can be serialized.');
    }
    return <String, dynamic>{
      'id': id,
      'name': name,
      'lightSeed': lightSeed.toARGB32(),
      'darkSeed': effectiveDarkSeed.toARGB32(),
      'customAdvanced': customAdvanced,
      'light': lightSemanticColors!.toJson(),
      'dark': darkSemanticColors!.toJson(),
    };
  }

  static AppThemePalette? fromCustomJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final lightSeed = raw['lightSeed'];
    final darkSeed = raw['darkSeed'];
    final light = AppThemeSemanticColors.fromJson(raw['light']);
    final dark = AppThemeSemanticColors.fromJson(raw['dark']);
    if (id is! String ||
        !id.startsWith('custom:') ||
        name is! String ||
        lightSeed is! int ||
        light == null ||
        dark == null) {
      return null;
    }
    final resolvedDarkSeed = darkSeed is int ? Color(darkSeed) : Color(lightSeed);
    return AppThemePalette(
      id: id,
      name: name.trim().isEmpty ? '自定义配色' : name.trim(),
      lightSeed: Color(lightSeed),
      darkSeed: resolvedDarkSeed,
      previewColors: light.previewColors,
      lightSemanticColors: light,
      darkSemanticColors: dark,
      customAdvanced: raw['customAdvanced'] == true,
    );
  }

  static AppThemePalette custom({
    required String id,
    required String name,
    required Color seed,
    required AppThemeSemanticColors light,
    required AppThemeSemanticColors dark,
    required bool advanced,
  }) {
    return AppThemePalette(
      id: id.startsWith('custom:') ? id : 'custom:$id',
      name: name.trim().isEmpty ? '自定义配色' : name.trim(),
      lightSeed: seed,
      darkSeed: seed,
      previewColors: light.previewColors,
      lightSemanticColors: light,
      darkSemanticColors: dark,
      customAdvanced: advanced,
    );
  }
}

abstract final class AppThemePalettes {
  static const guildOriginal = AppThemePalette(
    id: 'guildOriginal',
    name: '公会原色',
    lightSeed: Color(0xFF6C7A6B),
    darkSeed: Color(0xFF90A58E),
    previewColors: <Color>[
      Color(0xFF6C7A6B),
      Color(0xFF90A58E),
      Color(0xFFDCE4DA),
    ],
  );

  static const tavernBell = AppThemePalette(
    id: 'tavernBell',
    name: '酒馆晚钟',
    lightSeed: Color(0xFF6C1A21),
    previewColors: <Color>[
      Color(0xFF6C1A21),
      Color(0xFFB92C2C),
      Color(0xFFCEA257),
      Color(0xFFD1BF9A),
      Color(0xFFE5E0CD),
    ],
  );

  static const clearSkyDew = AppThemePalette(
    id: 'clearSkyDew',
    name: '晴空晨露',
    lightSeed: Color(0xFF0097D0),
    previewColors: <Color>[
      Color(0xFF0097D0),
      Color(0xFF5EBFE0),
      Color(0xFFA6B7DD),
      Color(0xFFA4CDD1),
      Color(0xFFCBDBE1),
    ],
  );

  static const lateAutumnPost = AppThemePalette(
    id: 'lateAutumnPost',
    name: '晚秋驿站',
    lightSeed: Color(0xFFE4A273),
    previewColors: <Color>[
      Color(0xFF96B9B9),
      Color(0xFFB3BEAF),
      Color(0xFFE4A273),
      Color(0xFFC3A77F),
      Color(0xFFDADFDB),
    ],
  );

  static const rainbowCrystal = AppThemePalette(
    id: 'rainbowCrystal',
    name: '虹晶幻境',
    lightSeed: Color(0xFF9F99D1),
    previewColors: <Color>[
      Color(0xFF9F99D1),
      Color(0xFF86BADA),
      Color(0xFFDBAAD7),
      Color(0xFFF6BEB0),
      Color(0xFFFFE3B3),
    ],
  );

  static const deepBlueVow = AppThemePalette(
    id: 'deepBlueVow',
    name: '深蓝誓约',
    lightSeed: Color(0xFF2A5D85),
    previewColors: <Color>[
      Color(0xFF091831),
      Color(0xFF042B58),
      Color(0xFF2A5D85),
      Color(0xFF7394B7),
      Color(0xFFD0E5EF),
    ],
  );

  static const meadCampfire = AppThemePalette(
    id: 'meadCampfire',
    name: '蜜酒篝火',
    lightSeed: Color(0xFFB97621),
    previewColors: <Color>[
      Color(0xFF372111),
      Color(0xFF7E170D),
      Color(0xFFB97621),
      Color(0xFFCE9C6C),
      Color(0xFFEBCE79),
    ],
  );

  static const amberTreasure = AppThemePalette(
    id: 'amberTreasure',
    name: '琥珀瑰宝',
    lightSeed: Color(0xFFD48205),
    previewColors: <Color>[
      Color(0xFF442604),
      Color(0xFF876A58),
      Color(0xFFD48205),
      Color(0xFFFBBA42),
      Color(0xFFFCE8D0),
    ],
  );

  static const cherryPotion = AppThemePalette(
    id: 'cherryPotion',
    name: '樱桃药剂',
    lightSeed: Color(0xFFFF2446),
    previewColors: <Color>[
      Color(0xFFFF2446),
      Color(0xFFFF7C96),
      Color(0xFFF5B6C2),
      Color(0xFFD8C3C3),
      Color(0xFFE6E1E1),
    ],
  );

  static const emeraldValley = AppThemePalette(
    id: 'emeraldValley',
    name: '翠风溪谷',
    lightSeed: Color(0xFF03695E),
    previewColors: <Color>[
      Color(0xFF03695E),
      Color(0xFF6DAF5F),
      Color(0xFF239DCA),
      Color(0xFFA5C6DB),
      Color(0xFFE7E9D8),
    ],
  );

  static const roseCamp = AppThemePalette(
    id: 'roseCamp',
    name: '蔷薇营地',
    lightSeed: Color(0xFF9B5E61),
    previewColors: <Color>[
      Color(0xFF9B5E61),
      Color(0xFFE3A09A),
      Color(0xFF567F75),
      Color(0xFF96ABA2),
      Color(0xFFE9E7E5),
    ],
  );

  static const tidalSecret = AppThemePalette(
    id: 'tidalSecret',
    name: '潮汐秘境',
    lightSeed: Color(0xFF006863),
    previewColors: <Color>[
      Color(0xFF006863),
      Color(0xFF489D98),
      Color(0xFF49C7BC),
      Color(0xFFA0D4CD),
      Color(0xFFD0E4E1),
    ],
  );

  static const flowerMarket = AppThemePalette(
    id: 'flowerMarket',
    name: '花冠集市',
    lightSeed: Color(0xFFF9CF01),
    previewColors: <Color>[
      Color(0xFFF9CF01),
      Color(0xFFDEB073),
      Color(0xFF99A986),
      Color(0xFFADC4BE),
      Color(0xFFD3D3CA),
    ],
  );

  static const lemonMorning = AppThemePalette(
    id: 'lemonMorning',
    name: '柠光晨信',
    lightSeed: Color(0xFFF9D77C),
    previewColors: <Color>[
      Color(0xFFF9D77C),
      Color(0xFF8DA6D2),
    ],
  );

  static const peachWhisper = AppThemePalette(
    id: 'peachWhisper',
    name: '桃雾密语',
    lightSeed: Color(0xFFF2B6B6),
    previewColors: <Color>[
      Color(0xFFF2B6B6),
      Color(0xFF6A90A6),
    ],
  );

  static const mintFountain = AppThemePalette(
    id: 'mintFountain',
    name: '薄荷泉庭',
    lightSeed: Color(0xFFA9D8B7),
    previewColors: <Color>[
      Color(0xFFA9D8B7),
      Color(0xFF7BBFCF),
    ],
  );

  static const creamScroll = AppThemePalette(
    id: 'creamScroll',
    name: '奶油卷轴',
    lightSeed: Color(0xFFFBE2A2),
    previewColors: <Color>[
      Color(0xFFFBE2A2),
      Color(0xFF8C8C94),
    ],
  );

  static const all = <AppThemePalette>[
    guildOriginal,
    tavernBell,
    clearSkyDew,
    lateAutumnPost,
    rainbowCrystal,
    deepBlueVow,
    meadCampfire,
    amberTreasure,
    cherryPotion,
    emeraldValley,
    roseCamp,
    tidalSecret,
    flowerMarket,
    lemonMorning,
    peachWhisper,
    mintFountain,
    creamScroll,
  ];

  static AppThemePalette byId(String? id) {
    for (final palette in all) {
      if (palette.id == id) return palette;
    }
    return guildOriginal;
  }

  static bool containsId(String id) {
    return all.any((palette) => palette.id == id);
  }
}
