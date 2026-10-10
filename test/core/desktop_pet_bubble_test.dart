import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/desktop_pet/desktop_pet_service.dart';

void main() {
  test('old pet presets have no bubble image and remain compatible', () {
    final preset = DesktopPetPreset.fromJson({
      'id': 'old-id',
      'name': '旧桌宠',
      'imageA': 'C:/old.png',
    });
    expect(preset, isNotNull);
    expect(preset!.bubbleImage, isNull);
    expect(preset.bubbleAboveOffset.x, 0);
  });

  test('bubble PNG is per-preset and round-trips through JSON', () {
    const initial = DesktopPetPreset(id: 'pet-1', name: '团子');
    final preset = initial.copyWith(bubbleImage: 'C:/bubble.png');
    final restored = DesktopPetPreset.fromJson(preset.toJson());
    expect(restored?.bubbleImage, 'C:/bubble.png');
    expect(restored?.imageA, isNull);
    expect(restored?.copyWith(clearBubbleImage: true).bubbleImage, isNull);
    expect(DesktopPetBubbleStyle.speech.label, '说话气泡');
    expect(DesktopPetBubbleStyle.thought.label, '思考气泡');
  });
}
