import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/queue_order.dart';

class OrderStore extends ChangeNotifier {
  final List<QueueOrder> _orders = <QueueOrder>[];

  UnmodifiableListView<QueueOrder> get orders => UnmodifiableListView(_orders);

  bool contains(String id) {
    return _orders.any((order) => order.id == id);
  }

  QueueOrder byId(String id) {
    return _orders.firstWhere((order) => order.id == id);
  }

  QueueOrder _normalizeActiveNode(QueueOrder order) {
    if (order.isArchived || order.nodePresetSnapshot.nodes.isEmpty) {
      return order;
    }

    final nodes = order.nodePresetSnapshot.nodes;
    if (order.isCompleted) {
      final finalNodeId = nodes.last.id;
      if (order.currentNodeId == finalNodeId &&
          order.currentNodeProgress == 0) {
        return order;
      }
      return order.copyWith(
        currentNodeId: finalNodeId,
        currentNodeProgress: 0,
      );
    }

    final currentNodeExists =
        nodes.any((node) => node.id == order.currentNodeId);
    if (currentNodeExists) return order;

    return order.copyWith(
      currentNodeId: nodes.first.id,
      currentNodeProgress: 0,
    );
  }

  void replaceAll(Iterable<QueueOrder> orders) {
    _orders
      ..clear()
      ..addAll(orders.map(_normalizeActiveNode));
    notifyListeners();
  }

  void addOrder(QueueOrder order) {
    _orders.insert(0, _normalizeActiveNode(order));
    notifyListeners();
  }

  void updateOrder(QueueOrder updated) {
    final index = _orders.indexWhere((order) => order.id == updated.id);
    if (index == -1) {
      return;
    }
    _orders[index] = updated;
    notifyListeners();
  }

  void deleteOrder(String id) {
    _orders.removeWhere((order) => order.id == id);
    notifyListeners();
  }

  void deleteOrders(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _orders.removeWhere((order) => idSet.contains(order.id));
    notifyListeners();
  }

  void setArchived(String id, bool archived) {
    if (archived) {
      archiveAsSettled(id);
    } else {
      restoreArchivedOrder(id);
    }
  }

  void archiveAsSettled(String id) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    final nodes = order.nodePresetSnapshot.nodes;
    final finalNodeId =
        nodes.isEmpty ? order.currentNodeId : nodes.last.id;

