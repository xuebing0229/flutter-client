import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = File(
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  );
  if (!source.existsSync()) {
    stderr.writeln('Android launcher icon not found: ${source.path}');
    exitCode = 1;
    return;
  }

  final decoded = img.decodePng(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Android launcher icon is not a valid PNG.');
    exitCode = 1;
    return;
  }

  final outputDir = Directory('web/icons')..createSync(recursive: true);

  void write(String name, int size) {
    final resized = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    File('${outputDir.path}/$name').writeAsBytesSync(
      img.encodePng(resized, level: 9),
      flush: true,
    );
  }

  write('app-icon-192.png', 192);
  write('app-icon-512.png', 512);

  // The Android launcher PNG already contains the final framed composition.
  // Marking that same bitmap as a maskable full-bleed icon makes Chromium
  // enlarge/crop it again, so the installed PWA no longer matches the app.
  final staleMaskable = File('${outputDir.path}/app-icon-maskable-512.png');
  if (staleMaskable.existsSync()) {
    staleMaskable.deleteSync();
  }
}
