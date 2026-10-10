import 'dart:io';

import 'package:flutter_app/features/imports/data/screenshot_import_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streamed image fingerprint retains the exact SHA-256 identity', () async {
    final temp = await Directory.systemTemp.createTemp('guild-ocr-hash-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/example.png');
    await file.writeAsBytes(<int>[97, 98, 99], flush: true);

    expect(
      await const ScreenshotImportHistory().hashImage(file.path),
      'ba7816bf8f01cfea414140de5dae2223b00361'
      'a396177a9cb410ff61f20015ad',
    );
  });
}
