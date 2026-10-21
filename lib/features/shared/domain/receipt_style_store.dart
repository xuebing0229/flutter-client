import 'package:flutter/foundation.dart';

class ReceiptStyleStore extends ChangeNotifier {
  static const int defaultFontColorValue = 0xFF000000;

  int _fontColorValue = defaultFontColorValue;
  String? _backgroundImageBase64;
  String? _backgroundImageName;

  int get fontColorValue => _fontColorValue;
  String? get backgroundImageBase64 => _backgroundImageBase64;
  String? get backgroundImageName => _backgroundImageName;

  void setFontColorValue(int value) {
    if (_fontColorValue == value) return;
    _fontColorValue = value;
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

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fontColorValue': _fontColorValue,
        if (_backgroundImageBase64 != null)
          'backgroundImageBase64': _backgroundImageBase64,
        if (_backgroundImageName != null)
          'backgroundImageName': _backgroundImageName,
      };

  void applyJson(Object? raw) {
    if (raw == null) {
      _fontColorValue = defaultFontColorValue;
      _backgroundImageBase64 = null;
      _backgroundImageName = null;
      notifyListeners();
      return;
    }
    if (raw is! Map) {
      throw const FormatException('同步小票样式格式无效。');
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final font = json['fontColorValue'];
    if (font != null && font is! int) {
      throw const FormatException('同步小票字体颜色格式无效。');
    }
    final background = json['backgroundImageBase64'];
    final name = json['backgroundImageName'];
    if (background != null && background is! String) {
      throw const FormatException('同步小票背景格式无效。');
    }
    if (name != null && name is! String) {
      throw const FormatException('同步小票背景名称格式无效。');
    }
    _fontColorValue = font is int ? font : defaultFontColorValue;
    _backgroundImageBase64 = background as String?;
    _backgroundImageName = name as String?;
    notifyListeners();
  }
}
