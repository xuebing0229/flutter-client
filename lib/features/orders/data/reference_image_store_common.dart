import 'dart:convert';

class ReferenceImageRules {
  const ReferenceImageRules._();

  static const Set<String> supportedImageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
  };

  static String orderKey(String orderId) =>
      base64Url.encode(utf8.encode(orderId)).replaceAll('=', '');

  static String? safeExtension(String value) {
    final name = value.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final extension = name.substring(dot + 1).toLowerCase();
    if (extension.length > 8 ||
        !RegExp(r'^[a-z0-9]+$').hasMatch(extension)) {
      return null;
    }
    return '.$extension';
  }

  static String displayName(String value, String extension) {
    final name = value.split(RegExp(r'[\\/]')).last.trim();
    return name.isEmpty ? '参考图$extension' : name;
  }

  static String mimeType(String fileName) {
    final extension = safeExtension(fileName)?.toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      _ => 'application/octet-stream',
    };
  }

  static List<String> validateReferencePath(String value) {
    final segments = _safeFourSegmentPath(value, error: '参考图路径无效。');
    if (segments[0] != 'assets' ||
        segments[1] != 'order-reference-images') {
      throw const FormatException('参考图路径无效。');
    }
    return segments;
  }

  static List<String> validateAssetPath(String value) {
    final segments = _safeFourSegmentPath(value, error: '本地素材路径无效。');
    final referenceImage =
        segments[0] == 'assets' && segments[1] == 'order-reference-images';
    final desktopPet =
        segments[0] == 'desktop-pet' && segments[1] == 'presets';
    if (!referenceImage && !desktopPet) {
      throw const FormatException('本地素材路径无效。');
    }
    return segments;
  }

  static List<String> _safeFourSegmentPath(
    String value, {
    required String error,
  }) {
    if (value.contains('\\') || value.startsWith('/')) {
      throw FormatException(error);
    }
    final segments = value.split('/');
    if (segments.length != 4 || !segments.skip(2).every(isSafeSegment)) {
      throw FormatException(error);
    }
    return segments;
  }

  static bool isSafeSegment(String value) {
    if (value.isEmpty || value == '.' || value == '..') return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
  }
}
