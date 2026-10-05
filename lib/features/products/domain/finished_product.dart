import '../../../core/finance/income_calculator.dart';
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
    this.defaultOrder = 0,
    this.soldCount = 0,
    this.saleRecords = const <DateTime>[],
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

  /// Stable cross-device order used by the default list sort.
  final int defaultOrder;
  int get effectiveDefaultOrder =>
      defaultOrder == 0 ? defaultOrderFromId(id) : defaultOrder;

  final int soldCount;

  /// Timestamp for each recorded sale.
  final List<DateTime> saleRecords;

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
    int? defaultOrder,
    int? soldCount,
    List<DateTime>? saleRecords,
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
      defaultOrder: defaultOrder ?? this.defaultOrder,
      soldCount: nextSoldCount,
      saleRecords: saleRecords ?? this.saleRecords,
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
