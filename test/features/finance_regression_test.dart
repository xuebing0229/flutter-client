import 'package:flutter_app/core/finance/pricing_adjustments.dart';
import 'package:flutter_app/features/orders/data/node_presets.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/state/order_store.dart';
import 'package:flutter_app/features/shared/presentation/adjustment_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform adjustment defaults keep Huajia off and Mihuashi on', () {
    expect(CommissionPlatform.mihuashi.defaultAdjustmentFeeEnabled, isTrue);
    expect(CommissionPlatform.huajia.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.bilibiliWorkshop.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.linjie.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.offline.defaultAdjustmentFeeEnabled, isFalse);
    expect(CommissionPlatform.archivedOffline.defaultAdjustmentFeeEnabled, isFalse);
  });

  test('adjustment edit applies the user delta on top of a remote amount', () {
    final merged = mergeAdjustmentEdit(
      baselineAmount: 10,
      baselineFeeEnabled: false,
      draft: const AdjustmentDialogResult(
        amount: 0,
        feeEnabled: false,
      ),
      currentAmount: 15,
      currentFeeEnabled: true,
    );

    expect(merged.amount, 5);
    // The checkbox was untouched locally, so the remote fee switch survives.
    expect(merged.feeEnabled, isTrue);
  });

  test('adjustment edit clamps only the final merged amount at zero', () {
    final merged = mergeAdjustmentEdit(
      baselineAmount: 10,
      baselineFeeEnabled: true,
      draft: const AdjustmentDialogResult(
        amount: 0,
        feeEnabled: false,
      ),
      currentAmount: 4,
      currentFeeEnabled: true,
    );

    expect(merged.amount, 0);
    // This checkbox was explicitly changed by the local dialog.
    expect(merged.feeEnabled, isFalse);
  });

  test('pricing presets apply proportional rules before flat amounts', () {
    const adjustments = <PricingAdjustment>[
      PricingAdjustment(
        id: 'commercial',
        name: '商用',
        multiplier: 2,
      ),
      PricingAdjustment(
        id: 'rush',
        name: '加急',
        percent: 30,
      ),
      PricingAdjustment(
        id: 'background',
        name: '复杂背景',
        fixedAmount: 100,
      ),
    ];

    expect(applyPricingAdjustments(1000, adjustments), 2700);
    expect(
      pricedSupplementAmount(
        basePrice: 1000,
        supplementAmount: 200,
        adjustments: adjustments,
        participates: true,
      ),
      520,
    );
    expect(
      pricedSupplementAmount(
        basePrice: 1000,
        supplementAmount: 200,
        adjustments: adjustments,
        participates: false,
      ),
      200,
    );
  });

  test('order pricing snapshot and supplement participation affect total', () {
    final order = QueueOrder(
      id: 'order-pricing',
      platform: CommissionPlatform.offline,
      title: '测试',
      clientName: '单主',
      deadline: null,
      nodePresetId: defaultNodePreset.id,
      nodePresetSnapshot: defaultNodePreset,
      currentNodeId: defaultNodePreset.nodes.first.id,
      price: 1000,
      feeEnabled: false,
      supplementAmount: 200,
      supplementPricingEnabled: true,
      pricingAdjustments: const <PricingAdjustment>[
        PricingAdjustment(id: 'commercial', name: '商用', multiplier: 2),
      ],
    );

    expect(order.pricedBaseAmount, 2000);
    expect(order.pricedSupplementAmountValue, 400);
    expect(order.originalTotal, 2400);
  });

  test('supplement pricing switch merges independently from fee switch', () {
    final merged = mergeAdjustmentEdit(
      baselineAmount: 100,
      baselineFeeEnabled: false,
      baselinePricingEnabled: false,
      draft: const AdjustmentDialogResult(
        amount: 120,
        feeEnabled: false,
        pricingEnabled: true,
      ),
      currentAmount: 130,
      currentFeeEnabled: true,
      currentPricingEnabled: false,
    );

    expect(merged.amount, 150);
    expect(merged.feeEnabled, isTrue);
    expect(merged.pricingEnabled, isTrue);
  });

  test('invalid custom refunds cannot archive or poison settled income', () {
    final store = OrderStore();
    final order = QueueOrder(
      id: 'order-finance',
      platform: CommissionPlatform.mihuashi,
      title: '测试',
      clientName: '单主',
      deadline: null,
      nodePresetId: defaultNodePreset.id,
      nodePresetSnapshot: defaultNodePreset,
      currentNodeId: defaultNodePreset.nodes.first.id,
      price: 100,
      feeEnabled: true,
    );
    store.addOrder(order);

    store.archiveAsTerminatedWithCustomRefund(order.id, double.nan);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);

    store.archiveAsTerminatedWithCustomRefund(order.id, double.infinity);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);

    store.archiveAsTerminatedWithCustomRefund(order.id, -1);
    expect(store.byId(order.id).isArchived, isFalse);
    expect(store.byId(order.id).settledIncome, isNull);
  });
}