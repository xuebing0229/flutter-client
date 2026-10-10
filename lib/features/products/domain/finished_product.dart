import 'dart:math';

import '../../../core/finance/income_calculator.dart';
import 'sale_receipt.dart';
import '../../orders/domain/queue_order.dart';

enum ProductSaleType {
  single('单次售卖'),
  multiple('多次售卖');

  const ProductSaleType(this.label);
  final String label;
}

class FinishedProduct {
  const FinishedProduct({
    required this.id,
    required this.title,
    required this.platform,
    required this.saleType,
    this.price = 0,
    this.feeEnabled = false,
    this.huajiaLoveLevel = HuajiaLoveLevel.none,
    this.onlinePercent = 100,
    this.supplementAmount = 0,
    this.supplementFeeEnabled = false,
    this.deductionAmount = 0,
    this.deductionFeeEnabled = false,
    this.description = '',
    this.referenceImages = const <OrderReferenceImage>[],
    this.defaultOrder = 0,
    this.soldCount = 0,
    this.saleRecords = const <DateTime>[],
    this.saleReceipts = const <SaleReceipt>[],
    this.archivedAt,
    this.isArchived = false,
    this.isPinned = false,
  });

  final String id;
  final String title;
  final CommissionPlatform platform;
  final ProductSaleType saleType;

  /// 原始售价，仅详情页展示。
  final double price;
  final bool feeEnabled;
  final HuajiaLoveLevel huajiaLoveLevel;
  final double onlinePercent;
  final double supplementAmount;
  final bool supplementFeeEnabled;
  final double deductionAmount;
  final bool deductionFeeEnabled;

  final String description;
  final List<OrderReferenceImage> referenceImages;

  /// Stable cross-device order used by the default list sort.
  final int defaultOrder;
  int get effectiveDefaultOrder =>
      defaultOrder == 0 ? defaultOrderFromId(id) : defaultOrder;

  final int soldCount;

  /// Timestamp for each recorded sale.
  final List<DateTime> saleRecords;

  /// Amount/platform snapshots for each sale. Older files have only dates.
  final List<SaleReceipt> saleReceipts;

  /// Timestamp when this product was moved into the archive.
  final DateTime? archivedAt;

  final bool isArchived;
  final bool isPinned;

  bool get isSold => soldCount > 0;

  String get saleStatusLabel {
    if (saleType == ProductSaleType.single) {
      return isSold ? '已售出' : '未售出';
    }
    return '已售出 $soldCount';
  }

  double get normalizedOnlinePercent => onlinePercent.clamp(0, 100).toDouble();

  double get offlinePercent => 100 - normalizedOnlinePercent;

  double get originalTotal =>
      price + supplementAmount - deductionAmount;

  double _feeFor(double amount, bool enabled) {
    return calculatePlatformServiceFee(
      amount: amount,
      feeEnabled: enabled,
      usesHuajiaRules: platform == CommissionPlatform.huajia,
      huajiaLoveMultiplier: huajiaLoveLevel.feeMultiplier,
      usesOnlineOfflineSplit: platform.usesOnlineOfflineSplit,
      onlinePercent: normalizedOnlinePercent,
      roundsFeeDownToWholeYuan: platform == CommissionPlatform.mihuashi,
    );
  }

  double get serviceFeeAmount => _feeFor(price, feeEnabled);

  double get supplementFeeAmount =>
      _feeFor(supplementAmount, supplementFeeEnabled);

  double get deductionFeeAmount =>
      _feeFor(deductionAmount, deductionFeeEnabled);

  double get realIncome => calculateAdjustedIncome(
        basePrice: price,
        baseFee: serviceFeeAmount,
        supplementAmount: supplementAmount,
        supplementFee: supplementFeeAmount,
        deductionAmount: deductionAmount,
        deductionFee: deductionFeeAmount,
      );

