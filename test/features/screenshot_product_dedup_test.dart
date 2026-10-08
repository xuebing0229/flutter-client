import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/imports/domain/screenshot_product_dedup.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';

void main() {
  ScreenshotProductCandidate item(
    String image, {
    String title = '【常驻】 黑白摸鱼头3.0',
    CommissionPlatform platform = CommissionPlatform.mihuashi,
    double? price = 94,
  }) => ScreenshotProductCandidate(
    platform: platform,
    title: title,
    imageInstanceId: image,
    price: price,
  );

  test('product storefronts are deduplicated even within one screenshot', () {
    final result = groupScreenshotProducts(
      candidates: [
        item('shot1'),
        item('shot1'),
        item('shot2'),
      ],
      existingProducts: const [],
    );

    expect(result.length, 1);
    expect(result.single.duplicateCardCount, 3);
    expect(result.single.sourceImages, ['shot1', 'shot2']);
    expect(result.single.price, 94);
    expect(result.single.alreadyInLibrary, isFalse);
    // Importing a product storefront must not imply three sales.
  });

  test('different storefront names and platforms remain distinct', () {
    final result = groupScreenshotProducts(
      candidates: [
        item('shot1'),
        item('shot2', title: '【常驻】 黑白摸鱼头3.0 '),
        item('shot3', title: '【常驻】 红白摸鱼头3.0'),
        item('shot4', platform: CommissionPlatform.huajia),
      ],
      existingProducts: const [],
    );
    expect(result.length, 3);
    expect(result.first.title, '【常驻】 黑白摸鱼头3.0');
  });

  test('existing archived products are flagged rather than recreated or sold', () {
    final existing = FinishedProduct(
      id: 'prod-original',
      title: '【常驻】 黑白摸鱼头3.0',
      platform: CommissionPlatform.mihuashi,
      saleType: ProductSaleType.multiple,
      soldCount: 5,
      saleRecords: [
        DateTime(2026, 9, 30, 12),
        DateTime(2026, 10, 1, 13),
      ],
      isArchived: true,
    );
    final result = groupScreenshotProducts(
      candidates: [item('shot1')],
      existingProducts: [existing],
    );
    expect(result.length, 1);
    expect(result.single.existingProductIds, ['prod-original']);
    expect(result.single.alreadyInLibrary, isTrue);
    expect(existing.soldCount, 5);
    expect(existing.saleRecords.length, 2);
  });

  test('conflicting OCR prices are flagged and not guessed', () {
    final result = groupScreenshotProducts(
      candidates: [
        item('shot1', price: 94),
        item('shot2', price: 49),
      ],
      existingProducts: const [],
    );
    expect(result.single.price, isNull);
    expect(result.single.priceNeedsReview, isTrue);
  });

  test('blank title does not become a new imported product', () {
    final result = groupScreenshotProducts(
      candidates: [item('shot1', title: '   ')],
      existingProducts: const [],
    );
    expect(result, isEmpty);
  });
}
