import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_duplicate_review.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';

void main() {
  ScreenshotImportIdentity entry({
    required String image,
    required String card,
    CommissionPlatform platform = CommissionPlatform.huajia,
    String title = '【常驻】 黑白摸鱼头3.0',
    String client = '同一个买家',
    DateTime? date,
    ScreenshotDatePrecision precision = ScreenshotDatePrecision.minute,
  }) {
    return ScreenshotImportIdentity(
      platform: platform,
      title: title,
      clientName: client,
      imageInstanceId: image,
      cardInstanceId: card,
      sourceDate: date ?? DateTime(2026, 10, 8, 16, 48),
      datePrecision: precision,
    );
  }

  test('all separate physical cards in a single screenshot are kept', () {
    final a = entry(image: 'picture1', card: 'card1');
    final b = entry(image: 'picture1', card: 'card2');
    expect(reviewScreenshotDuplicate(a, b),
        ScreenshotDuplicateReview.independent);
    expect(reviewScreenshotDuplicate(b, a),
        ScreenshotDuplicateReview.independent);
  });

  test('a repeated OCR result for the same card is a technical duplicate', () {
    final a = entry(image: 'picture1', card: 'card1');
    expect(reviewScreenshotDuplicate(a, a),
        ScreenshotDuplicateReview.duplicateOcrCard);
  });

  test('two overlapping images require review rather than automatic removal', () {
    final a = entry(image: 'picture1', card: 'card1');
    final b = entry(image: 'picture2', card: 'card3');
    expect(reviewScreenshotDuplicate(a, b),
        ScreenshotDuplicateReview.possibleDuplicate);
  });

  test('huajia displayed minute cannot distinguish different seconds', () {
    final a = entry(image: 'a', card: 'a');
    final b = entry(
      image: 'b', card: 'b',
      date: DateTime(2026, 10, 8, 16, 48, 59),
      precision: ScreenshotDatePrecision.second,
    );
    expect(reviewScreenshotDuplicate(a, b),
        ScreenshotDuplicateReview.possibleDuplicate);
  });

  test('mihuashi day-only dates remain a potential match', () {
    final a = entry(
      image: 'a', card: 'a', platform: CommissionPlatform.mihuashi,
      date: DateTime(2026, 10, 31), precision: ScreenshotDatePrecision.day,
    );
    final b = entry(
      image: 'b', card: 'b', platform: CommissionPlatform.mihuashi,
      date: DateTime(2026, 10, 31, 23, 59),
      precision: ScreenshotDatePrecision.minute,
    );
    expect(reviewScreenshotDuplicate(a, b),
        ScreenshotDuplicateReview.possibleDuplicate);
  });

  test('missing buyer requires review, not an assumed duplicate', () {
    final a = entry(image: 'a', card: 'a', client: '');
    final b = entry(image: 'b', card: 'b');
    expect(reviewScreenshotDuplicate(a, b),
        ScreenshotDuplicateReview.insufficientEvidence);
  });

  test('different known buyer or minute does not conflict', () {
    final a = entry(image: 'a', card: 'a');
    final changedBuyer = entry(image: 'b', card: 'b', client: '另一个买家');
    final changedMinute = entry(
      image: 'b', card: 'b', date: DateTime(2026, 10, 8, 16, 49));
    expect(reviewScreenshotDuplicate(a, changedBuyer),
        ScreenshotDuplicateReview.independent);
    expect(reviewScreenshotDuplicate(a, changedMinute),
        ScreenshotDuplicateReview.independent);
  });
}
