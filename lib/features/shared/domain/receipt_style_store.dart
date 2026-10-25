import 'package:flutter/foundation.dart';

class ReceiptStylePreset {
  const ReceiptStylePreset({
    required this.id,
    required this.name,
    required this.fontColorValue,
    this.headerText,
    this.backgroundImageBase64,
    this.backgroundImageName,
  });

  final String id;
  final String name;
  final int fontColorValue;
  final String? headerText;
  final String? backgroundImageBase64;
  final String? backgroundImageName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'fontColorValue': fontColorValue,
        if (headerText != null) 'headerText': headerText,
        if (backgroundImageBase64 != null)
          'backgroundImageBase64': backgroundImageBase64,
        if (backgroundImageName != null)
          'backgroundImageName': backgroundImageName,
      };

  factory ReceiptStylePreset.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final font = json['fontColorValue'];
    final headerText = json['headerText'];
    final background = json['backgroundImageBase64'];
    final backgroundName = json['backgroundImageName'];

    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('小票样式预设 ID 无效。');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('小票样式预设名称无效。');
    }
    if (font is! int) {
      throw const FormatException('小票样式预设字体颜色无效。');
    }
    if (headerText != null && headerText is! String) {
      throw const FormatException('小票样式预设抬头文字无效。');
    }
    if (background != null && background is! String) {
      throw const FormatException('小票样式预设背景无效。');
    }
    if (backgroundName != null && backgroundName is! String) {
      throw const FormatException('小票样式预设背景名称无效。');
    }

    return ReceiptStylePreset(
      id: id,
      name: name.trim(),
      fontColorValue: font,
      headerText: headerText as String?,
      backgroundImageBase64: background as String?,
      backgroundImageName: backgroundName as String?,
    );
  }
}

class ReceiptStyleStore extends ChangeNotifier {
  static const int defaultFontColorValue = 0xFF000000;

  int _fontColorValue = defaultFontColorValue;
  String? _headerText;
  String? _backgroundImageBase64;
  String? _backgroundImageName;
  final List<ReceiptStylePreset> _presets = <ReceiptStylePreset>[];

  int get fontColorValue => _fontColorValue;
  String? get headerText => _headerText;
  String? get backgroundImageBase64 => _backgroundImageBase64;
  String? get backgroundImageName => _backgroundImageName;
  List<ReceiptStylePreset> get presets =>
      List<ReceiptStylePreset>.unmodifiable(_presets);

  String effectiveHeaderText(String defaultHeaderText) =>
      _headerText ?? defaultHeaderText.trim();

  bool get isDefault =>
      _fontColorValue == defaultFontColorValue &&
      _headerText == null &&
      _backgroundImageBase64 == null;

  void setFontColorValue(int value) {
    if (_fontColorValue == value) return;
    _fontColorValue = value;
    notifyListeners();
  }

  /// null follows the account username; an empty string intentionally hides it.
  void setHeaderText(String? value) {
    if (_headerText == value) return;
    _headerText = value;
    notifyListeners();
  }

  void setBackgroundImage({
    required String base64,
    required String name,
  }) {
    _backgroundImageBase64 = base64;
    _backgroundImageName = name;
    notifyListeners();
  }

  void clearBackgroundImage() {
    if (_backgroundImageBase64 == null && _backgroundImageName == null) return;
    _backgroundImageBase64 = null;
    _backgroundImageName = null;
    notifyListeners();
  }

  void resetDefault() {
    final changed = !isDefault || _backgroundImageName != null;
    _fontColorValue = defaultFontColorValue;
    _headerText = null;
    _backgroundImageBase64 = null;
    _backgroundImageName = null;
    if (changed) notifyListeners();
  }

  ReceiptStylePreset saveCurrentPreset(
    String name, {
    required String resolvedHeaderText,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('小票样式预设名称不能为空。');
    }
    final preset = ReceiptStylePreset(
      id: 'receipt-style-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      fontColorValue: _fontColorValue,
      headerText: resolvedHeaderText,
      backgroundImageBase64: _backgroundImageBase64,
      backgroundImageName: _backgroundImageName,
    );
    _presets.add(preset);
    notifyListeners();
    return preset;
  }

  void applyPreset(String id) {
    final preset = _presets.where((item) => item.id == id).firstOrNull;
    if (preset == null) return;
    _fontColorValue = preset.fontColorValue;
    if (preset.headerText != null) {
      _headerText = preset.headerText;
    }
    _backgroundImageBase64 = preset.backgroundImageBase64;
    _backgroundImageName = preset.backgroundImageName;
    notifyListeners();
  }

  void deletePreset(String id) {
    final before = _presets.length;
    _presets.removeWhere((item) => item.id == id);
    if (_presets.length != before) notifyListeners();
  }

  ReceiptStylePreset importPreset(
    ReceiptStylePreset source, {
    bool apply = true,
  }) {
    final imported = ReceiptStylePreset(
      id: 'receipt-style-${DateTime.now().microsecondsSinceEpoch}',
      name: source.name,
      fontColorValue: source.fontColorValue,
      headerText: source.headerText,
      backgroundImageBase64: source.backgroundImageBase64,
      backgroundImageName: source.backgroundImageName,
    );
    _presets.add(imported);
    if (apply) {
      _fontColorValue = imported.fontColorValue;
      if (imported.headerText != null) {
        _headerText = imported.headerText;
      }
      _backgroundImageBase64 = imported.backgroundImageBase64;
      _backgroundImageName = imported.backgroundImageName;
    }
    notifyListeners();
    return imported;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fontColorValue': _fontColorValue,
        if (_headerText != null) 'headerText': _headerText,
        if (_backgroundImageBase64 != null)
          'backgroundImageBase64': _backgroundImageBase64,
        if (_backgroundImageName != null)
          'backgroundImageName': _backgroundImageName,
        'presets': <Map<String, dynamic>>[
          for (final preset in _presets) preset.toJson(),
        ],
      };

  void applyJson(Object? raw) {
    if (raw == null) {
      _fontColorValue = defaultFontColorValue;
      _headerText = null;
      _backgroundImageBase64 = null;
      _backgroundImageName = null;
      _presets.clear();
      notifyListeners();
      return;
    }
    if (raw is! Map) {
      throw const FormatException('同步小票样式格式无效。');
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final font = json['fontColorValue'];
    final headerText = json['headerText'];
    if (font != null && font is! int) {
      throw const FormatException('同步小票字体颜色格式无效。');
    }
    if (headerText != null && headerText is! String) {
      throw const FormatException('同步小票抬头文字格式无效。');
    }
    final background = json['backgroundImageBase64'];
    final name = json['backgroundImageName'];
    if (background != null && background is! String) {
      throw const FormatException('同步小票背景格式无效。');
    }
    if (name != null && name is! String) {
      throw const FormatException('同步小票背景名称格式无效。');
    }

    final rawPresets = json['presets'];
    if (rawPresets != null && rawPresets is! List) {
      throw const FormatException('同步小票样式预设格式无效。');
    }
    final presets = <ReceiptStylePreset>[];
    if (rawPresets is List) {
      for (final item in rawPresets) {
        if (item is! Map) {
          throw const FormatException('同步小票样式预设条目无效。');
        }
        presets.add(
          ReceiptStylePreset.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }

    _fontColorValue = font is int ? font : defaultFontColorValue;
    _headerText = headerText as String?;
    _backgroundImageBase64 = background as String?;
    _backgroundImageName = name as String?;
    _presets
      ..clear()
      ..addAll(presets);
    notifyListeners();
  }
}
