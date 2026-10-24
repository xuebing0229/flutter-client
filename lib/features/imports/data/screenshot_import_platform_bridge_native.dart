import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/portability/data_portability_file_bridge.dart';

class ScreenshotImportPickedImage {
  const ScreenshotImportPickedImage({
    required this.path,
    required this.name,
    required this.temporary,
  });

  final String path;
  final String name;
  final bool temporary;
}

class ScreenshotImportPlatformBridge {
  const ScreenshotImportPlatformBridge();

  static const DataPortabilityFileBridge _files =
      DataPortabilityFileBridge();

  Future<List<ScreenshotImportPickedImage>> pickImages() async {
    final picked = await _files.pickImages();
    return <ScreenshotImportPickedImage>[
      for (final image in picked)
        ScreenshotImportPickedImage(
          path: image.path,
          name: image.name,
          temporary: image.temporary,
        ),
    ];
  }

  Future<void> deleteTemporaryImages(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Android picker copies live in app cache. If a native handle lingers,
        // the startup cache sweep can retry later.
      }
    }
  }

  Widget image(String path, {BoxFit fit = BoxFit.contain}) {
    return Image.file(File(path), fit: fit);
  }
}
