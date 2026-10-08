import '../domain/screenshot_layout_parser.dart';

class ScreenshotOcrResult {
  const ScreenshotOcrResult({
    required this.width,
    required this.height,
    required this.lines,
  });

  final double width;
  final double height;
  final List<ScreenshotTextLine> lines;
}
