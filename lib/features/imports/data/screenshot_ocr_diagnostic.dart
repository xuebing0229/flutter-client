import 'screenshot_ocr_result.dart';

/// Local-only, opt-in debug text. Never includes paths, image bytes, file
/// hashes, account identifiers, or automatic network submission.
///
/// Recognized text can still include customer names and prices. The app must
/// explicitly warn the user before copying it to their clipboard.
String formatScreenshotOcrDiagnostic({
  required int screenshotNumber,
  required ScreenshotOcrResult ocr,
  required String route,
  required String platform,
  required Iterable<String> parsedRows,
}) {
  final result = StringBuffer()
    ..writeln('截图 $screenshotNumber')
    ..writeln('图片尺寸: ${ocr.width.toStringAsFixed(0)} × ${ocr.height.toStringAsFixed(0)}')
    ..writeln('页面识别: $route')
    ..writeln('识别平台: $platform')
    ..writeln('原始 OCR (${ocr.lines.length} 行; 坐标为左/上/右/下):');

  final lines = [...ocr.lines]..sort((a, b) {
    final y = a.top.compareTo(b.top);
    return y != 0 ? y : a.left.compareTo(b.left);
  });
  for (final line in lines) {
    final rect = [
      line.left, line.top, line.right, line.bottom,
    ].map((value) => value.toStringAsFixed(0)).join(',');
    result.writeln('[$rect] ${line.text}');
  }
  final rows = parsedRows.toList();
  result.writeln('解析出的记录 (${rows.length} 条):');
  for (var index = 0; index < rows.length; index++) {
    result.writeln('  ${index + 1}. ${rows[index]}');
  }
  return result.toString();
}
