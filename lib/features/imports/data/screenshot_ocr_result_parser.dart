import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';

ScreenshotOcrResult parseScreenshotOcrPayload(
  Map raw, {
  List<String> fallbackTrace = const <String>[],
}) {
  double number(Object? value, String field) {
    if (value is num) return value.toDouble();
    throw FormatException('截图识别结果缺少 $field');
  }

  final rawLines = raw['lines'];
  if (rawLines is! List) {
    throw const FormatException('截图识别结果格式无效');
  }

  final lines = <ScreenshotTextLine>[];
  for (final item in rawLines) {
    if (item is! Map || item['text'] is! String) continue;
    lines.add(
      ScreenshotTextLine(
        text: item['text'] as String,
        recoveredFromCrop: item['recoveredFromCrop'] == true,
        left: number(item['left'], 'left'),
        top: number(item['top'], 'top'),
        right: number(item['right'], 'right'),
        bottom: number(item['bottom'], 'bottom'),
        confidence: item['confidence'] is num
            ? (item['confidence'] as num).toDouble()
            : 1,
      ),
    );
  }

  final width = number(raw['imageWidth'], 'imageWidth');
  final height = number(raw['imageHeight'], 'imageHeight');
  if (width <= 0 || height <= 0) {
    throw const FormatException('截图尺寸无效');
  }

  final trace = raw['nativeTrace'];
  return ScreenshotOcrResult(
    width: width,
    height: height,
    lines: List<ScreenshotTextLine>.unmodifiable(lines),
    nativeTrace: List<String>.unmodifiable(
      trace is List ? trace.whereType<String>() : fallbackTrace,
    ),
  );
}
