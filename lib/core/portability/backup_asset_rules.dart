class BackupAssetRules {
  const BackupAssetRules._();

  static const String manifestFileName = 'backup.json';

  static bool isSafeArchivePath(String value) {
    if (value.isEmpty || value.contains('\\')) return false;
    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }
    final segments = value
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return false;
    return !segments.any((segment) => segment == '.' || segment == '..');
  }

  static bool isDesktopPetAssetPath(String value) {
    if (!isSafeArchivePath(value)) return false;
    final segments = value.split('/');
    return segments.length == 4 &&
        segments[0] == 'desktop-pet' &&
        segments[1] == 'presets' &&
        segments.skip(2).every(_safeSegment);
  }

  static bool isReferenceAssetPath(String value) {
    if (!isSafeArchivePath(value)) return false;
    final segments = value.split('/');
    return segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images' &&
        segments.skip(2).every(_safeSegment);
  }

  static bool isAllowedAssetPath(String value) =>
      isReferenceAssetPath(value) || isDesktopPetAssetPath(value);

  static Set<String> desktopPetAssetPaths(
    Object? rawManifest, {
    bool strict = false,
  }) {
    if (rawManifest == null) return const <String>{};
    if (rawManifest is! Map || rawManifest['schema'] != 1) {
      if (strict) throw const FormatException('桌宠备份设置格式无效。');
      return const <String>{};
    }
    final rawPresets = rawManifest['presets'];
    if (rawPresets is! List) {
      if (strict) throw const FormatException('桌宠备份缺少预设列表。');
      return const <String>{};
    }

    final result = <String>{};
    for (final preset in rawPresets) {
      if (preset is! Map) {
        if (strict) throw const FormatException('桌宠备份包含无效预设。');
        continue;
      }
      for (final key in const <String>['imageA', 'imageB', 'bubbleImage']) {
        final value = preset[key];
        if (value == null) continue;
        if (value is! String || !isDesktopPetAssetPath(value)) {
          if (strict) throw const FormatException('桌宠备份素材路径无效。');
          continue;
        }
        result.add(value);
      }
    }
    return result;
  }

  static bool _safeSegment(String segment) =>
      segment.isNotEmpty &&
      segment != '.' &&
      segment != '..' &&
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment);
}
