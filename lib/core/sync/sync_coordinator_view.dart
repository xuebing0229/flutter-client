import 'package:flutter/foundation.dart';

abstract interface class SyncCoordinatorView implements Listenable {
  Set<String> get conflictedOrderIds;
  Set<String> get conflictedProductIds;

  Future<void> flushNow();
}
