import '../../../core/finance/income_calculator.dart';

enum CommissionPlatform {
  mihuashi('米画师'),
  huajia('画加'),
  bilibiliWorkshop('B站工坊'),
  linjie('临界'),
  offline('线下'),
  archivedOffline('留档线下');

  const CommissionPlatform(this.label);
  final String label;

  bool get defaultFeeEnabled {
    return switch (this) {
      CommissionPlatform.mihuashi ||
      CommissionPlatform.archivedOffline => true,
      _ => false,
    };
  }

  bool get usesOnlineOfflineSplit =>
      this == CommissionPlatform.archivedOffline;

  bool get defaultAdjustmentFeeEnabled {
    return this == CommissionPlatform.mihuashi;
  }
}

enum HuajiaLoveLevel {
  none('无', 1.0),
  level1('1级', 0.9),
  level2('2级', 0.8),
  level3('3级', 0.7);

  const HuajiaLoveLevel(this.label, this.feeMultiplier);

  final String label;
  final double feeMultiplier;
}

enum OrderArchiveOutcome {
  successful('顺利结算'),
  terminated('中止合作');

  const OrderArchiveOutcome(this.label);
  final String label;
}

class NodeDefinition {
  const NodeDefinition({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.progressPercent,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final int progressPercent;
  final bool builtIn;

  NodeDefinition snapshot() {
    return NodeDefinition(
      id: id,
      name: name,
      iconKey: iconKey,
      colorValue: colorValue,
      progressPercent: progressPercent,
      builtIn: builtIn,
    );
  }
}

class NodePreset {
  const NodePreset({
    required this.id,
    required this.name,
    required this.nodes,
  });

  final String id;
  final String name;
  final List<NodeDefinition> nodes;

  NodeDefinition nodeById(String nodeId) {
    if (nodes.isEmpty) {
      throw StateError('Node preset must contain at least one node.');
    }

    return nodes.firstWhere(
      (node) => node.id == nodeId,
      orElse: () => nodes.first,
    );
  }

  NodePreset snapshot() {
    return NodePreset(
      id: id,
      name: name,
      nodes: [for (final node in nodes) node.snapshot()],
    );
  }
}

const String notStartedNodeId = '__not_started__';

const NodeDefinition notStartedNode = NodeDefinition(
  id: notStartedNodeId,
  name: '未开始',
  iconKey: 'pause',
  colorValue: 0xFF8D8D8D,
  progressPercent: 0,
  builtIn: true,
);

class QueueOrder {
  const QueueOrder({
    required this.id,
    required this.platform,
    required this.title,
    required this.clientName,
    required this.deadline,
    required this.nodePresetId,
    required this.nodePresetSnapshot,
    required this.currentNodeId,
    this.currentNodeProgress = 0,
    this.price = 0,
    this.feeEnabled = false,
    this.huajiaLoveLevel = HuajiaLoveLevel.none,
    this.onlinePercent = 100,
    this.supplementAmount = 0,
    this.supplementFeeEnabled = false,
    this.deductionAmount = 0,
    this.deductionFeeEnabled = false,
    this.description = '',
    this.completedAt,
    this.settledAt,
    this.settledIncome,
    this.archiveOutcome,
    this.settlementNodeId,
    this.customRefundAmount,
    this.isArchived = false,
    this.isPinned = false,
  });

  final String id;
  final CommissionPlatform platform;
  final String title;
  final String clientName;
  final DateTime? deadline;
  final String nodePresetId;
  final NodePreset nodePresetSnapshot;
  final String currentNodeId;

  /// Progress inside the current node, in 10% steps from 0 to 100.
  final int currentNodeProgress;

  /// 原始稿价，仅详情页展示。
  final double price;

  /// 基础稿价是否参与 5% 手续费。
  final bool feeEnabled;

  /// 画加“真爱永恒”手续费折扣等级。
  final HuajiaLoveLevel huajiaLoveLevel;

  /// 留档线下时的线上比例。普通平台始终按 100% 参与手续费。
  final double onlinePercent;

  final double supplementAmount;
  final bool supplementFeeEnabled;
  final double deductionAmount;
  final bool deductionFeeEnabled;

  final String description;
  final DateTime? completedAt;

  /// Timestamp when income was finalized by manual archive settlement.
  final DateTime? settledAt;

  /// Frozen real-income snapshot captured when the order is archived/settled.
  final double? settledIncome;

  /// Why the order was archived. Null while the order is still active.
  final OrderArchiveOutcome? archiveOutcome;

  /// Final settlement node used when an order is terminated midway.
  final String? settlementNodeId;

  /// Manually negotiated refund amount used for custom termination settlement.
  final double? customRefundAmount;

  final bool isArchived;
  final bool isPinned;

  bool get isCompleted => completedAt != null;

  NodeDefinition get currentNode =>
      currentNodeId == notStartedNodeId
          ? notStartedNode
          : nodePresetSnapshot.nodeById(currentNodeId);

  int get progressPercent => currentNode.progressPercent;

  double get normalizedOnlinePercent => onlinePercent.clamp(0, 100).toDouble();

  double get offlinePercent => 100 - normalizedOnlinePercent;

  double get originalTotal =>
      price + supplementAmount - deductionAmount;

  double _feeFor(double amount, bool enabled) {
    return calculatePlatformServiceFee(
      amount: amount,
      feeEnabled: enabled,
      usesHuajiaRules: platform == CommissionPlatform.huajia,
      huajiaLoveMultiplier: huajiaLoveLevel.feeMultiplier,
      usesOnlineOfflineSplit: platform.usesOnlineOfflineSplit,
      onlinePercent: normalizedOnlinePercent,
      roundsFeeDownToWholeYuan: platform == CommissionPlatform.mihuashi,
    );
  }

  double get serviceFeeAmount => _feeFor(price, feeEnabled);

  double get supplementFeeAmount =>
      _feeFor(supplementAmount, supplementFeeEnabled);

  double get deductionFeeAmount =>
      _feeFor(deductionAmount, deductionFeeEnabled);

  double get realIncome => calculateAdjustedIncome(
        basePrice: price,
        baseFee: serviceFeeAmount,
        supplementAmount: supplementAmount,
        supplementFee: supplementFeeAmount,
        deductionAmount: deductionAmount,
        deductionFee: deductionFeeAmount,
      );

  double get settlementIncome => settledIncome ?? realIncome;

  NodeDefinition? get settlementNode {
    final nodeId = settlementNodeId;
    if (nodeId == null) return null;
    if (nodeId == notStartedNodeId) return notStartedNode;
    return nodePresetSnapshot.nodeById(nodeId);
  }

  double incomeAtProgress(int progressPercent) {
    final ratio = progressPercent.clamp(0, 100) / 100;
    return realIncome * ratio;
  }

  QueueOrder copyWith({
    CommissionPlatform? platform,
    String? title,
    String? clientName,
    DateTime? deadline,
    bool clearDeadline = false,
    String? nodePresetId,
    NodePreset? nodePresetSnapshot,
    String? currentNodeId,
    int? currentNodeProgress,
    double? price,
    bool? feeEnabled,
    HuajiaLoveLevel? huajiaLoveLevel,
    double? onlinePercent,
    double? supplementAmount,
    bool? supplementFeeEnabled,
    double? deductionAmount,
    bool? deductionFeeEnabled,
    String? description,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? settledAt,
    bool clearSettledAt = false,
    double? settledIncome,
    bool clearSettledIncome = false,
    OrderArchiveOutcome? archiveOutcome,
    bool clearArchiveOutcome = false,
    String? settlementNodeId,
    bool clearSettlementNodeId = false,
    double? customRefundAmount,
    bool clearCustomRefundAmount = false,
    bool? isArchived,
    bool? isPinned,
  }) {
    return QueueOrder(
      id: id,
      platform: platform ?? this.platform,
      title: title ?? this.title,
      clientName: clientName ?? this.clientName,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      nodePresetId: nodePresetId ?? this.nodePresetId,
      nodePresetSnapshot: nodePresetSnapshot ?? this.nodePresetSnapshot,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      currentNodeProgress:
          (currentNodeProgress ?? this.currentNodeProgress).clamp(0, 100).toInt(),
      price: price ?? this.price,
      feeEnabled: feeEnabled ?? this.feeEnabled,
      huajiaLoveLevel: huajiaLoveLevel ?? this.huajiaLoveLevel,
      onlinePercent: onlinePercent ?? this.onlinePercent,
      supplementAmount: supplementAmount ?? this.supplementAmount,
      supplementFeeEnabled:
          supplementFeeEnabled ?? this.supplementFeeEnabled,
      deductionAmount: deductionAmount ?? this.deductionAmount,
      deductionFeeEnabled:
          deductionFeeEnabled ?? this.deductionFeeEnabled,
      description: description ?? this.description,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
      settledIncome:
          clearSettledIncome ? null : (settledIncome ?? this.settledIncome),
      archiveOutcome:
          clearArchiveOutcome ? null : (archiveOutcome ?? this.archiveOutcome),
      settlementNodeId: clearSettlementNodeId
          ? null
          : (settlementNodeId ?? this.settlementNodeId),
      customRefundAmount: clearCustomRefundAmount
          ? null
          : (customRefundAmount ?? this.customRefundAmount),
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
