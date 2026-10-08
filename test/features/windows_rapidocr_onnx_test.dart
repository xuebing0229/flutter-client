import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/data/windows_rapidocr_onnx.dart';

void main() {
  test('RapidOCR logger text and boxes become positioned OCR lines', () {
    const output = '''
=====Start detect====
ScaleParam(sw:692,sh:1536,dw:692,dh:1536,1.0,1.0)
TextBox[0](+padding)[score(0.988),[x: 280, y: 395], [x: 580, y: 395], [x: 580, y: 427], [x: 280, y: 427]]
TextBox[1](+padding)[score(0.990),[x: 310, y: 520], [x: 450, y: 520], [x: 450, y: 546], [x: 310, y: 546]]
textLine[0](【常驻】黑白摸鱼头3.0)
textScores[0]{0.9 ,0.9}
textLine[1](2026-10-31)
textScores[1]{0.9 ,0.9}
=====End detect====
''';
    final result = parseRapidOnnxConsole(output);
    expect(result.width, 692);
    expect(result.height, 1536);
    expect(result.lines.map((x) => x.text).toList(),
        ['【常驻】黑白摸鱼头3.0', '2026-10-31']);
    expect(result.lines.first.left, 280);
    expect(result.lines.first.bottom, 427);
    expect(result.lines.last.top, 520);
  });

  test('Windows CRLF console output still parses', () {
    const output = 'ScaleParam(sw:692,sh:1536,dw:692,dh:1536,1,1)\r\n'
        'TextBox[0](+padding)[score(0.9),[x: 20, y: 30], [x: 150, y: 30], [x: 150, y: 50], [x: 20, y: 50]]\r\n'
        'textLine[0](【常驻】画稿)\r\n';
    final result = parseRapidOnnxConsole(output);
    expect(result.lines.single.text, '【常驻】画稿');
  });
}
