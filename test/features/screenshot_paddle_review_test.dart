import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/data/screenshot_paddle_review.dart';
import 'package:flutter_app/features/imports/domain/screenshot_layout_parser.dart';

void main() {
  ScreenshotOrderCandidate row({
    String buyer = '',
    String title = '【常驻】测试稿',
    bool cropRecovered = false,
  }) => ScreenshotOrderCandidate(
        title: title,
        clientName: buyer,
        detectedDate: null,
        deadlineHasTime: false,
        relativeDeadlineText: null,
        price: 94,
        progressPercent: 60,
        sourceLines: const [],
        sourceStartY: 0,
        sourceEndY: 0,
        clientBox: buyer.isEmpty ? null : ScreenshotTextLine(
          text: buyer,
          left: 160,
          top: 900,
          right: 230,
          bottom: 930,
          recoveredFromCrop: cropRecovered,
        ),
        titleBox: ScreenshotTextLine(
          text: title,
          left: 350,
          top: 1070,
          right: 670,
          bottom: 1105,
        ),
      );

  test('only uncertain buyers trigger independent OCR', () {
    expect(shouldPaddleReviewBuyer(row()), isTrue);
    expect(shouldPaddleReviewBuyer(row(buyer: '正常买家')), isFalse);
    expect(shouldPaddleReviewBuyer(
      row(buyer: '限w', cropRecovered: true),
    ), isTrue);
  });

  test('malformed bracket titles are reviewed while normal ones are untouched', () {
    expect(shouldPaddleReviewTitle(row(title: '【这是1摸念盒子')), isTrue);
    expect(shouldPaddleReviewTitle(row(title: '【常驻】测试稿')), isFalse);
  });

  test('nearby buyer text wins over unrelated high-score lines', () {
    final best = bestPaddleText([
      const PaddleFieldText('别的单主', 0.98, 10),
      const PaddleFieldText('暂vv', 0.93, 150),
      const PaddleFieldText('￥94', 0.99, 150),
      const PaddleFieldText('截稿时间', 0.99, 155),
    ], isBuyer: true, preferredY: 148);
    expect(best, '暂vv');
  });

  test('secondary OCR never hallucinates from empty or UI-only regions', () {
    expect(bestPaddleText([
      const PaddleFieldText('全额支付', 0.99, 100),
      const PaddleFieldText('2026-10-31', 0.99, 100),
      const PaddleFieldText('￥88', 0.99, 100),
    ], isBuyer: true, preferredY: 100), isNull);
    expect(bestPaddleText([], isBuyer: false, preferredY: 80), isNull);
  });
}
