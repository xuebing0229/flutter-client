import '../../orders/domain/queue_order.dart';

/// A sale is a historical financial event, never recalculated from the
/// currently editable product settings. Older records have estimated=true
/// because earlier app versions saved dates without transaction amounts.
class SaleReceipt {
  const SaleReceipt({
    required this.id,
    required this.soldAt,
    required this.netIncome,
    required this.originalPrice,
    required this.serviceFee,
    required this.platform,
    this.estimated = false,
  });

  final String id;
  final DateTime soldAt;
  final double netIncome;
  final double originalPrice;
  final double serviceFee;
  final CommissionPlatform platform;
  final bool estimated;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'soldAt': soldAt.toUtc().toIso8601String(),
    'netIncome': netIncome,
    'originalPrice': originalPrice,
    'serviceFee': serviceFee,
    'platform': platform.name,
    'estimated': estimated,
  };

  factory SaleReceipt.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final rawDate = json['soldAt'];
    final amount = json['netIncome'];
    final price = json['originalPrice'];
    final fee = json['serviceFee'];
    final rawPlatform = json['platform'];
    final estimated = json['estimated'];
    if (id is! String || id.isEmpty ||
        rawDate is! String ||
        amount is! num || !amount.isFinite ||
        price is! num || !price.isFinite ||
        fee is! num || !fee.isFinite ||
        rawPlatform is! String ||
        estimated is! bool) {
      throw const FormatException('成品售出流水格式无效。');
    }
    final date = DateTime.tryParse(rawDate);
    if (date == null) {
      throw const FormatException('成品售出流水日期无效。');
    }
    final platforms = CommissionPlatform.values.where(
      (item) => item.name == rawPlatform,
    );
    if (platforms.isEmpty) {
      throw const FormatException('成品售出流水平台无效。');
    }
    return SaleReceipt(
      id: id,
      soldAt: date,
      netIncome: amount.toDouble(),
      originalPrice: price.toDouble(),
      serviceFee: fee.toDouble(),
      platform: platforms.first,
      estimated: estimated,
    );
  }
}
