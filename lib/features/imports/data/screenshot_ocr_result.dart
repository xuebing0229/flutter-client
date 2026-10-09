import '../domain/screenshot_layout_parser.dart';

class ScreenshotOcrResult {
  const ScreenshotOcrResult({
    required this.width,
    required this.height,
    required this.lines,
    this.nativeTrace = const <String>[],
  });

  final double width;
  final double height;
  final List<ScreenshotTextLine> lines;
  /// Optional local, opt-in diagnostics from Android crop retries.
  final List<String> nativeTrace;
}
