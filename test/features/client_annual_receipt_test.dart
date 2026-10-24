import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/features/orders/domain/queue_order.dart';
import 'package:flutter_client/features/shared/presentation/receipt_page.dart';

void main() {
  const preset = NodePreset(
    id: 'preset',
    name: '测试节点',
    nodes: [
      NodeDefinition(
        id: 'half',
        name: '进行中',
        iconKey: 'edit',
        colorValue: 0xFF000000,
        progressPercent: 50,
      ),
      NodeDefinition(
        id: 'done',
        name: '完成',
        iconKey: 'check',
        colorValue: 0xFF000000,
        progressPercent: 100,
      ),
    ],
  );

  QueueOrder order({
    required String id,
    required String title,
    required String client,
    required double price,
    required DateTime completedAt,
    DateTime? settledAt,
    CommissionPlatform platform = CommissionPlatform.mihuashi,
    OrderArchiveOutcome? outcome,
    String? settlementNodeId,
    double? customRefundAmount,
  }) {
    return QueueOrder(
      id: id,
      platform: platform,
      title: title,
      clientName: client,
      deadline: null,
      nodePresetId: preset.id,
      nodePresetSnapshot: preset,
      currentNodeId: outcome == OrderArchiveOutcome.terminated
          ? (settlementNodeId ?? 'done')
          : 'done',
      price: price,
      completedAt: completedAt,
      settledAt: settledAt,
      archiveOutcome: outcome,
      settlementNodeId: settlementNodeId,
      customRefundAmount: customRefundAmount,
      isArchived: settledAt != null,
    );
  }

  test('annual receipt filters by client and year and sorts by completion date', () {
    final data = AnnualReceiptData.fromOrders(
      clientName: '  Alice ',
      year: 2026,
      orders: [
        order(
          id: '3',
          title: '下一年',
          client: 'Alice',
          price: 999,
          completedAt: DateTime(2027, 1, 1),
        ),
        order(
          id: '2',
          title: '第二张',
          client: 'alice',
          price: 200,
          completedAt: DateTime(2026, 8, 2),
        ),
        order(
          id: '1',
          title: '第一张',
          client: 'Alice',
          price: 100,
          completedAt: DateTime(2026, 2, 1),
        ),
        order(
          id: '4',
          title: '别的单主',
          client: 'Bob',
          price: 888,
          completedAt: DateTime(2026, 3, 1),
        ),
      ],
    );

    expect(data.clientName, 'Alice');
    expect(data.entries.map((entry) => entry.title), ['第一张', '第二张']);
    expect(data.total, 300);
  });

  test('annual receipt uses customer-facing amount for terminated orders', () {
    final nodeSettlement = order(
      id: 'node',
      title: '节点结算',
      client: 'Alice',
      price: 200,
      completedAt: DateTime(2026, 5, 1),
      settledAt: DateTime(2026, 5, 1),
      outcome: OrderArchiveOutcome.terminated,
      settlementNodeId: 'half',
    );
    final refundSettlement = order(
      id: 'refund',
      title: '退款结算',
      client: 'Alice',
      price: 300,
      completedAt: DateTime(2026, 6, 1),
      settledAt: DateTime(2026, 6, 1),
      outcome: OrderArchiveOutcome.terminated,
      customRefundAmount: 80,
    );

    expect(annualReceiptAmountForOrder(nodeSettlement), 100);
    expect(annualReceiptAmountForOrder(refundSettlement), 220);
  });
}
