import 'dart:convert';
import 'dart:io';

import '../domain/screenshot_layout_parser.dart';
import 'screenshot_ocr_result.dart';

/// Windows OCR via a redistributable local Tesseract installation shipped in
/// the Windows app bundle by the release workflow (including chi_sim data).
/// No user-side installation, network request or cloud processing is needed.
/// The TSV contains one bounding box per word. Group words by text line before
/// running the shared order parser.
class WindowsTesseractOcr {
  const WindowsTesseractOcr();

  Future<ScreenshotOcrResult> recognize(String sourceImage) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows OCR 仅支持 Windows');
    }
    final root = File(Platform.resolvedExecutable).parent;
    final ocrRoot = Directory('${root.path}${Platform.pathSeparator}ocr');
    final binary = File('${ocrRoot.path}${Platform.pathSeparator}tesseract.exe');
    final tessdata = Directory('${ocrRoot.path}${Platform.pathSeparator}tessdata');
    if (!await binary.exists() || !await tessdata.exists()) {
      throw StateError('本安装包缺少离线中文 OCR 文件，请重新安装完整 Windows 版本');
    }
    final result = await Process.run(
      binary.path,
      [
        sourceImage,
        'stdout',
        '--tessdata-dir',
        tessdata.path,
        '-l',
        'chi_sim+eng',
        '--psm',
        '3',
        'tsv',
      ],
      workingDirectory: ocrRoot.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 75));

    if (result.exitCode != 0) {
      throw StateError('本地文字识别失败：${result.stderr}');
    }
    final content = (result.stdout as String).trim();
    final rows = const LineSplitter().convert(content);
    if (rows.length < 2) {
      throw const FormatException('OCR 未返回可用文字');
    }

    final grouped = <String, _WindowsTesseractLine>{};
    var width = 0;
    var height = 0;
    for (final raw in rows.skip(1)) {
      final columns = raw.split('\t');
      if (columns.length < 12) continue;
      final level = int.tryParse(columns[0]);
      final left = int.tryParse(columns[6]);
      final top = int.tryParse(columns[7]);
      final w = int.tryParse(columns[8]);
      final h = int.tryParse(columns[9]);
      if (level == 1 && w != null && h != null) {
        width = w;
        height = h;
        continue;
      }
      if (level != 5 || left == null || top == null ||
          w == null || h == null || w <= 0 || h <= 0) continue;
      final text = columns.sublist(11).join('\t').trim();
      if (text.isEmpty) continue;
      final key = columns.sublist(1, 5).join('/');
      final line = grouped.putIfAbsent(key, () => _WindowsTesseractLine());
      line.add(text, left.toDouble(), top.toDouble(),
          (left + w).toDouble(), (top + h).toDouble());
    }

    if (width <= 0 || height <= 0) {
      throw const FormatException('OCR 无法读取原图片尺寸');
    }
    return ScreenshotOcrResult(
      width: width.toDouble(),
      height: height.toDouble(),
      lines: List<ScreenshotTextLine>.unmodifiable([
        for (final line in grouped.values)
          if (line.text.isNotEmpty)
            ScreenshotTextLine(
              text: line.text,
              left: line.left,
              top: line.top,
              right: line.right,
              bottom: line.bottom,
            ),
      ]),
    );
  }
}

class _WindowsTesseractLine {
  String text = '';
  double left = double.infinity;
  double top = double.infinity;
  double right = double.negativeInfinity;
  double bottom = double.negativeInfinity;

  void add(String word, double x1, double y1, double x2, double y2) {
    // Chinese glyphs shouldn't gain spaces between successive characters;
    // English words must remain separated for field parsing.
    if (text.isNotEmpty && !RegExp(r'^[\u3400-\u9fff【】￥¥]').hasMatch(word)) {
      text += ' ';
    }
    text += word;
    if (x1 < left) left = x1;
    if (y1 < top) top = y1;
    if (x2 > right) right = x2;
    if (y2 > bottom) bottom = y2;
  }
}