    _orders[index] = order.copyWith(
      currentNodeId: finalNodeId,
      currentNodeProgress: 0,
      completedAt: order.completedAt ?? DateTime.now(),
      settledAt: DateTime.now(),
      settledIncome: order.realIncome,
      archiveOutcome: OrderArchiveOutcome.successful,
      clearSettlementNodeId: true,
      clearCustomRefundAmount: true,
      isArchived: true,
      isPinned: false,
    );
    notifyListeners();
  }

  void archiveManyAsSettled(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    final now = DateTime.now();
    for (var i = 0; i < _orders.length; i++) {
      final order = _orders[i];
      if (!idSet.contains(order.id) || order.isArchived) continue;

      final nodes = order.nodePresetSnapshot.nodes;
      final finalNodeId =
          nodes.isEmpty ? order.currentNodeId : nodes.last.id;

      _orders[i] = order.copyWith(
        currentNodeId: finalNodeId,
        currentNodeProgress: 0,
        completedAt: order.completedAt ?? now,
        settledAt: now,
        settledIncome: order.realIncome,
        archiveOutcome: OrderArchiveOutcome.successful,
        clearSettlementNodeId: true,
        clearCustomRefundAmount: true,
        isArchived: true,
        isPinned: false,
      );
    }
    notifyListeners();
  }

  void archiveManyAsTerminatedAtCurrentNode(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    final now = DateTime.now();
    for (var i = 0; i < _orders.length; i++) {
      final order = _orders[i];
      if (!idSet.contains(order.id) || order.isArchived) continue;

      final validNodeIds = <String>{
        notStartedNodeId,
        for (final node in order.nodePresetSnapshot.nodes) node.id,
      };
      final settlementNodeId = validNodeIds.contains(order.currentNodeId)
          ? order.currentNodeId
          : notStartedNodeId;
      final settlementNode = settlementNodeId == notStartedNodeId
          ? notStartedNode
          : order.nodePresetSnapshot.nodeById(settlementNodeId);

      _orders[i] = order.copyWith(
        currentNodeId: settlementNodeId,
        currentNodeProgress: 0,
        completedAt: now,
        settledAt: now,
        settledIncome:
            order.incomeAtProgress(settlementNode.progressPercent),
        archiveOutcome: OrderArchiveOutcome.terminated,
        settlementNodeId: settlementNodeId,
        clearCustomRefundAmount: true,
        isArchived: true,
        isPinned: false,
      );
    }
    notifyListeners();
  }

  void archiveAsTerminated(String id, String settlementNodeId) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    final validNodeIds = <String>{
      notStartedNodeId,
      for (final node in order.nodePresetSnapshot.nodes) node.id,
    };
    if (!validNodeIds.contains(settlementNodeId)) return;

    final settlementNode = settlementNodeId == notStartedNodeId
        ? notStartedNode
        : order.nodePresetSnapshot.nodeById(settlementNodeId);

    _orders[index] = order.copyWith(
      currentNodeId: settlementNodeId,
      currentNodeProgress: 0,
      completedAt: DateTime.now(),
      settledAt: DateTime.now(),
      settledIncome: order.incomeAtProgress(settlementNode.progressPercent),
      archiveOutcome: OrderArchiveOutcome.terminated,
      settlementNodeId: settlementNodeId,
      clearCustomRefundAmount: true,
      isArchived: true,
      isPinned: false,
    );
    notifyListeners();
  }

  void archiveAsTerminatedWithCustomRefund(
    String id,
    double refundAmount,
  ) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    final normalizedRefund = refundAmount < 0 ? 0.0 : refundAmount;

    _orders[index] = order.copyWith(
      currentNodeProgress: 0,
      completedAt: DateTime.now(),
      settledAt: DateTime.now(),
      settledIncome: order.realIncome - normalizedRefund,
      archiveOutcome: OrderArchiveOutcome.terminated,
      clearSettlementNodeId: true,
      customRefundAmount: normalizedRefund,
      isArchived: true,
      isPinned: false,
    );
    notifyListeners();
  }

  void restoreArchivedOrder(String id) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    _orders[index] = order.copyWith(
      clearCompletedAt:
          order.archiveOutcome == OrderArchiveOutcome.terminated,
      clearSettledAt: true,
      clearSettledIncome: true,
      clearArchiveOutcome: true,
      clearSettlementNodeId: true,
      clearCustomRefundAmount: true,
      isArchived: false,
    );
    notifyListeners();
  }

  void setPinned(String id, bool pinned) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    _orders[index] = _orders[index].copyWith(isPinned: pinned);
    notifyListeners();
  }

  void adjustCurrentNodeProgress(String id, int delta) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    if (order.isArchived ||
        order.isCompleted ||
        order.currentNodeId == notStartedNodeId) {
      return;
    }

    final next = (order.currentNodeProgress + delta).clamp(0, 100).toInt();
    if (next == order.currentNodeProgress) return;

    _orders[index] = order.copyWith(currentNodeProgress: next);
    notifyListeners();
  }

  void advanceOrder(String id) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return;

    final order = _orders[index];
    if (order.isCompleted) return;

    final nodes = order.nodePresetSnapshot.nodes;
    if (nodes.isEmpty) return;

    if (order.currentNodeId == notStartedNodeId) {
      _orders[index] = order.copyWith(
        currentNodeId: nodes.first.id,
        currentNodeProgress: 0,
      );
      notifyListeners();
      return;
    }

    final currentIndex = nodes.indexWhere(
      (node) => node.id == order.currentNodeId,
    );

    if (currentIndex == -1) {
      _orders[index] = order.copyWith(
        currentNodeId: nodes.first.id,
        currentNodeProgress: 0,
      );
    } else if (currentIndex < nodes.length - 1) {
      _orders[index] = order.copyWith(
        currentNodeId: nodes[currentIndex + 1].id,
        currentNodeProgress: 0,
      );
    } else {
      _orders[index] = order.copyWith(
        currentNodeProgress: 0,
        completedAt: DateTime.now(),
        clearSettledIncome: true,
      );
    }

    notifyListeners();
  }
}
