import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class WebPickedScreenshot {
  const WebPickedScreenshot({
    required this.path,
    required this.name,
    this.temporary = true,
  });

  final String path;
  final String name;
  final bool temporary;
}

class WebScreenshotFiles {
  WebScreenshotFiles._();

  static final Random _random = Random.secure();
  static final Map<String, Uint8List> _files = <String, Uint8List>{};

  static Future<List<WebPickedScreenshot>> pickImages() async {
    const typeGroup = XTypeGroup(
      label: '截图',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    final selected = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    final result = <WebPickedScreenshot>[];
    for (final file in selected) {
      final bytes = await file.readAsBytes();
      final token =
          'web-shot-${DateTime.now().microsecondsSinceEpoch}-'
          '${_random.nextInt(0x7fffffff).toRadixString(36)}';
      _files[token] = Uint8List.fromList(bytes);
      result.add(
        WebPickedScreenshot(path: token, name: file.name, temporary: true),
      );
    }
    return result;
  }

  static Uint8List bytes(String path) {
    final bytes = _files[path];
    if (bytes == null) {
      throw StateError('所选截图已经释放，请重新选择。');
    }
    return bytes;
  }

  static void remove(String path) => _files.remove(path);

  static Widget image(String path, {BoxFit fit = BoxFit.contain}) {
    final bytes = _files[path];
    if (bytes == null) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    return Image.memory(bytes, fit: fit, gaplessPlayback: true);
  }
}
