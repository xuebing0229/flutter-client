import 'package:flutter_app/core/sync/portable_sync_workspace_validator.dart';
import 'package:flutter_app/core/sync/sync_entity_codec.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old portable product sync backup without receipts remains valid', () {
    final old = FinishedProduct(
      id: 'legacy-bundle-product',
      title: '历史成品',
      platform: CommissionPlatform.mihuashi,
      saleType: ProductSaleType.multiple,
      price: 100,
      feeEnabled: true,
      soldCount: 1,
      saleRecords: <DateTime>[DateTime.utc(2026, 8, 1)],
    );
    final migrated = SyncEntityCodec.productToFields(old);
    final previousVersion = <String, dynamic>{...migrated}
      ..remove('saleReceipts');
    final oldRecord = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: old.id,
      values: previousVersion,
      deviceId: 'old-phone',
    ).copyWith(accountId: 'account-1');

    expect(
      PortableSyncWorkspaceValidator.recordsMatchWorkspace(
        accountId: 'account-1',
        records: [oldRecord.toJson()],
        orders: const {},
        products: {old.id: migrated},
        presets: const {},
      ),
      isTrue,
    );
    // The compatibility exception only permits the *missing* new field;
    // mismatches to historic timestamps or prices still fail validation.
    expect(
      PortableSyncWorkspaceValidator.recordsMatchWorkspace(
        accountId: 'account-1',
        records: [oldRecord.toJson()],
        orders: const {},
        products: {
          old.id: <String, dynamic>{...migrated, 'price': 500.0},
        },
        presets: const {},
      ),
      isFalse,
    );
  });

  test('migrated settings ignore the retained legacy feature aggregate', () {
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: const <String, dynamic>{
        'id': 'app',
        'features': <String, dynamic>{
          'search': false,
          'sorting': true,
        },
        'feature.search': false,
        'feature.sorting': true,
        'themeMode': 'system',
      },
      deviceId: 'phone',
    ).copyWith(accountId: 'account-1');

    final matches = PortableSyncWorkspaceValidator.recordsMatchWorkspace(
      accountId: 'account-1',
      records: <Map<String, dynamic>>[record.toJson()],
      orders: const <String, Map<String, dynamic>>{},
      products: const <String, Map<String, dynamic>>{},
      presets: const <String, Map<String, dynamic>>{},
      settings: const <String, dynamic>{
        'id': 'app',
        'feature.search': false,
        'feature.sorting': true,
        'themeMode': 'system',
      },
    );

    expect(matches, isTrue);
  });
}
