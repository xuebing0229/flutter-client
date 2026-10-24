import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/finished_product.dart';

class ProductStore extends ChangeNotifier {
  final List<FinishedProduct> _products = <FinishedProduct>[];

  UnmodifiableListView<FinishedProduct> get products =>
      UnmodifiableListView(_products);

  void _sortDefaultOrder() {
    _products.sort((left, right) {
      final byOrder = right.effectiveDefaultOrder.compareTo(
        left.effectiveDefaultOrder,
      );
      if (byOrder != 0) return byOrder;
      return right.id.compareTo(left.id);
    });
  }

  bool contains(String id) {
    return _products.any((product) => product.id == id);
  }

  FinishedProduct byId(String id) {
    return _products.firstWhere((product) => product.id == id);
  }

  void replaceAll(Iterable<FinishedProduct> products) {
    _products
      ..clear()
      ..addAll(products);
    _sortDefaultOrder();
    notifyListeners();
  }

  void addProduct(FinishedProduct product) {
    _products.add(product);
    _sortDefaultOrder();
    notifyListeners();
  }

  void updateProduct(FinishedProduct updated) {
    final index = _products.indexWhere((product) => product.id == updated.id);
    if (index == -1) return;

    _products[index] = updated;
    notifyListeners();
  }

  void markSold(String id, {DateTime? soldAt, String? clientName}) {
    final index = _products.indexWhere((product) => product.id == id);
    if (index == -1) return;

    final product = _products[index];
    if (product.isArchived) return;
    if (product.saleType == ProductSaleType.single && product.isSold) {
      return;
    }

    final nextSoldCount = product.saleType == ProductSaleType.single
        ? 1
        : product.soldCount + 1;

    final timestamp = soldAt ?? DateTime.now();
    final normalizedClient = clientName?.trim() ?? '';
    final nextSaleClientNames = <String, String>{
      ...product.saleClientNames,
    };
    if (normalizedClient.isNotEmpty) {
      nextSaleClientNames[timestamp.toUtc().toIso8601String()] =
          normalizedClient;
    }

    _products[index] = product.copyWith(
      soldCount: nextSoldCount,
      saleRecords: [
        ...product.saleRecords,
        timestamp,
      ],
      saleClientNames: nextSaleClientNames,
    );
    notifyListeners();
  }

  void setArchived(String id, bool archived) {
    final index = _products.indexWhere((product) => product.id == id);
    if (index == -1) return;

    final product = _products[index];
    if (product.isArchived == archived) return;
    _products[index] = product.copyWith(
      archivedAt: archived ? DateTime.now() : null,
      clearArchivedAt: !archived,
      isArchived: archived,
      isPinned: archived ? false : product.isPinned,
    );
    notifyListeners();
  }

  void setArchivedMany(Iterable<String> ids, bool archived) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    final archivedAt = archived ? DateTime.now() : null;
    var changed = false;
    for (var i = 0; i < _products.length; i++) {
      if (!idSet.contains(_products[i].id) ||
          _products[i].isArchived == archived) {
        continue;
      }
      _products[i] = _products[i].copyWith(
        archivedAt: archivedAt,
        clearArchivedAt: !archived,
        isArchived: archived,
        isPinned: archived ? false : _products[i].isPinned,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setPinned(String id, bool pinned) {
    final index = _products.indexWhere((product) => product.id == id);
    if (index == -1) return;

    _products[index] = _products[index].copyWith(isPinned: pinned);
    notifyListeners();
  }

  void deleteProduct(String id) {
    _products.removeWhere((product) => product.id == id);
    notifyListeners();
  }

  void deleteProducts(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _products.removeWhere((product) => idSet.contains(product.id));
    notifyListeners();
  }
}
