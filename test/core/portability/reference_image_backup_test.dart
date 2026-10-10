import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference image metadata survives backup round trip', () {
    const node = NodeDefinition(
      id: 'draft',
      name: '草图',
      iconKey: 'circle',
      colorValue: 0xFF777777,
      progressPercent: 20,
    );
    const preset = NodePreset(
      id: 'preset',
      name: '默认',
      nodes: <NodeDefinition>[node],
    );
    final addedAt = DateTime(2026, 10, 5, 20, 30);
    final order = QueueOrder(
      id: 'order-1',
      platform: CommissionPlatform.mihuashi,
      title: '测试',
      clientName: '单主',
      deadline: null,
      nodePresetId: preset.id,
      nodePresetSnapshot: preset,
      currentNodeId: node.id,
      referenceImages: <OrderReferenceImage>[
        OrderReferenceImage(
          id: 'ref-1',
          fileName: '参考.png',
          relativePath:
              'assets/order-reference-images/b3JkZXItMQ/ref-1.png',
          addedAt: addedAt,
          sizeBytes: 2048,
        ),
      ],
    );

    final encoded = AppBackupData(
      exportedAt: DateTime(2026, 10, 5, 21),
      orders: <QueueOrder>[order],
      products: const [],
      nodePresets: const <NodePreset>[preset],
    ).encode(pretty: false);

    final decoded = AppBackupData.decode(encoded);
    final image = decoded.orders.single.referenceImages.single;

    expect(image.id, 'ref-1');
    expect(image.fileName, '参考.png');
    expect(
      image.relativePath,
      'assets/order-reference-images/b3JkZXItMQ/ref-1.png',
    );
    expect(image.addedAt, addedAt);
    expect(image.sizeBytes, 2048);
  });

  test('product reference image metadata survives backup round trip', () {
    final addedAt = DateTime(2026, 10, 10, 9, 30);
    final product = FinishedProduct(
      id: 'product-1',
      title: '成品测试',
      platform: CommissionPlatform.huajia,
      saleType: ProductSaleType.multiple,
      referenceImages: <OrderReferenceImage>[
        OrderReferenceImage(
          id: 'ref-product-1',
          fileName: '成品参考.webp',
          relativePath:
              'assets/order-reference-images/cHJvZHVjdC0x/ref-product-1.webp',
          addedAt: addedAt,
          sizeBytes: 4096,
        ),
      ],
    );

    final encoded = AppBackupData(
      exportedAt: DateTime(2026, 10, 10, 10),
      orders: const <QueueOrder>[],
      products: <FinishedProduct>[product],
      nodePresets: const <NodePreset>[],
    ).encode(pretty: false);

    final decoded = AppBackupData.decode(encoded);
    final image = decoded.products.single.referenceImages.single;

    expect(image.id, 'ref-product-1');
    expect(image.fileName, '成品参考.webp');
    expect(
      image.relativePath,
      'assets/order-reference-images/cHJvZHVjdC0x/ref-product-1.webp',
    );
    expect(image.addedAt, addedAt);
    expect(image.sizeBytes, 4096);
  });
}
