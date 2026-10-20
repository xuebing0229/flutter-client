import 'package:flutter/foundation.dart';

import 'sync_models.dart';

class SyncConflictView {
  const SyncConflictView({
    required this.kind,
    required this.recordId,
  });

  final SyncEntityKind kind;
  final String recordId;
}

String syncFieldLabel(String field) => field;

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator.web({required this.accountId});

  final String accountId;

  bool get initialized => true;
  bool get syncBusy => false;
  bool get syncPaused => false;
  int get conflictCount => 0;
  String? get lastError => null;
  DateTime? get lastSuccessfulSyncAt => null;

  List<SyncConflictView> get conflicts => const <SyncConflictView>[];
  Set<String> get conflictedOrderIds => const <String>{};
  Set<String> get conflictedProductIds => const <String>{};

  Future<void> flushNow() async {}
  void notifySettingsChanged() {}
}
