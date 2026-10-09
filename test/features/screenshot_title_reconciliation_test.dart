import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_draft.dart';
import 'package:flutter_app/features/imports/domain/screenshot_title_reconciliation.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  ScreenshotOrderCandidate card(
    String title,
    String buyer, {
    double? price = 94,
    DateTime? deadline,
  }) => ScreenshotOrderCandidate(
    title: title,
    clientName: buyer,
    detectedDate: deadline ?? DateTime(2026, 10, 31),
    deadlineHasTime: false,
    relativeDeadlineText: null,
    price: price,
    progressPercent: 60,
    sourceLines: const [],
    sourceStartY: 0,
    sourceEndY: 100,
  );

  test('real MiHuashi three cards with one missing 头 and broken bracket', () {
    final cards = [
      card('【常驻】 黑白摸鱼头3.0', '买家甲'),
      card('【常驻】 黑白摸鱼3.0', '买家乙'),
      card('【常驻1黑白摸鱼头3.0', '买家丙'),
    ];
    final titles = reconcileMiHuashiScreenshotTitles(cards);
    expect(titles, everyElement('【常驻】 黑白摸鱼头3.0'));
    // The importer must not collapse three purchases into a single order.
    expect(titles, hasLength(3));
    expect(cards.map((e) => e.clientName).toList(),
        ['买家甲', '买家乙', '买家丙']);
  });

  test('one OCR-uncertain title does not silently rename another work', () {
    final titles = reconcileMiHuashiScreenshotTitles([
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼头3.0', '乙'),
      card('【常驻】 黑白摸鱼头4.0', '丙'),
    ]);
    expect(titles.last, '【常驻】 黑白摸鱼头4.0');
  });

  test('independent price or deadline cannot be used as OCR consensus', () {
    final titles = reconcileMiHuashiScreenshotTitles([
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼头3.0', '乙'),
      card('【常驻】 黑白摸鱼3.0', '丙', price: 80),
      card('【常驻】 黑白摸鱼3.0', '丁', deadline: DateTime(2026, 11, 2)),
    ]);
    expect(titles[2], '【常驻】 黑白摸鱼3.0');
    expect(titles[3], '【常驻】 黑白摸鱼3.0');
  });

  test('two disputed versions alone are not sufficient to rewrite a title', () {
    final titles = reconcileMiHuashiScreenshotTitles([
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼3.0', '乙'),
    ]);
    expect(titles.first, '【常驻】 黑白摸鱼头3.0');
    expect(titles.last, '【常驻】 黑白摸鱼3.0');
  });

  test('missing price or repeated buyer does not produce a false consensus', () {
    final titles = reconcileMiHuashiScreenshotTitles([
      card('【常驻】 黑白摸鱼头3.0', '甲', price: null),
      card('【常驻】 黑白摸鱼头3.0', '乙', price: null),
      card('【常驻】 黑白摸鱼3.0', '丙', price: null),
    ]);
    expect(titles.last, '【常驻】 黑白摸鱼3.0');
    final singleBuyer = reconcileMiHuashiScreenshotTitles([
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼3.0', '乙'),
    ]);
    expect(singleBuyer.last, '【常驻】 黑白摸鱼3.0');
  });

  test('consensus titles let a batch preset propagate to all three rows', () {
    final cards = [
      card('【常驻】 黑白摸鱼头3.0', '甲'),
      card('【常驻】 黑白摸鱼3.0', '乙'),
      card('【常驻1黑白摸鱼头3.0', '丙'),
    ];
    final titles = reconcileMiHuashiScreenshotTitles(cards);
    final rows = [
      for (var index = 0; index < cards.length; index++)
        ScreenshotImportDraft(
          id: 'row-$index',
          sourceImageId: 'shot-1',
          title: titles[index],
          clientName: cards[index].clientName,
          price: 94,
          platform: CommissionPlatform.mihuashi,
          detectedDate: DateTime(2026, 10, 31),
          recognizedPercent: 60,
          presetId: 'unselected',
          nodeId: 'unselected',
        ),
    ];
    cascadeScreenshotPreset(
      changed: rows.first,
      rows: rows,
      selectedPreset: defaultNodePreset,
    );
    expect(rows.every((r) => r.presetId == defaultNodePreset.id), isTrue);
    expect(rows.map((r) => r.clientName).toList(), ['甲', '乙', '丙']);
  });

  test('real phone detail: recover malformed bracket, do not invent fish emoji', () {
    final titles = reconcileMiHuashiScreenshotTitles([
      card('【这是1摸念盒子', '买家丁'),
    ]);
    expect(titles, ['【这是】摸念盒子']);
    // A genuinely numbered bracket label must not be rewritten.
    expect(reconcileMiHuashiScreenshotTitles([
      card('【这是1号】摸鱼盒子', '买家乙'),
    ]), ['【这是1号】摸鱼盒子']);
  });
}
