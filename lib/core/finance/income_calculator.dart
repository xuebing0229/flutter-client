const double commissionFeeRate = 0.05;
const double huajiaExcessChannelFeeRate = 0.01;
const double huajiaTierThreshold = 500;

double calculateServiceFee({
  required double basePrice,
  required bool feeEnabled,
  double feeApplicablePercent = 100,
}) {
  if (!feeEnabled || basePrice == 0) return 0;
  final ratio = feeApplicablePercent.clamp(0, 100) / 100;
  return basePrice * ratio * commissionFeeRate;
}

/// 画加当前阶梯规则：
/// - 500 元及以下：5%
/// - 超过 500 元：前 500 元手续费 25 元；超出部分仅按约 1%
///   的支付通道费计算。
/// 真爱永恒折扣只作用于平台手续费部分，不折支付通道费。
double calculateHuajiaServiceFee({
  required double amount,
  required bool feeEnabled,
  required double loveDiscountMultiplier,
}) {
  if (!feeEnabled || amount == 0) return 0;

  final positiveAmount = amount.abs();
  final discount = loveDiscountMultiplier.clamp(0, 1).toDouble();

  if (positiveAmount <= huajiaTierThreshold) {
    return positiveAmount * commissionFeeRate * discount;
  }

  final platformFee =
      huajiaTierThreshold * commissionFeeRate * discount;
  final channelFee =
      (positiveAmount - huajiaTierThreshold) * huajiaExcessChannelFeeRate;

  return platformFee + channelFee;
}

double calculatePlatformServiceFee({
  required double amount,
  required bool feeEnabled,
  required bool usesHuajiaRules,
  required double huajiaLoveMultiplier,
  required bool usesOnlineOfflineSplit,
  required double onlinePercent,
  bool roundsFeeDownToWholeYuan = false,
}) {
  if (!feeEnabled || amount == 0) return 0;

  if (usesHuajiaRules) {
    return calculateHuajiaServiceFee(
      amount: amount,
      feeEnabled: true,
      loveDiscountMultiplier: huajiaLoveMultiplier,
    );
  }

  final fee = calculateServiceFee(
    basePrice: amount,
    feeEnabled: true,
    feeApplicablePercent:
        usesOnlineOfflineSplit ? onlinePercent.clamp(0, 100).toDouble() : 100,
  );

  return roundsFeeDownToWholeYuan ? fee.floorToDouble() : fee;
}

double calculateAdjustedIncome({
  required double basePrice,
  required double baseFee,
  required double supplementAmount,
  required double supplementFee,
  required double deductionAmount,
  required double deductionFee,
}) {
  return basePrice -
      baseFee +
      supplementAmount -
      supplementFee -
      deductionAmount +
      deductionFee;
}


double applyOptionalFee({
  required double amount,
  required bool subjectToFee,
}) {
  if (!subjectToFee) return amount;
  return amount * (1 - commissionFeeRate);
}

double calculateRealIncome({
  required double basePrice,
  required bool feeEnabled,
  double feeApplicablePercent = 100,
  double supplementAmount = 0,
  bool supplementFeeEnabled = false,
  double deductionAmount = 0,
  bool deductionFeeEnabled = false,
}) {
  final baseFee = calculateServiceFee(
    basePrice: basePrice,
    feeEnabled: feeEnabled,
    feeApplicablePercent: feeApplicablePercent,
  );

  final supplementNet = applyOptionalFee(
    amount: supplementAmount,
    subjectToFee: supplementFeeEnabled,
  );

  final deductionNet = applyOptionalFee(
    amount: deductionAmount,
    subjectToFee: deductionFeeEnabled,
  );

  return basePrice - baseFee + supplementNet - deductionNet;
}
