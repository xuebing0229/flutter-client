import 'package:flutter/foundation.dart';

abstract class SyncUiCoordinator implements Listenable {
  Set<String> get conflictedOrderIds;
  Set<String> get conflictedProductIds;
  Future<void> flushNow();
}

class EmptySyncUiCoordinator extends ChangeNotifier
    implements SyncUiCoordinator {
  @override
  Set<String> get conflictedOrderIds => const <String>{};

  @override
  Set<String> get conflictedProductIds => const <String>{};

  @override
  Future<void> flushNow() async {}
}
