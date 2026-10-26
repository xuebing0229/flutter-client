import 'dart:convert';

import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product sale client names round-trip and old schema-7 backups stay readable', () {
    final soldAt = DateTime(2026, 10, 24, 12, 0);
    final product = FinishedProduct(
      id: 'product-1',
      title: '成品',
      platform: CommissionPlatform.mihuashi,
      saleType: ProductSaleType.multiple,
      price: 100,
      soldCount: 1,
      saleRecords: [soldAt],
      saleClientNames: {
        soldAt.toUtc().toIso8601String(): 'Alice',
      },
    );

    final backup = AppBackupData(
      exportedAt: DateTime(2026, 10, 24),
      orders: const [],
      products: [product],
      nodePresets: const [],
    );

    final decoded = AppBackupData.decode(backup.encode(pretty: false));
    expect(decoded.products.single.clientNameForSale(soldAt), 'Alice');

    final legacyJson = jsonDecode(backup.encode(pretty: false))
        as Map<String, dynamic>;
    final payload = legacyJson['payload'] as Map<String, dynamic>;
    final products = payload['products'] as List<dynamic>;
    (products.single as Map<String, dynamic>).remove('saleClientNames');

    final legacyDecoded = AppBackupData.decode(jsonEncode(legacyJson));
    expect(legacyDecoded.products.single.saleClientNames, isEmpty);
    expect(legacyDecoded.products.single.saleRecords, hasLength(1));
  });
}
