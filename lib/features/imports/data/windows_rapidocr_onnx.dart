import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';

/// Offline Paddle PP-OCRv3 via the bundled RapidOcrOnnx C++ executable.
/// This requires no Windows language packs and no server/API calls.
class WindowsRapidOcrOnnx {
  const WindowsRapidOcrOnnx();

  Future<ScreenshotOcrResult> recognize(String imageFile) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows OCR only');
    }
    final root = File(Platform.resolvedExecutable).parent.path;
    final engine = File('$root\\rapidocr\\RapidOcrOnnx.exe');
    final models = Directory('$root\\rapidocr\\models');
    if (!await engine.exists() || !await models.exists()) {
      throw StateError('离线中文 OCR 组件缺失，请安装完整 Windows 版本');
    }
    // Upstream CLI writes a result image and text alongside the input file.
    // Work on a temporary copy and always remove it after recognition.
    final temp = await Directory.systemTemp.createTemp('ag-screenshot-ocr-');
    try {
      final extension = imageFile.contains('.')
          ? imageFile.substring(imageFile.lastIndexOf('.'))
          : '.png';
      final local = '${temp.path}\\screenshot$extension';
      await File(imageFile).copy(local);
      final run = await Process.run(
        engine.path,
        [
          '--models', models.path.replaceAll(r'\\', '/'),
          '--det', 'ch_PP-OCRv3_det_infer.onnx',
          '--cls', 'ch_ppocr_mobile_v2.0_cls_infer.onnx',
          '--rec', 'ch_PP-OCRv3_rec_infer.onnx',
          '--keys', 'ppocr_keys_v1.txt',
          '--image', local.replaceAll(r'\\', '/'),
          '--padding', '0',
          '--maxSideLen', '0',
          '--numThread', '4',
          '--doAngle', '0',
          '--mostAngle', '0',
        ],
        workingDirectory: engine.parent.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 85));
      if (run.exitCode != 0) {
        throw StateError('OCR 识别未完成：${run.stderr}');
      }
      return parseRapidOnnxConsole(run.stdout as String);
    } finally {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {
        // Temporary cleanup should never erase successful OCR results.
      }
    }
  }
}

/// Parse RapidOcrOnnx's indexed textLine and TextBox logger entries into the
/// shared text geometry interface. Public for native-independent unit tests.
ScreenshotOcrResult parseRapidOnnxConsole(String output) {
  final size = RegExp(r'ScaleParam\(sw:(\d+),sh:(\d+),').firstMatch(output);
  if (size == null) {
    throw const FormatException('RapidOCR 未提供图片尺寸');
  }
  final width = double.parse(size.group(1)!);
  final height = double.parse(size.group(2)!);
  if (width <= 0 || height <= 0) {
    throw const FormatException('RapidOCR 图片尺寸无效');
  }

  final boxes = <int, List<double>>{};
  final words = <int, String>{};
  final boxPattern = RegExp(
    r'TextBox\[(\d+)\]\(\+padding\)\[score\([^)]+\),'
    r'\[x:\s*(-?\d+), y:\s*(-?\d+)\], '
    r'\[x:\s*(-?\d+), y:\s*(-?\d+)\], '
    r'\[x:\s*(-?\d+), y:\s*(-?\d+)\], '
    r'\[x:\s*(-?\d+), y:\s*(-?\d+)\]',
  );
  for (final match in boxPattern.allMatches(output)) {
    final index = int.parse(match.group(1)!);
    final values = [
      for (var k = 2; k <= 9; k++) double.parse(match.group(k)!),
    ];
    final xs = [values[0], values[2], values[4], values[6]];
    final ys = [values[1], values[3], values[5], values[7]];
    boxes[index] = [
      xs.reduce(math.min).clamp(0, width).toDouble(),
      ys.reduce(math.min).clamp(0, height).toDouble(),
      xs.reduce(math.max).clamp(0, width).toDouble(),
      ys.reduce(math.max).clamp(0, height).toDouble(),
    ];
  }

  final linePattern = RegExp(r'^textLine\[(\d+)\]\((.*)\)\r?$', multiLine: true);
  for (final match in linePattern.allMatches(output)) {
    words[int.parse(match.group(1)!)] = match.group(2)!.trim();
  }
  final lines = <ScreenshotTextLine>[];
  for (final index in words.keys.toList()..sort()) {
    final text = words[index]!;
    final rect = boxes[index];
    if (text.isEmpty || rect == null || rect[2] <= rect[0] ||
        rect[3] <= rect[1]) {
      continue;
    }
    lines.add(ScreenshotTextLine(
      text: text,
      left: rect[0],
      top: rect[1],
      right: rect[2],
      bottom: rect[3],
    ));
  }
  if (lines.isEmpty) {
    throw const FormatException('RapidOCR 没有输出有效文字');
  }
  return ScreenshotOcrResult(
    width: width,
    height: height,
    lines: List.unmodifiable(lines),
  );
}
