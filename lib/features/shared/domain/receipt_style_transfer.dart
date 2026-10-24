import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'receipt_style_store.dart';

class ReceiptStyleTransfer {
  const ReceiptStyleTransfer();

  static const String marker = '\nAGRECEIPT1\n';
  static final Uint8List _markerBytes = Uint8List.fromList(utf8.encode(marker));

  Uint8List attachPresetToPng(
    Uint8List pngBytes,
    ReceiptStylePreset preset,
  ) {
    final payload = <String, dynamic>{
      'type': 'adventurer-guild-receipt-style',
      'version': 1,
      'preset': preset.toJson(),
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressed = gzip.encode(jsonBytes);
    final encoded = utf8.encode(base64UrlEncode(compressed));

    return Uint8List.fromList(<int>[
      ...pngBytes,
      ..._markerBytes,
      ...encoded,
    ]);
  }

  ReceiptStylePreset decodePresetFromImage(Uint8List bytes) {
    final markerIndex = _lastIndexOf(bytes, _markerBytes);
    if (markerIndex < 0) {
      throw const FormatException(
        '这张图片不是冒险者公会小票预设分享图，或分享平台重新压缩了图片。',
      );
    }

    final encoded = utf8
        .decode(bytes.sublist(markerIndex + _markerBytes.length))
        .trim();
    if (encoded.isEmpty) {
      throw const FormatException('小票预设分享图没有包含可读取的数据。');
    }

    Object? raw;
    try {
      final compressed = base64Url.decode(_normalizeBase64(encoded));
      final jsonBytes = gzip.decode(compressed);
      raw = jsonDecode(utf8.decode(jsonBytes));
    } catch (_) {
      throw const FormatException('小票预设分享数据已损坏。');
    }

    if (raw is! Map) {
      throw const FormatException('小票预设分享数据格式无效。');
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    if (map['type'] != 'adventurer-guild-receipt-style' ||
        map['version'] != 1) {
      throw const FormatException('这不是支持的小票预设分享图。');
    }
    final presetRaw = map['preset'];
    if (presetRaw is! Map) {
      throw const FormatException('小票预设内容缺失。');
    }
    return ReceiptStylePreset.fromJson(
      presetRaw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  int _lastIndexOf(Uint8List source, Uint8List needle) {
    if (needle.isEmpty || source.length < needle.length) return -1;
    for (var i = source.length - needle.length; i >= 0; i--) {
      var matches = true;
      for (var j = 0; j < needle.length; j++) {
        if (source[i + j] != needle[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i;
    }
    return -1;
  }

  String _normalizeBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value.padRight(value.length + (4 - remainder), '=');
  }
}
