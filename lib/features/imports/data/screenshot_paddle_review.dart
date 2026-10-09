import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';

/// The second engine never changes dates, money, order count or card anchors.
/// It is used only for uncertain buyer/title text in MiHuashi screenshots.
class PaddleFieldReview {
  const PaddleFieldReview({this.buyer, this.title});
  final String? buyer;
  final String? title;
}

class PaddleFieldText {
  const PaddleFieldText(this.text, this.confidence, this.centerY);
  final String text;
  final double confidence;
  final double centerY;
}

/// A conservative, platform-independent ranking step. Do not copy prices,
/// stage labels or texts from a neighboring order into a buyer field.
String? bestPaddleText(
  Iterable<PaddleFieldText> readings, {
  required bool isBuyer,
  required double preferredY,
}) {
  final ranked = <(PaddleFieldText, double)>[];
  for (final reading in readings) {
    final text = reading.text.trim().replaceFirst(RegExp(r'\s*[›＞>》»]\s*$'), '');
    if (text.isEmpty || reading.confidence < 0.42) continue;
    if (RegExp(r'\d{4}[-/.年]\d|[¥￥]|\d+%').hasMatch(text)) continue;
    const rejected = [
      '添加备注', '定向企划', '全额支付', '进行中', '已完成',
      '当前交付节点', '截稿时间', '购买时间', '待交稿', '稿件夹',
    ];
    if (rejected.any((label) => text.contains(label))) continue;
    if (isBuyer && (text.contains('【') || text.length > 35)) continue;
    if (!isBuyer && text.length < 2) continue;
    final delta = (reading.centerY - preferredY).abs();
    // Multiple OCR boxes in a crop are common; focus on the intended row.
    final score = reading.confidence * 100 - delta * 0.35 +
        math.min(text.runes.length, 20) * 0.5;
    ranked.add((PaddleFieldText(text, reading.confidence, reading.centerY), score));
  }
  ranked.sort((a, b) => b.$2.compareTo(a.$2));
  return ranked.isEmpty ? null : ranked.first.$1.text;
}

bool shouldPaddleReviewBuyer(ScreenshotOrderCandidate row) =>
    row.clientName.trim().isEmpty ||
    (row.clientBox?.recoveredFromCrop ?? false);

bool shouldPaddleReviewTitle(ScreenshotOrderCandidate row) {
  final raw = row.titleBox?.text ?? row.title;
  return raw.contains('【') && !raw.contains('】') ||
      raw.contains('�');
}

/// PaddleOCR / PP-OCRv6 small runs entirely offline, only after a suspicious
/// ML Kit result. All cropped images are deleted, even on native OCR failure.
class ScreenshotPaddleReviewService {
  final PaddleOcr _engine = PaddleOcr();
  bool _initialized = false;

