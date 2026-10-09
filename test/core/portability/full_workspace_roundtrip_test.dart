import 'dart:convert';

import 'package:flutter_app/core/account/account_models.dart';
import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/core/sync/sync_entity_codec.dart';
import 'package:flutter_app/features/focus/domain/focus_session.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orderKeys = <String>{
    'id',
    'platform',
    'title',
    'clientName',
    'deadline',
    'nodePresetId',
    'nodePresetSnapshot',
    'currentNodeId',
    'currentNodeProgress',
    'price',
    'feeEnabled',
    'huajiaLoveLevel',
    'onlinePercent',
    'supplementAmount',
    'supplementFeeEnabled',
    'deductionAmount',
    'deductionFeeEnabled',
    'description',
    'tags',
    'defaultOrder',
    'referenceImages',
    'completedAt',
    'settledAt',
    'settledIncome',
    'archiveOutcome',
    'settlementNodeId',
    'customRefundAmount',
    'isArchived',
    'isPinned',
  };

  const productKeys = <String>{
    'id',
    'title',
    'platform',
    'saleType',
    'price',
    'feeEnabled',
    'huajiaLoveLevel',
    'onlinePercent',
    'supplementAmount',
    'supplementFeeEnabled',
    'deductionAmount',
    'deductionFeeEnabled',
    'description',
    'defaultOrder',
    'soldCount',
    'saleRecords',
    'isArchived',
    'isPinned',
  };

  const nodeA = NodeDefinition(
    id: 'draft',
    name: '草图',
    iconKey: 'edit',
    colorValue: 0xFF112233,
    progressPercent: 20,
    builtIn: true,
  );
  const nodeB = NodeDefinition(
    id: 'finish',
    name: '成稿',
    iconKey: 'image',
    colorValue: 0xFF445566,
    progressPercent: 100,
  );
  const preset = NodePreset(
    id: 'preset-all-fields',
    name: '全字段模板',
    nodes: <NodeDefinition>[nodeA, nodeB],
  );

  final order = QueueOrder(
    id: 'order-1790000000000000',
    platform: CommissionPlatform.archivedOffline,
    title: '全字段排单',
    clientName: '测试单主',
    deadline: DateTime.utc(2026, 11, 1, 8, 30),
    nodePresetId: preset.id,
    nodePresetSnapshot: preset,
    currentNodeId: nodeB.id,
    currentNodeProgress: 70,
    price: 1234.5,
    feeEnabled: true,
    huajiaLoveLevel: HuajiaLoveLevel.level2,
    onlinePercent: 42.5,
    supplementAmount: 88.8,
    supplementFeeEnabled: true,
    deductionAmount: 12.3,
    deductionFeeEnabled: true,
    description: '所有字段都要回来',
    defaultOrder: 1790000000000000,
    referenceImages: <OrderReferenceImage>[
      OrderReferenceImage(
        id: 'ref-all',
        fileName: '参考图.png',
        relativePath:
            'assets/order-reference-images/b3JkZXItMTc5MDAwMDAwMDAwMDAwMA/ref-all.png',
        addedAt: DateTime.utc(2026, 10, 5, 10, 20, 30),
        sizeBytes: 2048,
      ),
    ],
    completedAt: DateTime.utc(2026, 10, 20, 1),
    settledAt: DateTime.utc(2026, 10, 21, 2),
    settledIncome: 999.25,
    archiveOutcome: OrderArchiveOutcome.terminated,
    settlementNodeId: nodeA.id,
    customRefundAmount: 66.6,
    isArchived: true,
    isPinned: true,
  );

  final focusSession = FocusSession(
    id: 'focus-roundtrip',
    startedAt: DateTime.utc(2026, 10, 6, 8, 0),
    endedAt: DateTime.utc(2026, 10, 6, 8, 45, 12),
    orderId: order.id,
    orderTitleSnapshot: order.title,
  );

  final product = FinishedProduct(
    id: 'product-1790000000000100',
    title: '全字段成品',
    platform: CommissionPlatform.huajia,
    saleType: ProductSaleType.multiple,
    price: 456.7,
    feeEnabled: true,
    huajiaLoveLevel: HuajiaLoveLevel.level3,
    onlinePercent: 75,
    supplementAmount: 20,
    supplementFeeEnabled: true,
    deductionAmount: 3.5,
    deductionFeeEnabled: true,
    description: '成品全部字段',
    defaultOrder: 1790000000000100,
    soldCount: 2,
    saleRecords: <DateTime>[
      DateTime.utc(2026, 10, 2, 3, 4),
      DateTime.utc(2026, 10, 3, 4, 5),
    ],
    isArchived: true,
    isPinned: true,
  );

  final account = AccountSyncState(
    accountId: 'account_roundtrip',
    accountName: '测试账号',
    password: 'password-123',
    accountNameUpdatedAt: DateTime.utc(2026, 10, 1, 1),
    passwordUpdatedAt: DateTime.utc(2026, 10, 2, 2),
    avatarBase64: base64Encode(<int>[1, 2, 3, 4]),
    avatarUpdatedAt: DateTime.utc(2026, 10, 3, 3),
    devices: <String, AccountDevice>{
      'phone': AccountDevice(
        id: 'phone',
        name: '手机',
        platform: 'android',
        firstSeenAt: DateTime.utc(2026, 9, 1),
        lastSeenAt: DateTime.utc(2026, 10, 5),
        nameUpdatedAt: DateTime.utc(2026, 10, 4),
        syncTransportId: 'AAAAAAAAAAAAAAAAAAAA-BBBBBBBBBBBBBBBBBBBB',
      ),
      'desktop': AccountDevice(
        id: 'desktop',
        name: '电脑',
        platform: 'windows',
        firstSeenAt: DateTime.utc(2026, 9, 2),
        lastSeenAt: DateTime.utc(2026, 10, 4),
        syncTransportId: 'CCCCCCCCCCCCCCCCCCCC-DDDDDDDDDDDDDDDDDDDD',
      ),
    },
    revocations: <String, DeviceRevocation>{
      'old-device': DeviceRevocation(
        deviceId: 'old-device',
        revokedAt: DateTime.utc(2026, 10, 4, 12),
      ),
    },
  );

  const settings = <String, dynamic>{
    'id': 'app',
    'themeMode': 'system',
    'themePaletteId': 'guild',
    'features': <String, dynamic>{
      'clientInfo': true,
      'nodeProgress': true,
      'search': true,
      'sorting': true,
      'viewSwitch': true,
      'products': true,
      'schedule': true,
      'statistics': true,
      'deadlineReminders': false,
      'abstractMode': true,
    },
    'orderCardView': true,
    'productCardView': false,
    'orderSortMode': 'deadline',
    'productSortMode': 'soldCount',
    'desktopNavigationOpen': false,
  };

  test('backup and sync codecs expose every current entity field', () {
    expect(SyncEntityCodec.orderToFields(order).keys.toSet(), orderKeys);
    expect(SyncEntityCodec.productToFields(product).keys.toSet(), productKeys);
  });

  test('full backup round trip keeps all workspace and account fields', () {
    final source = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 1, 2, 3),
      orders: <QueueOrder>[order],
      products: <FinishedProduct>[product],
      nodePresets: const <NodePreset>[preset],
      focusSessions: <FocusSession>[focusSession],
      accountSyncState: account,
      syncRecords: const <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'settings',
          'id': 'app',
          'accountId': 'account_roundtrip',
        },
      ],
      settings: settings,
    );

    final restored = AppBackupData.decode(source.encode(pretty: false));
    final restoredOrder = restored.orders.single;
    final restoredProduct = restored.products.single;
    final restoredPreset = restored.nodePresets.single;
    final restoredFocus = restored.focusSessions.single;
    final restoredAccount = restored.accountSyncState!;

    expect(restored.exportedAt.toUtc(), source.exportedAt.toUtc());
    expect(restored.settings, settings);
    expect(restored.syncRecords, source.syncRecords);
    expect(restoredFocus.toJson(), focusSession.toJson());

    expect(restoredOrder.id, order.id);
    expect(restoredOrder.platform, order.platform);
    expect(restoredOrder.title, order.title);
    expect(restoredOrder.clientName, order.clientName);
    expect(restoredOrder.deadline!.toUtc(), order.deadline!.toUtc());
    expect(restoredOrder.nodePresetId, order.nodePresetId);
    expect(restoredOrder.currentNodeId, order.currentNodeId);
    expect(restoredOrder.currentNodeProgress, order.currentNodeProgress);
    expect(restoredOrder.price, order.price);
    expect(restoredOrder.feeEnabled, order.feeEnabled);
    expect(restoredOrder.huajiaLoveLevel, order.huajiaLoveLevel);
    expect(restoredOrder.onlinePercent, order.onlinePercent);
    expect(restoredOrder.supplementAmount, order.supplementAmount);
    expect(
      restoredOrder.supplementFeeEnabled,
      order.supplementFeeEnabled,
    );
    expect(restoredOrder.deductionAmount, order.deductionAmount);
    expect(restoredOrder.deductionFeeEnabled, order.deductionFeeEnabled);
    expect(restoredOrder.description, order.description);
    expect(restoredOrder.defaultOrder, order.defaultOrder);
    expect(restoredOrder.completedAt!.toUtc(), order.completedAt!.toUtc());
    expect(restoredOrder.settledAt!.toUtc(), order.settledAt!.toUtc());
    expect(restoredOrder.settledIncome, order.settledIncome);
    expect(restoredOrder.archiveOutcome, order.archiveOutcome);
    expect(restoredOrder.settlementNodeId, order.settlementNodeId);
    expect(restoredOrder.customRefundAmount, order.customRefundAmount);
    expect(restoredOrder.isArchived, order.isArchived);
    expect(restoredOrder.isPinned, order.isPinned);

    final restoredImage = restoredOrder.referenceImages.single;
    final sourceImage = order.referenceImages.single;
    expect(restoredImage.id, sourceImage.id);
    expect(restoredImage.fileName, sourceImage.fileName);
    expect(restoredImage.relativePath, sourceImage.relativePath);
    expect(restoredImage.addedAt.toUtc(), sourceImage.addedAt.toUtc());
    expect(restoredImage.sizeBytes, sourceImage.sizeBytes);

    expect(restoredProduct.id, product.id);
    expect(restoredProduct.title, product.title);
    expect(restoredProduct.platform, product.platform);
    expect(restoredProduct.saleType, product.saleType);
    expect(restoredProduct.price, product.price);
    expect(restoredProduct.feeEnabled, product.feeEnabled);
    expect(restoredProduct.huajiaLoveLevel, product.huajiaLoveLevel);
    expect(restoredProduct.onlinePercent, product.onlinePercent);
    expect(restoredProduct.supplementAmount, product.supplementAmount);
    expect(
      restoredProduct.supplementFeeEnabled,
      product.supplementFeeEnabled,
    );
    expect(restoredProduct.deductionAmount, product.deductionAmount);
    expect(
      restoredProduct.deductionFeeEnabled,
      product.deductionFeeEnabled,
    );
    expect(restoredProduct.description, product.description);
    expect(restoredProduct.defaultOrder, product.defaultOrder);
    expect(restoredProduct.soldCount, product.soldCount);
    expect(
      restoredProduct.saleRecords.map((value) => value.toUtc()).toList(),
      product.saleRecords.map((value) => value.toUtc()).toList(),
    );
    expect(restoredProduct.isArchived, product.isArchived);
    expect(restoredProduct.isPinned, product.isPinned);

    expect(restoredPreset.id, preset.id);
    expect(restoredPreset.name, preset.name);
    expect(restoredPreset.nodes, hasLength(2));
    expect(restoredPreset.nodes[0].id, nodeA.id);
    expect(restoredPreset.nodes[0].name, nodeA.name);
    expect(restoredPreset.nodes[0].iconKey, nodeA.iconKey);
    expect(restoredPreset.nodes[0].colorValue, nodeA.colorValue);
    expect(restoredPreset.nodes[0].progressPercent, nodeA.progressPercent);
    expect(restoredPreset.nodes[0].builtIn, nodeA.builtIn);

    expect(restoredAccount.toJson(), account.toJson());
  });

  test('sync entity round trip keeps all order, product and focus fields', () {
    final orderFields = SyncEntityCodec.orderToFields(order);
    final productFields = SyncEntityCodec.productToFields(product);
    final focusFields = SyncEntityCodec.focusSessionToFields(focusSession);

    final restoredOrder = SyncEntityCodec.orderFromFields(orderFields);
    final restoredProduct = SyncEntityCodec.productFromFields(productFields);
    final restoredFocus = SyncEntityCodec.focusSessionFromFields(focusFields);

    expect(SyncEntityCodec.orderToFields(restoredOrder), orderFields);
    expect(SyncEntityCodec.productToFields(restoredProduct), productFields);
    expect(SyncEntityCodec.focusSessionToFields(restoredFocus), focusFields);
  });

  test('legacy entities do not require a defaultOrder field', () {
    final legacyOrder = QueueOrder(
      id: 'order-123456789',
      platform: CommissionPlatform.mihuashi,
      title: '旧排单',
      clientName: '旧单主',
      deadline: null,
      nodePresetId: preset.id,
      nodePresetSnapshot: preset,
      currentNodeId: nodeA.id,
    );
    final legacyProduct = FinishedProduct(
      id: 'product-987654321',
      title: '旧成品',
      platform: CommissionPlatform.mihuashi,
      saleType: ProductSaleType.single,
    );

    final orderFields = SyncEntityCodec.orderToFields(legacyOrder);
    final productFields = SyncEntityCodec.productToFields(legacyProduct);

    expect(orderFields.containsKey('defaultOrder'), isFalse);
    expect(productFields.containsKey('defaultOrder'), isFalse);
    expect(
      SyncEntityCodec.orderFromFields(orderFields).effectiveDefaultOrder,
      123456789,
    );
    expect(
      SyncEntityCodec.productFromFields(productFields).effectiveDefaultOrder,
      987654321,
    );
  });

  test('legacy entity ids get deterministic default order', () {
    expect(defaultOrderFromId('order-123456789'), 123456789);
    expect(defaultOrderFromId('product-987654321'), 987654321);
    expect(defaultOrderFromId('custom-id'), 0);
  });
}
