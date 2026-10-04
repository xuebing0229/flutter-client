import 'package:flutter/material.dart';

class AppThemePalette {
  const AppThemePalette({
    required this.id,
    required this.name,
    required this.lightSeed,
    required this.previewColors,
    this.darkSeed,
  });

  final String id;
  final String name;
  final Color lightSeed;
  final Color? darkSeed;
  final List<Color> previewColors;

  Color get effectiveDarkSeed => darkSeed ?? lightSeed;
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
