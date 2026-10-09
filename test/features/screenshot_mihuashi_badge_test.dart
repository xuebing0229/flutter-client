import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';
import 'package:flutter_app/features/imports/domain/screenshot_mihuashi_badge.dart';
import 'package:flutter_app/features/imports/domain/screenshot_import_draft.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';

void main() {
  ScreenshotTextLine box(String value, double x, double y) =>
      ScreenshotTextLine(text: value, left: x, top: y, right: x + 180, bottom: y + 28);

  ScreenshotOrderCandidate candidate({
    required String title,
    List<ScreenshotTextLine>? lines,
    ScreenshotTextLine? titleBox,
  }) => ScreenshotOrderCandidate(
    title: title,
    clientName: '买家',
    detectedDate: DateTime(2026, 12, 31),
    deadlineHasTime: false,
    relativeDeadlineText: null,
    price: null,
    progressPercent: 80,
    sourceLines: lines ?? const [],
    sourceStartY: 0,
    sourceEndY: 800,
    titleBox: titleBox,
  );

  test('merged MiHuashi badge, even with no blank separator, is not title', () {
    final row = candidate(title: '定向企划邀请您价目表中的人head气球');
    expect(hasDirectedCommissionBadge(
      platform: CommissionPlatform.mihuashi, candidate: row,
    ), isTrue);
    expect(removeDirectedCommissionPrefix(row.title),
        '邀请您价目表中的人head气球');
    expect(removeDirectedCommissionPrefix('定向企划 黑白摸鱼头'), '黑白摸鱼头');
  });

  test('standalone badge on same line is recognized without stripping title', () {
    final title = box('黑白摸鱼头', 350, 486);
    final row = candidate(
      title: title.text, titleBox: title,
      lines: [box('定向企划', 80, 488), title, box('2026-11-30', 280, 540)],
    );
    expect(hasDirectedCommissionBadge(
      platform: CommissionPlatform.mihuashi, candidate: row,
    ), isTrue);
    expect(removeDirectedCommissionPrefix(row.title), '黑白摸鱼头');
  });

  test('badge on another row, platform, or ordinary title is not tagged', () {
    final title = box('黑白摸鱼头', 350, 488);
    final row = candidate(title: title.text, titleBox: title,
        lines: [box('定向企划', 80, 280)]);
    expect(hasDirectedCommissionBadge(
      platform: CommissionPlatform.mihuashi, candidate: row,
    ), isFalse);
    final foreign = candidate(title: '定向企划黑白摸鱼头');
    expect(hasDirectedCommissionBadge(
      platform: CommissionPlatform.huajia, candidate: foreign,
    ), isFalse);
    expect(removeDirectedCommissionPrefix('【常驻】黑白摸鱼头3.0'),
        '【常驻】黑白摸鱼头3.0');
  });

  test('tag can travel with import draft and be removed before writing', () {
    final row = ScreenshotImportDraft(
      id: 'draft', sourceImageId: 'shot-1', title: '黑白摸鱼头',
      clientName: '买家', price: 12, platform: CommissionPlatform.mihuashi,
      detectedDate: null, recognizedPercent: 80,
      presetId: 'preset', nodeId: 'node',
      tags: const [directedCommissionTag],
      saleType: ProductSaleType.single,
    );
    expect(row.tags, [directedCommissionTag]);
    row.tags = [];
    expect(row.tags, isEmpty);
  });
}
