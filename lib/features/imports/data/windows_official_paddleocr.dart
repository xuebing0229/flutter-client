import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';

/// Offline Windows OCR using PaddleOCR's official C++ inference pipeline.
///
/// The Windows package bundles the official PaddleOCR C++ executable,
/// Paddle Inference runtime and PP-OCRv6 Small detection/recognition models.
/// No Python installation, language pack, server or API is required.
class WindowsOfficialPaddleOcr {
  const WindowsOfficialPaddleOcr();

  Future<ScreenshotOcrResult> recognize(String imageFile) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows OCR only');
    }

    final root = File(Platform.resolvedExecutable).parent.path;
    final runtime = Directory('\${root}\\\\paddleocr');
    final engine = File('\${root}\\\\paddleocr\\\\ppocr.exe');
    final detModel =
        Directory('\${root}\\\\paddleocr\\\\models\\\\PP-OCRv6_small_det_infer');
    final recModel =
        Directory('\${root}\\\\paddleocr\\\\models\\\\PP-OCRv6_small_rec_infer');
    if (!await engine.exists() ||
        !await detModel.exists() ||
        !await recModel.exists()) {
      throw StateError('官方 PaddleOCR 离线组件缺失，请安装完整 Windows 版本');
    }

    final sourceBytes = await File(imageFile).readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const FormatException('OCR 图片尺寸无效');
    }

    final temp = await Directory.systemTemp.createTemp('ag-paddleocr-');
    try {
      final extension = imageFile.contains('.')
          ? imageFile.substring(imageFile.lastIndexOf('.'))
          : '.png';
      final local = File('\${temp.path}\\\\screenshot\$extension');
      await local.writeAsBytes(sourceBytes, flush: true);
      final output = Directory('\${temp.path}\\\\output');
      await output.create(recursive: true);

      String slash(String value) =>
          value.replaceAll(String.fromCharCode(92), '/');

      final run = await Process.run(
        engine.path,
        [
          'ocr',
          '--input',
          slash(local.path),
          '--save_path',
          slash(output.path),
          '--text_detection_model_name',
          'PP-OCRv6_small_det',
          '--text_detection_model_dir',
          slash(detModel.path),
          '--text_recognition_model_name',
          'PP-OCRv6_small_rec',
          '--text_recognition_model_dir',
          slash(recModel.path),
          '--use_doc_orientation_classify',
          'false',
          '--use_doc_unwarping',
          'false',
          '--use_textline_orientation',
          'false',
          '--text_rec_score_thresh',
          '0',
          '--device',
          'cpu',
          '--cpu_threads',
          '4',
          '--enable_mkldnn',
          'true',
        ],
        workingDirectory: runtime.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 120));

      if (run.exitCode != 0) {
        throw StateError(
          'PaddleOCR 识别未完成：'
          '\${(run.stderr as String).trim().isEmpty ? run.stdout : run.stderr}',
        );
      }

      final expected = File('\${output.path}\\\\screenshot.json');
      File? resultFile;
      if (await expected.exists()) {
        resultFile = expected;
      } else {
        final files = await output
            .list()
            .where((entry) => entry is File && entry.path.endsWith('.json'))
            .cast<File>()
            .toList();
        if (files.length == 1) resultFile = files.single;
      }
      if (resultFile == null) {
        throw const FormatException('PaddleOCR 未生成可读取的 JSON 结果');
      }

      return parseOfficialPaddleOcrJson(
        await resultFile.readAsString(),
        imageWidth: decoded.width.toDouble(),
        imageHeight: decoded.height.toDouble(),
      );
    } finally {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Parses PaddleOCR C++ pipeline JSON into the geometry format shared by
/// Android and all existing screenshot parsers.
ScreenshotOcrResult parseOfficialPaddleOcrJson(
  String source, {
  required double imageWidth,
  required double imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw const FormatException('OCR 图片尺寸无效');
  }
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('PaddleOCR JSON 格式错误');
  }

  final rawTexts = decoded['rec_texts'];
  final rawBoxes = decoded['rec_boxes'];
  if (rawTexts is! List || rawBoxes is! List) {
    throw const FormatException('PaddleOCR 缺少文字或坐标结果');
  }

  final count = math.min(rawTexts.length, rawBoxes.length);
  final lines = <ScreenshotTextLine>[];
  for (var index = 0; index < count; index++) {
    final textValue = rawTexts[index];
    final boxValue = rawBoxes[index];
    if (textValue is! String || boxValue is! List || boxValue.length < 4) {
      continue;
    }
    final text = textValue.trim();
    if (text.isEmpty) continue;

    double number(Object? value) {
      if (value is num) return value.toDouble();
      throw const FormatException('PaddleOCR 坐标格式错误');
    }

    final left = number(boxValue[0]).clamp(0, imageWidth).toDouble();
    final top = number(boxValue[1]).clamp(0, imageHeight).toDouble();
    final right = number(boxValue[2]).clamp(0, imageWidth).toDouble();
    final bottom = number(boxValue[3]).clamp(0, imageHeight).toDouble();
    if (right <= left || bottom <= top) continue;

    lines.add(
      ScreenshotTextLine(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ),
    );
  }

  if (lines.isEmpty) {
    throw const FormatException('PaddleOCR 没有输出有效文字');
  }

  return ScreenshotOcrResult(
    width: imageWidth,
    height: imageHeight,
    lines: List<ScreenshotTextLine>.unmodifiable(lines),
    nativeTrace: const <String>[
      'Windows OCR: official PaddleOCR C++ + Paddle Inference + PP-OCRv6 Small',
    ],
  );
}
