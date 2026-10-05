import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const preset = NodePreset(
    id: 'preset',
    name: '默认',
    nodes: <NodeDefinition>[
      NodeDefinition(
        id: 'draft',
        name: '草图',
        iconKey: 'edit',
        colorValue: 0xFF777777,
        progressPercent: 20,
      ),
    ],
  );

  QueueOrder order(String id, int defaultOrder) => QueueOrder(
        id: id,
        platform: CommissionPlatform.mihuashi,
        title: id,
        clientName: 'client',
        deadline: null,
        nodePresetId: preset.id,
        nodePresetSnapshot: preset,
        currentNodeId: 'draft',
        defaultOrder: defaultOrder,
      );

  FinishedProduct product(String id, int defaultOrder) => FinishedProduct(
        id: id,
        title: id,
        platform: CommissionPlatform.mihuashi,
        saleType: ProductSaleType.single,
        defaultOrder: defaultOrder,
      );

  test('order store restores canonical newest-first default order', () {
    final store = OrderStore();
    addTearDown(store.dispose);

    store.replaceAll(<QueueOrder>[
      order('order-100', 100),
      order('order-300', 300),
      order('order-200', 200),
    ]);

    expect(
      store.orders.map((item) => item.id),
      <String>['order-300', 'order-200', 'order-100'],
    );
  });

  test('product store restores canonical newest-first default order', () {
    final store = ProductStore();
    addTearDown(store.dispose);

    store.replaceAll(<FinishedProduct>[
      product('product-100', 100),
      product('product-300', 300),
      product('product-200', 200),
    ]);

    expect(
      store.products.map((item) => item.id),
      <String>['product-300', 'product-200', 'product-100'],
    );
  });

  test('legacy timestamp ids give the same order on every device', () {
    final store = OrderStore();
    addTearDown(store.dispose);

    store.replaceAll(<QueueOrder>[
      order('order-1700000000000000', 0),
      order('order-1900000000000000', 0),
      order('order-1800000000000000', 0),
    ]);

    expect(
      store.orders.map((item) => item.id),
      <String>[
        'order-1900000000000000',
        'order-1800000000000000',
        'order-1700000000000000',
      ],
    );
  });
}