  /// Reconcile historical dates with frozen receipts. Legacy dates are
  /// estimated once using the price known at migration; never pretend these
  /// values were present in the original transaction records.
  List<SaleReceipt> get accountedSales {
    final byDate = <int, List<SaleReceipt>>{};
    for (final receipt in saleReceipts) {
      byDate.putIfAbsent(
        receipt.soldAt.toUtc().microsecondsSinceEpoch,
        () => <SaleReceipt>[],
      ).add(receipt);
    }
    for (final group in byDate.values) {
      group.sort((a, b) => a.id.compareTo(b.id));
    }

    final ordinalByDate = <int, int>{};
    final result = <SaleReceipt>[];
    for (final at in saleRecords) {
      final timestamp = at.toUtc().microsecondsSinceEpoch;
      final ordinal = ordinalByDate.update(
        timestamp,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final existing = byDate[timestamp];
      if (existing != null && existing.isNotEmpty) {
        result.add(existing.removeAt(0));
      } else {
        result.add(SaleReceipt(
          id: 'legacy-$id-$timestamp-$ordinal',
          soldAt: at,
          netIncome: realIncome,
          originalPrice: price,
          serviceFee: serviceFeeAmount +
              supplementFeeAmount - deductionFeeAmount,
          platform: platform,
          estimated: true,
        ));
      }
    }
    return List<SaleReceipt>.unmodifiable(result);
  }

  /// Centralized sale editing; single and multiple sale paths use identical
  /// immutable bookkeeping so timestamps and snapshots never drift apart.
  FinishedProduct withSaleCount(int requested, {DateTime? soldAt}) {
    final desired = saleType == ProductSaleType.single
        ? requested.clamp(0, 1)
        : max(0, requested);
    final dates = <DateTime>[...saleRecords];
    final receipts = <SaleReceipt>[...accountedSales];
    if (desired < dates.length) {
      dates.removeRange(desired, dates.length);
      receipts.removeRange(desired, receipts.length);
    }
    while (dates.length < desired) {
      var at = soldAt ?? DateTime.now().toUtc();
      if (soldAt == null && dates.contains(at)) {
        at = at.add(Duration(microseconds: dates.length + 1));
      }
      dates.add(at);
      final nonce = Random.secure().nextInt(0x7fffffff);
      receipts.add(SaleReceipt(
        id: 'sale-${at.toUtc().microsecondsSinceEpoch}-'
            '${nonce.toRadixString(36)}',
        soldAt: at,
        netIncome: realIncome,
        originalPrice: price,
        serviceFee: serviceFeeAmount +
            supplementFeeAmount - deductionFeeAmount,
        platform: platform,
      ));
    }
    return copyWith(
      soldCount: desired,
      saleRecords: dates,
      saleReceipts: receipts,
    );
  }

  FinishedProduct copyWith({
    String? title,
    CommissionPlatform? platform,
    ProductSaleType? saleType,
    double? price,
    bool? feeEnabled,
    HuajiaLoveLevel? huajiaLoveLevel,
    double? onlinePercent,
    double? supplementAmount,
    bool? supplementFeeEnabled,
    double? deductionAmount,
    bool? deductionFeeEnabled,
    String? description,
    List<OrderReferenceImage>? referenceImages,
    int? defaultOrder,
    int? soldCount,
    List<DateTime>? saleRecords,
    List<SaleReceipt>? saleReceipts,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    bool? isArchived,
    bool? isPinned,
  }) {
    final nextSaleType = saleType ?? this.saleType;
    var nextSoldCount = soldCount ?? this.soldCount;
    if (nextSoldCount < 0) nextSoldCount = 0;
    if (nextSaleType == ProductSaleType.single && nextSoldCount > 1) {
      nextSoldCount = 1;
    }

    return FinishedProduct(
      id: id,
      title: title ?? this.title,
      platform: platform ?? this.platform,
      saleType: nextSaleType,
      price: price ?? this.price,
      feeEnabled: feeEnabled ?? this.feeEnabled,
      huajiaLoveLevel: huajiaLoveLevel ?? this.huajiaLoveLevel,
      onlinePercent: onlinePercent ?? this.onlinePercent,
      supplementAmount: supplementAmount ?? this.supplementAmount,
      supplementFeeEnabled:
          supplementFeeEnabled ?? this.supplementFeeEnabled,
      deductionAmount: deductionAmount ?? this.deductionAmount,
      deductionFeeEnabled:
          deductionFeeEnabled ?? this.deductionFeeEnabled,
      description: description ?? this.description,
      referenceImages: referenceImages ?? this.referenceImages,
      defaultOrder: defaultOrder ?? this.defaultOrder,
      soldCount: nextSoldCount,
      saleRecords: saleRecords ?? this.saleRecords,
      // copyWith seals legacy income at the *old* price before edit.
      saleReceipts: saleReceipts ?? accountedSales,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
