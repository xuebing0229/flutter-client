import 'package:flutter/material.dart';

import 'web_screenshot_files.dart';

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

  Future<List<ScreenshotImportPickedImage>> pickImages() async {
    final picked = await WebScreenshotFiles.pickImages();
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
      WebScreenshotFiles.remove(path);
    }
  }

  Widget image(String path, {BoxFit fit = BoxFit.contain}) {
    return WebScreenshotFiles.image(path, fit: fit);
  }
}
