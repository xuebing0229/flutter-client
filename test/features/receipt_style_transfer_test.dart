import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/shared/domain/receipt_style_store.dart';
import 'package:flutter_app/features/shared/domain/receipt_style_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const transfer = ReceiptStyleTransfer();

  test('receipt share image preserves custom background and font color', () {
    final background = base64Encode(
      Uint8List.fromList(List<int>.generate(4096, (index) => index % 251)),
    );
    final preset = ReceiptStylePreset(
      id: 'source-preset',
      name: '测试分享预设',
      fontColorValue: 0xFF336699,
      backgroundImageBase64: background,
      backgroundImageName: 'background.webp',
    );

    // The transfer format appends its payload to a PNG file. A real decoder
    // ignores bytes after IEND; the transfer reader locates our own marker.
    final fakePng = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x49, 0x45, 0x4E, 0x44,
    ]);
    final shared = transfer.attachPresetToPng(fakePng, preset);
    final restored = transfer.decodePresetFromImage(shared);

    expect(restored.name, preset.name);
    expect(restored.fontColorValue, preset.fontColorValue);
    expect(restored.backgroundImageBase64, background);
    expect(restored.backgroundImageName, 'background.webp');
  });

  test('ordinary image without receipt payload is rejected', () {
    expect(
      () => transfer.decodePresetFromImage(
        Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      ),
      throwsFormatException,
    );
  });
}