  // A native SIGABRT/SIGSEGV or Android low-memory process kill cannot be
  // caught by Dart. Keep an on-disk stage marker before each native call:
  // after an interrupted stage, disable Paddle for the rest of this build.
  // ML Kit remains available for all normal imports.
  Future<File> _crashMarker() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/paddle-ocr-native-v115.running');
  }

  Future<void> _nativeStageStart(String stage) async {
    final marker = await _crashMarker();
    if (await marker.exists()) {
      final oldStage = await marker.readAsString();
      throw StateError('PaddleOCR 上次运行未正常结束（$oldStage），'
          '本版本已自动停用第二引擎以避免连续闪退。原 ML Kit 仍可正常识别。');
    }
    await marker.writeAsString(stage, flush: true);
  }

  Future<void> _nativeStageEnd() async {
    final marker = await _crashMarker();
    if (await marker.exists()) await marker.delete();
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _nativeStageStart('初始化模型');
    try {
      await _engine.init(engine: const EngineConfig(numThreads: 1));
      _initialized = true;
    } finally {
      await _nativeStageEnd();
    }
  }

  /// Run PP-OCRv6 on bounded vertical tiles instead of passing the entire
  /// image to OpenCV and ONNX at once. Preserve original coordinates/scale,
  /// text sizes and the main ML Kit import result. All images remain local.
  /// A crash marker prevents repeatedly killing the app on native failure.
  Future<ScreenshotOcrResult?> recognizeFullImage({
    required String imagePath,
    required double imageWidth,
    required double imageHeight,
    required List<String> diagnostics,
    void Function(String stage)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      diagnostics.add('PaddleOCR 对照目前仅支持 Android');
      return null;
    }
    final clock = Stopwatch()..start();
    Directory? workDir;
    try {
      onProgress?.call('初始化（首次可能较慢）');
      await _ensureInitialized();
      final source = img.decodeImage(await File(imagePath).readAsBytes());
      if (source == null) throw const FormatException('截图解码失败');
      // The detector already resizes its input, but the old full-image path
      // first allocated a native full-size ARGB bitmap. Limit that footprint.
      const tileHeight = 720;
      const overlap = 120;
      const stride = tileHeight - overlap;
      final n = source.height <= tileHeight
          ? 1
          : ((source.height - tileHeight + stride - 1) ~/ stride) + 1;
      final sx = imageWidth / source.width;
      final sy = imageHeight / source.height;
      final found = <ScreenshotTextLine>[];
      workDir = await Directory.systemTemp.createTemp('ag-ocr-tiles-');
      diagnostics.add('PaddleOCR 分片安全模式：$n 片，'
          '每片最多 $tileHeight 像素高，重叠 $overlap 像素');
      var nativeMs = 0;
      for (var index = 0; index < n; index++) {
        final top = index * stride;
        final height = math.min(tileHeight, source.height - top);
        final crop = img.copyCrop(source, x: 0, y: top,
            width: source.width, height: height);
        final path = '${workDir.path}/tile.png';
        await File(path).writeAsBytes(img.encodePng(crop), flush: true);
        onProgress?.call('分片 ${index + 1}/$n');
        await _nativeStageStart('识别分片 ${index + 1}/$n');
        try {
          final run = await _engine.recognize(path)
              .timeout(const Duration(seconds: 35));
          nativeMs += run.totalTimeMs;
          for (final result in run.results) {
            final box = result.boundingBox;
            final center = top + box.center.dy;
            // Keep only the middle half of an overlap, assigning a
            // line to exactly one tile instead of duplicating a card.
            if (index > 0 && center < top + overlap / 2) continue;
            if (index < n - 1 && center >= top + height - overlap / 2) {
              continue;
            }
            found.add(ScreenshotTextLine(
              text: result.text,
              left: box.left * sx, right: box.right * sx,
              top: (box.top + top) * sy,
              bottom: (box.bottom + top) * sy,
            ));
            diagnostics.add('PaddleOCR 置信度 '
                '${result.confidence.toStringAsFixed(3)}'
                ' | ${result.text}');
          }
          diagnostics.add('PaddleOCR 分片 ${index + 1}/$n：'
              '${run.results.length} 行，推理 ${run.totalTimeMs} ms');
        } finally {
          await _nativeStageEnd();
          try { await File(path).delete(); } catch (_) {}
        }
      }
      found.sort((a, b) {
        final byY = a.top.compareTo(b.top);
        return byY == 0 ? a.left.compareTo(b.left) : byY;
      });
      diagnostics.add('PaddleOCR 分片合并：${found.length} 行，'
          '推理合计 $nativeMs ms，总耗时 ${clock.elapsedMilliseconds} ms');
      return ScreenshotOcrResult(
        width: imageWidth,
        height: imageHeight,
        lines: List.unmodifiable(found),
      );
    } catch (error) {
      diagnostics.add('PaddleOCR 安全对照失败：$error'
          '（${clock.elapsedMilliseconds} ms；原 ML Kit 结果保留）');
      return null;
    } finally {
      clock.stop();
      if (workDir != null) {
        try { await workDir.delete(recursive: true); } catch (_) {}
      }
    }
  }

  Future<List<PaddleFieldReview>> review({
    required String imagePath,
    required double imageWidth,
    required double imageHeight,
    required List<ScreenshotOrderCandidate> rows,
    required List<String> diagnostics,
  }) async {
    final needed = rows.any((row) =>
        shouldPaddleReviewBuyer(row) || shouldPaddleReviewTitle(row));
    if (!Platform.isAndroid || !needed) {
      return List.filled(rows.length, const PaddleFieldReview());
    }

    final results = <PaddleFieldReview>[];
    img.Image? source;
    try {
      source = img.decodeImage(await File(imagePath).readAsBytes());
      if (source == null) throw const FormatException('图片解码失败');
      await _ensureInitialized();
    } catch (error) {
      diagnostics.add('PaddleOCR 初始化不可用：$error；保留原 OCR');
      return List.filled(rows.length, const PaddleFieldReview());
    }

    for (final row in rows) {
      String? buyer;
      String? title;
      final titleBox = row.titleBox;
      if (titleBox != null) {
        if (shouldPaddleReviewBuyer(row)) {
          // The buyer line in MiHuashi list sits roughly 100-180 source
          // pixels above the artwork title. Avoid the avatar and title.
          buyer = await _recognizeCrop(
            source, imagePath,
            imageWidth: imageWidth, imageHeight: imageHeight,
            left: imageWidth * 0.155,
            top: titleBox.centerY - 215,
            right: imageWidth * 0.66,
            bottom: titleBox.centerY - 48,
            targetRatio: 0.52,
            isBuyer: true,
            diagnostics: diagnostics,
          );
        }
        if (shouldPaddleReviewTitle(row)) {
          title = await _recognizeCrop(
            source, imagePath,
            imageWidth: imageWidth, imageHeight: imageHeight,
            left: titleBox.left - 25,
            top: titleBox.top - 32,
            right: math.min(imageWidth - 5, titleBox.right + 90),
            bottom: titleBox.bottom + 36,
            targetRatio: 0.5,
            isBuyer: false,
            diagnostics: diagnostics,
          );
        }
      }
      if (buyer == row.clientName.trim()) buyer = null;
      if (title == row.title.trim()) title = null;
      results.add(PaddleFieldReview(buyer: buyer, title: title));
    }
    return results;
  }

  Future<String?> _recognizeCrop(
    img.Image source,
    String imagePath, {
    required double imageWidth,
    required double imageHeight,
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double targetRatio,
    required bool isBuyer,
    required List<String> diagnostics,
  }) async {
    final sx = source.width / imageWidth;
    final sy = source.height / imageHeight;
    final x1 = (left * sx).floor().clamp(0, source.width - 1).toInt();
    final y1 = (top * sy).floor().clamp(0, source.height - 1).toInt();
    final x2 = (right * sx).ceil().clamp(x1 + 1, source.width).toInt();
    final y2 = (bottom * sy).ceil().clamp(y1 + 1, source.height).toInt();
    if (x2 - x1 < 12 || y2 - y1 < 12) return null;

    final tempDir = await Directory.systemTemp.createTemp('ag-paddle-');
    try {
      final crop = img.copyCrop(source, x: x1, y: y1,
          width: x2 - x1, height: y2 - y1);
      final enlarged = img.copyResize(
        crop, width: (crop.width * 2).clamp(24, 1800).toInt(),
        interpolation: img.Interpolation.cubic,
      );
      final path = '${tempDir.path}/region.png';
      await File(path).writeAsBytes(img.encodePng(enlarged));
      await _nativeStageStart('局部文字重识别');
      late final OcrRunResult run;
      try {
        run = await _engine.recognize(path)
            .timeout(const Duration(seconds: 25));
      } finally {
        await _nativeStageEnd();
      }
      final reading = bestPaddleText(
        run.results.map((r) => PaddleFieldText(
          r.text, r.confidence, r.boundingBox.center.dy,
        )),
        isBuyer: isBuyer,
        preferredY: enlarged.height * targetRatio,
      );
      diagnostics.add('${isBuyer ? "单主" : "图名"}区域 PaddleOCR '
          '${run.totalTimeMs}ms: '
          '${run.results.map((r) => "${r.text}(${r.confidence.toStringAsFixed(2)})").join(" | ")}');
      return reading;
    } catch (error) {
      diagnostics.add('${isBuyer ? "单主" : "图名"}区域 PaddleOCR 不可用：$error');
      return null;
    } finally {
      try { await tempDir.delete(recursive: true); } catch (_) {}
    }
  }

  /// Keep the native model between screenshots in one import batch.
  Future<void> dispose() async {
    if (_initialized) {
      _initialized = false;
      try {
        await _nativeStageStart('卸载模型');
        try {
          await _engine.dispose();
        } finally {
          await _nativeStageEnd();
        }
      } catch (_) {
        // The primary ML Kit import must remain usable.
      }
    }
  }
}
