class PricingAdjustment {
  const PricingAdjustment({
    required this.id,
    required this.name,
    this.multiplier = 1,
    this.percent = 0,
    this.fixedAmount = 0,
  });

  final String id;
  final String name;

  /// Applied first. 1 means unchanged, 2 means x2.
  final double multiplier;

  /// Applied after [multiplier]. 30 means +30%, -10 means -10%.
  final double percent;

  /// Applied last. Positive adds money, negative subtracts money.
  final double fixedAmount;

  PricingAdjustment snapshot() => PricingAdjustment(
        id: id,
        name: name,
        multiplier: multiplier,
        percent: percent,
        fixedAmount: fixedAmount,
      );

  double apply(double amount) {
    final multiplied = amount * multiplier;
    final percentAdjusted = multiplied * (1 + percent / 100);
    return percentAdjusted + fixedAmount;
  }

  String get formulaLabel {
    final parts = <String>[];
    if ((multiplier - 1).abs() > 0.0000001) {
      parts.add('×${formatPricingNumber(multiplier)}');
    }
    if (percent.abs() > 0.0000001) {
      parts.add('${percent > 0 ? '+' : ''}${formatPricingNumber(percent)}%');
    }
    if (fixedAmount.abs() > 0.0000001) {
      parts.add('${fixedAmount > 0 ? '+' : '-'}¥${formatPricingNumber(fixedAmount.abs())}');
    }
    return parts.isEmpty ? '不变' : parts.join(' ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'multiplier': multiplier,
        'percent': percent,
        'fixedAmount': fixedAmount,
      };

  factory PricingAdjustment.fromJson(Map<String, dynamic> json) {
    double readNumber(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return fallback;
    }

    final rawId = json['id'];
    final rawName = json['name'];
    return PricingAdjustment(
      id: rawId is String && rawId.trim().isNotEmpty
          ? rawId
          : 'pricing-${DateTime.now().microsecondsSinceEpoch}',
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : '未命名加价',
      multiplier: readNumber('multiplier', 1).clamp(0, 100).toDouble(),
      percent: readNumber('percent', 0).clamp(-100, 10000).toDouble(),
      fixedAmount: readNumber('fixedAmount', 0),
    );
  }
}

double applyPricingAdjustments(
  double amount,
  Iterable<PricingAdjustment> adjustments,
) {
  var value = amount;
  for (final adjustment in adjustments) {
    value = adjustment.apply(value);
  }
  return value;
}

/// Returns the part of a supplement that is attributable to proportional
/// pricing rules. Fixed-amount rules are deliberately excluded so a flat
/// +¥N charge is never multiplied into the supplement simply because the
/// supplement participates in pricing.
double pricedSupplementAmount({
  required double basePrice,
  required double supplementAmount,
  required Iterable<PricingAdjustment> adjustments,
  required bool participates,
}) {
  if (!participates || supplementAmount == 0) return supplementAmount;

  var base = basePrice;
  var withSupplement = basePrice + supplementAmount;
  for (final adjustment in adjustments) {
    base *= adjustment.multiplier;
    base *= 1 + adjustment.percent / 100;
    withSupplement *= adjustment.multiplier;
    withSupplement *= 1 + adjustment.percent / 100;
  }
  return withSupplement - base;
}

String formatPricingNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'[.]$'), '');
}
