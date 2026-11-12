import 'package:flutter/material.dart';

import 'screenshot_import_platform_types.dart';
import 'web_screenshot_files.dart';

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
