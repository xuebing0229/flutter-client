import 'dart:convert';

import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/core/sync/sync_entity_codec.dart';
import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinishedProduct product({
    double price = 100,
    bool feeEnabled = true,
  }) =>
      FinishedProduct(
        id: 'sale-receipt-test',
        title: '多次售卖',
        platform: CommissionPlatform.mihuashi,
        saleType: ProductSaleType.multiple,
        price: price,
        feeEnabled: feeEnabled,
      );

  test('every new sale freezes its own net amount and platform', () {
    final firstAt = DateTime.utc(2026, 9, 1, 10);
    final secondAt = DateTime.utc(2026, 10, 1, 10);
    final store = ProductStore();
    addTearDown(store.dispose);
    store.addProduct(product());

    store.markSold('sale-receipt-test', soldAt: firstAt);
    store.updateProduct(
      store.byId('sale-receipt-test').copyWith(price: 200),
    );
    store.markSold('sale-receipt-test', soldAt: secondAt);

    final sales = store.byId('sale-receipt-test').accountedSales;
    expect(sales, hasLength(2));
    expect(sales.map((receipt) => receipt.netIncome), [95, 190]);
    expect(sales.map((receipt) => receipt.soldAt), [firstAt, secondAt]);
    expect(sales.every((receipt) => !receipt.estimated), isTrue);
    expect(sales.map((receipt) => receipt.id).toSet(), hasLength(2));

    store.updateProduct(store.byId('sale-receipt-test').copyWith(
      platform: CommissionPlatform.offline,
      feeEnabled: false,
      price: 9000,
    ));
    final unchanged = store.byId('sale-receipt-test').accountedSales;
    expect(unchanged.map((receipt) => receipt.netIncome), [95, 190]);
    expect(
      unchanged.map((receipt) => receipt.platform),
      [CommissionPlatform.mihuashi, CommissionPlatform.mihuashi],
    );
  });

  test('old date-only records are sealed as estimates before price edits', () {
    final oldAt = DateTime.utc(2026, 8, 8);
    final legacy = product().copyWith(
      soldCount: 1,
      saleRecords: [oldAt],
      saleReceipts: const [],
    );
    final migrated = legacy.copyWith(price: 500);
    final sale = migrated.accountedSales.single;

    expect(sale.soldAt, oldAt);
    expect(sale.netIncome, 95);
    expect(sale.estimated, isTrue);
    expect(sale.id, contains('legacy-'));
    expect(migrated.accountedSales.single.netIncome, 95);
  });

  test('count reductions void latest sale without rewriting older receipts', () {
    final store = ProductStore();
    addTearDown(store.dispose);
    store.addProduct(product());

    final earlier = DateTime.utc(2026, 9, 1);
    final later = DateTime.utc(2026, 10, 1);
    store.markSold('sale-receipt-test', soldAt: earlier);
    store.updateProduct(store.byId('sale-receipt-test').copyWith(price: 200));
    store.markSold('sale-receipt-test', soldAt: later);

    final corrected = store.byId('sale-receipt-test').withSaleCount(1);
    store.updateProduct(corrected);
    expect(store.byId('sale-receipt-test').soldCount, 1);
    expect(store.byId('sale-receipt-test').saleRecords, [earlier]);
    expect(store.byId('sale-receipt-test').accountedSales.single.netIncome, 95);

    // Re-selling is a new event with a new ID; no resurrected stale receipt.
    store.markSold('sale-receipt-test', soldAt: DateTime.utc(2026, 11, 1));
    expect(
      store.byId('sale-receipt-test').accountedSales
          .map((sale) => sale.netIncome),
      [95, 190],
    );
  });

  test('receipts survive backup and local/sync codec roundtrip', () {
    final store = ProductStore();
    addTearDown(store.dispose);
    store.addProduct(product().withSaleCount(
      1,
      soldAt: DateTime.utc(2026, 10, 10),
    ));
    final original = store.byId('sale-receipt-test');
    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 10),
      orders: const [],
      products: [original],
      nodePresets: const [],
    );
    final decoded = AppBackupData.decode(backup.encode()).products.single;
    expect(decoded.accountedSales.single.netIncome, 95);
    expect(decoded.accountedSales.single.id, original.accountedSales.single.id);
    expect(decoded.accountedSales.single.estimated, isFalse);
    final fields = SyncEntityCodec.productToFields(original);
    final remote = SyncEntityCodec.productFromFields(fields);
    expect(remote.accountedSales.single.netIncome, 95);
    expect(remote.accountedSales.single.id, original.accountedSales.single.id);
  });

  test('schema 7 backup dates import as explicitly estimated snapshots', () {
    final old = product().copyWith(
      soldCount: 1,
      saleRecords: [DateTime.utc(2026, 8, 8)],
      saleReceipts: const [],
    );
    final root = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 10),
      orders: const [],
      products: [old],
      nodePresets: const [],
    ).toJson();
    root['schemaVersion'] = 7;
    final payload = root['payload'] as Map<String, dynamic>;
    final products = payload['products'] as List<dynamic>;
    final legacyProduct = products.single as Map<String, dynamic>;
    legacyProduct.remove('saleReceipts');

    final decoded = AppBackupData.decode(jsonEncode(root));
    final store = ProductStore();
    addTearDown(store.dispose);
    store.replaceAll(decoded.products);
    final receipt = store.byId(old.id).accountedSales.single;
    expect(receipt.estimated, isTrue);
    expect(receipt.netIncome, 95);
    expect(receipt.soldAt.isAtSameMomentAs(DateTime.utc(2026, 8, 8)), isTrue);
    expect(
      AppBackupData(
        exportedAt: DateTime.utc(2026, 10, 10),
        orders: const [],
        products: store.products.toList(),
        nodePresets: const [],
      ).toJson()['schemaVersion'],
      currentBackupSchemaVersion,
    );
  });

  test('receipt ledger prevents stale date/count fields reviving a sale', () {
    final engine = SyncMergeEngine();
    final sold = product().withSaleCount(
      1,
      soldAt: DateTime.utc(2026, 10, 10),
    );
    final originalFields = SyncEntityCodec.productToFields(sold);
    final staleFields = <String, dynamic>{...originalFields}
      ..['saleReceipts'] = <dynamic>[]
      ..['soldCount'] = 5;
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: sold.id,
      values: staleFields,
      deviceId: 'phone',
    );
    final materialized = engine.materialize(record)!;
    expect(materialized['soldCount'], 0);
    expect(materialized['saleRecords'], isEmpty);
  });

  test('voided receipt stays removed after stale sync and compaction', () {
    final engine = SyncMergeEngine();
    final blank = product();
    final before = SyncEntityCodec.productToFields(blank);
    final base = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: blank.id,
      values: before,
      deviceId: 'phone',
    );
    final withSale = blank.withSaleCount(
      1,
      soldAt: DateTime.utc(2026, 10, 11, 20),
    );
    final soldFields = SyncEntityCodec.productToFields(withSale);
    final created = engine.applyLocalSnapshot(
      record: base,
      previousValues: before,
      nextValues: soldFields,
      deviceId: 'phone',
    );
    final reversed = engine.applyLocalSnapshot(
      record: created,
      previousValues: soldFields,
      nextValues: SyncEntityCodec.productToFields(withSale.withSaleCount(0)),
      deviceId: 'computer',
    );
    for (final state in [
      engine.merge(reversed, created),
      engine.merge(created, reversed),
    ]) {
      final materialized = engine.materialize(state)!;
      expect(materialized['soldCount'], 0);
      expect(materialized['saleRecords'], isEmpty);
      expect(materialized['saleReceipts'], isEmpty);
      final compacted = engine.compactAcknowledgedOperations(
        state,
        deviceId: 'computer',
      );
      final again = engine.merge(compacted, created);
      expect(engine.materialize(again)!['soldCount'], 0);
      expect(engine.materialize(again)!['saleReceipts'], isEmpty);
    }
  });

  test('changing multi-sale product to single keeps only one receipt', () {
    final source = product().withSaleCount(2);
    final original = source.accountedSales.first;
    final changed = source.copyWith(
      saleType: ProductSaleType.single,
    ).withSaleCount(1);
    expect(changed.soldCount, 1);
    expect(changed.saleRecords.length, 1);
    expect(changed.accountedSales.single.id, original.id);
    expect(changed.accountedSales.single.netIncome, original.netIncome);
  });

  test('offline sales merge receipts idempotently and survive GC compaction', () {
    final engine = SyncMergeEngine();
    final baselineProduct = product();
    final initial = SyncEntityCodec.productToFields(baselineProduct);
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: baselineProduct.id,
      values: initial,
      deviceId: 'initial',
    );
    final phoneSale = baselineProduct.withSaleCount(
      1,
      soldAt: DateTime.utc(2026, 10, 10, 10),
    );
    final computerSale = baselineProduct.copyWith(price: 200).withSaleCount(
      1,
      soldAt: DateTime.utc(2026, 10, 10, 11),
    );

    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: initial,
      nextValues: SyncEntityCodec.productToFields(phoneSale),
      deviceId: 'phone',
    );
    final pc = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: initial,
      nextValues: SyncEntityCodec.productToFields(computerSale),
      deviceId: 'computer',
    );
    final merged = engine.merge(phone, pc);
    final values = engine.materialize(merged)!;
    final restored = SyncEntityCodec.productFromFields(values);
    expect(restored.soldCount, 2);
    expect(restored.accountedSales.map((sale) => sale.netIncome).toSet(),
        <double>{95, 190});
    expect(restored.accountedSales.map((sale) => sale.id).toSet(), hasLength(2));

    final repeated = engine.merge(merged, pc);
    expect(SyncEntityCodec.productFromFields(
        engine.materialize(repeated)!).accountedSales, hasLength(2));

    final compacted = engine.compactAcknowledgedOperations(
      repeated,
      deviceId: 'phone',
    );
    final revived = engine.merge(compacted, pc);
    final settled = SyncEntityCodec.productFromFields(
      engine.materialize(revived)!,
    );
    expect(settled.accountedSales.map((sale) => sale.netIncome).toSet(),
        <double>{95, 190});
  });
}
