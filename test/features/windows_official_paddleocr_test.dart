import 'dart:convert';

import 'package:flutter_app/features/imports/data/windows_official_paddleocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official PaddleOCR JSON becomes positioned OCR lines', () {
    final source = jsonEncode(<String, dynamic>{
      'rec_texts': <String>[
        '【常驻】黑白摸鱼头3.0',
        '2026-10-31',
      ],
      'rec_boxes': <List<int>>[
        <int>[280, 395, 580, 427],
        <int>[310, 520, 450, 546],
      ],
    });

    final result = parseOfficialPaddleOcrJson(
      source,
      imageWidth: 692,
      imageHeight: 1536,
    );

    expect(result.width, 692);
    expect(result.height, 1536);
    expect(
      result.lines.map((line) => line.text).toList(),
      <String>['【常驻】黑白摸鱼头3.0', '2026-10-31'],
    );
    expect(result.lines.first.left, 280);
    expect(result.lines.first.bottom, 427);
    expect(result.lines.last.top, 520);
  });

  test('invalid and out-of-range boxes are filtered or clamped', () {
    final source = jsonEncode(<String, dynamic>{
      'rec_texts': <String>['标题', '坏框'],
      'rec_boxes': <List<int>>[
        <int>[-5, 10, 1200, 80],
        <int>[20, 30, 10, 60],
      ],
    });

    final result = parseOfficialPaddleOcrJson(
      source,
      imageWidth: 800,
      imageHeight: 600,
    );

    expect(result.lines, hasLength(1));
    expect(result.lines.single.left, 0);
    expect(result.lines.single.right, 800);
  });
}
