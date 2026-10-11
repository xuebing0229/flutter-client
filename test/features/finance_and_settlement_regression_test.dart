import 'package:flutter_app/core/finance/income_calculator.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
import 'package:flutter_app/features/products/state/product_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const preset = NodePreset(
    id: 'settlement-check',
    name: '结算回归测试',
    nodes: <NodeDefinition>[
      NodeDefinition(
        id: 'draft',
        name: '草图',
        iconKey: 'edit',
        colorValue: 0xFF888888,
        progressPercent: 20,
      ),
      NodeDefinition(
        id: 'final',
        name: '成稿',
        iconKey: 'image',
        colorValue: 0xFF555555,
        progressPercent: 100,
      ),
    ],
  );

  QueueOrder order({
    double price = 200,
    bool feeEnabled = true,
  }) =>
      QueueOrder(
        id: 'order-finance-1',
        platform: CommissionPlatform.mihuashi,
        title: '测试排单',
        clientName: '测试单主',
        deadline: null,
        nodePresetId: preset.id,
        nodePresetSnapshot: preset,
        currentNodeId: 'draft',
        price: price,
        feeEnabled: feeEnabled,
      );

  test('米画师的每笔手续费按照整数向下取整', () {
    final source = order(price: 199);
    expect(source.serviceFeeAmount, 9);
    expect(source.realIncome, 190);
  });

  test('画加真爱折扣只应用于阶梯手续费，不重复折扣通道费', () {
    expect(
      calculateHuajiaServiceFee(
        amount: 900,
        feeEnabled: true,
        loveDiscountMultiplier: 0.5,
      ),
      16.5,
    );
  });

  test('补款和减款的手续费独立计算，避免重复计算稿费手续费', () {
    final withAdjustments = order().copyWith(
      supplementAmount: 100,
      supplementFeeEnabled: true,
      deductionAmount: 40,
      deductionFeeEnabled: true,
    );
    // 200 - 10 + (100 - 5) - (40 - 2) = 247.
    expect(withAdjustments.realIncome, 247);
  });

  test('顺利归档锁定收入，后续修改原价不能篡改已结算账目', () {
    final store = OrderStore();
    addTearDown(store.dispose);
    store.addOrder(order());

    store.archiveAsSettled('order-finance-1');
    final archived = store.byId('order-finance-1');
    expect(archived.isArchived, isTrue);
    expect(archived.settlementIncome, 190);

    store.updateOrder(archived.copyWith(price: 500));
    expect(store.byId('order-finance-1').settlementIncome, 190);
  });

  test('中止合作退款金额只影响最终结算收入', () {
    final store = OrderStore();
    addTearDown(store.dispose);
    store.addOrder(order());
    store.archiveAsTerminatedWithCustomRefund('order-finance-1', 50);

    final archived = store.byId('order-finance-1');
    expect(archived.isArchived, isTrue);
    expect(archived.archiveOutcome, OrderArchiveOutcome.terminated);
    expect(archived.settlementIncome, 140);
    expect(archived.customRefundAmount, 50);
  });

  test('确认成稿节点只标记已交稿，不提前归档统计收入', () {
    final store = OrderStore();
    addTearDown(store.dispose);
    store.addOrder(order().copyWith(currentNodeId: 'final'));
    store.advanceOrder('order-finance-1');

    final completed = store.byId('order-finance-1');
    expect(completed.isCompleted, isTrue);
    expect(completed.isArchived, isFalse);
    expect(completed.settledAt, isNull);
  });

  test('成品多次售卖同时记录次数与时间', () {
    final store = ProductStore();
    addTearDown(store.dispose);
    store.addProduct(const FinishedProduct(
      id: 'product-sale-1',
      title: '测试成品',
      platform: CommissionPlatform.mihuashi,
      saleType: ProductSaleType.multiple,
      price: 100,
      feeEnabled: true,
    ));
    final first = DateTime.utc(2026, 10, 10, 8);
    final second = DateTime.utc(2026, 10, 11, 8);
    store.markSold('product-sale-1', soldAt: first);
    store.markSold('product-sale-1', soldAt: second);

    final result = store.byId('product-sale-1');
    expect(result.soldCount, 2);
    expect(result.saleRecords, [first, second]);
  });
}
