import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

import '../domain/screenshot_layout_parser.dart';

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
      await _engine.init(engine: const EngineConfig(numThreads: 2));
      _initialized = true;
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
    final x1 = (left * sx).floor().clamp(0, source.width - 1);
    final y1 = (top * sy).floor().clamp(0, source.height - 1);
    final x2 = (right * sx).ceil().clamp(x1 + 1, source.width);
    final y2 = (bottom * sy).ceil().clamp(y1 + 1, source.height);
    if (x2 - x1 < 12 || y2 - y1 < 12) return null;

    final tempDir = await Directory.systemTemp.createTemp('ag-paddle-');
    try {
      final crop = img.copyCrop(source, x: x1, y: y1,
          width: x2 - x1, height: y2 - y1);
      final enlarged = img.copyResize(
        crop, width: (crop.width * 2).clamp(24, 1800),
        interpolation: img.Interpolation.cubic,
      );
      final path = '${tempDir.path}/region.png';
      await File(path).writeAsBytes(img.encodePng(enlarged));
      final run = await _engine.recognize(path)
          .timeout(const Duration(seconds: 25));
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
      await _engine.dispose();
    }
  }
}
