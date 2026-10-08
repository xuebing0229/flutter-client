import '../../orders/domain/queue_order.dart';
import '../../products/domain/finished_product.dart';
import 'screenshot_import_rules.dart';

/// Screenshots of product storefronts describe artwork/products, not sales.
/// Deliberately no deadline, buyer, soldAt or soldCount in this OCR draft.
class ScreenshotProductCandidate {
  const ScreenshotProductCandidate({
    required this.platform,
    required this.title,
    required this.imageInstanceId,
    this.price,
  });

  final CommissionPlatform platform;
  final String title;
  final String imageInstanceId;
  final double? price;
}

/// One unique storefront entry in the import preview, awaiting a human-chosen
/// ProductSaleType (single/multiple). Never creates sale records.
class ScreenshotProductGroup {
  const ScreenshotProductGroup({
    required this.platform,
    required this.title,
    required this.sourceImages,
    required this.duplicateCardCount,
    required this.price,
    required this.priceNeedsReview,
    required this.existingProductIds,
  });

  final CommissionPlatform platform;
  final String title;
  final List<String> sourceImages;
  final int duplicateCardCount;
  final double? price;
  final bool priceNeedsReview;

  /// If not empty, the preview must default to skipping creation. User can
  /// explicitly choose otherwise; never mutate or delete existing products.
  final List<String> existingProductIds;

  bool get alreadyInLibrary => existingProductIds.isNotEmpty;
}

String screenshotProductKey(CommissionPlatform platform, String fullTitle) =>
    '${platform.name}|${normalizedImportTitle(fullTitle)}';

/// Deduplicate storefronts across ALL selected images and cards, using
/// platform + full product title. This differs from order import, which must
/// preserve distinct physical order cards inside one screenshot.
///
/// Source images can show the same storefront at different prices: signal
/// ambiguity rather than guessing a sale or multiplying the product price.
List<ScreenshotProductGroup> groupScreenshotProducts({
  required Iterable<ScreenshotProductCandidate> candidates,
  required Iterable<FinishedProduct> existingProducts,
}) {
  final groups = <String, _WorkingProductGroup>{};
  for (final candidate in candidates) {
    if (candidate.title.trim().isEmpty) continue;

    final key = screenshotProductKey(candidate.platform, candidate.title);
    final group = groups.putIfAbsent(
      key,
      () => _WorkingProductGroup(candidate.platform, candidate.title.trim()),
    );
    group.count++;
    group.images.add(candidate.imageInstanceId);

    if (candidate.price != null) group.prices.add(candidate.price!);
  }

  final matches = <String, List<String>>{};
  for (final product in existingProducts) {
    final key = screenshotProductKey(product.platform, product.title);
    matches.putIfAbsent(key, () => <String>[]).add(product.id);
  }

  return List<ScreenshotProductGroup>.unmodifiable([
    for (final entry in groups.entries)
      ScreenshotProductGroup(
        platform: entry.value.platform,
        title: entry.value.title,
        sourceImages: List<String>.unmodifiable(entry.value.images),
        duplicateCardCount: entry.value.count,
        price: entry.value.prices.length == 1
            ? entry.value.prices.single
            : null,
        priceNeedsReview: entry.value.prices.length > 1,
        existingProductIds: List<String>.unmodifiable(
          matches[entry.key] ?? const <String>[],
        ),
      ),
  ]);
}

class _WorkingProductGroup {
  _WorkingProductGroup(this.platform, this.title);

  final CommissionPlatform platform;
  final String title;
  final Set<String> images = <String>{};
  final Set<double> prices = <double>{};
  int count = 0;
}
