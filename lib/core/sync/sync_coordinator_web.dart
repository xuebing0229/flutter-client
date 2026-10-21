import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/state/focus_store.dart';
import '../../features/orders/data/node_presets.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/domain/finished_product.dart';
import '../../features/products/state/product_store.dart';
import 'sync_entity_codec.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';
import 'sync_coordinator_view.dart';
import '../web/web_platform_bridge.dart';

typedef WebSyncSettingsCapture = Map<String, dynamic> Function();
typedef WebSyncSettingsApply =
    Future<void> Function(Map<String, dynamic> settings);

class SyncConflictView {
  const SyncConflictView({
    required this.kind,
    required this.recordId,
    required this.conflict,
  });

  final SyncEntityKind kind;
  final String recordId;
  final SyncConflict conflict;
}

String syncFieldLabel(String field) => field;

/// Browser-side CRDT coordinator.
///
/// It uses the same SyncRecord/SyncMergeEngine format as Android and Windows,
/// but persists the record graph in browser storage instead of a Syncthing
/// directory. A transport can exchange the portable records without changing
/// merge semantics.
class SyncCoordinator extends ChangeNotifier implements SyncCoordinatorView {
  SyncCoordinator.web({
    required this.accountId,
    required this.deviceId,
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.focusStore,
    required this.captureSettings,
    required this.applySettings,
    SyncMergeEngine? mergeEngine,
  }) : _mergeEngine = mergeEngine ?? SyncMergeEngine();

  static const String settingsRecordId = 'app';

  final String accountId;
  final String deviceId;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final FocusStore focusStore;
  final WebSyncSettingsCapture captureSettings;
  final WebSyncSettingsApply applySettings;
  final SyncMergeEngine _mergeEngine;

  final Map<SyncEntityKind, Map<String, SyncRecord>> _records = {
    for (final kind in SyncEntityKind.values) kind: <String, SyncRecord>{},
  };
  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> _lastEntityValues = {
    for (final kind in SyncEntityKind.values)
      kind: <String, Map<String, dynamic>>{},
  };

  List<Map<String, dynamic>>? _pendingRestore;
  List<SyncConflictView> _conflicts = const <SyncConflictView>[];
  Timer? _changeDebounce;
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  bool _applyingRemote = false;
  bool _syncBusy = false;
  final bool _syncPaused = false;
  String? _lastError;
  DateTime? _lastSuccessfulSyncAt;

  String get _storageKey =>
      'adventurers-guild.web.sync-records.v1.$accountId';

  bool get initialized => _initialized;
  bool get syncBusy => _syncBusy;
  bool get syncPaused => _syncPaused;
  int get conflictCount => _conflicts.length;
  String? get lastError => _lastError;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  List<SyncConflictView> get conflicts =>
      List<SyncConflictView>.unmodifiable(_conflicts);

  Set<String> get conflictedOrderIds => <String>{
    for (final item in _conflicts)
      if (item.kind == SyncEntityKind.order) item.recordId,
  };

  Set<String> get conflictedProductIds => <String>{
    for (final item in _conflicts)
      if (item.kind == SyncEntityKind.product) item.recordId,
  };

  List<Map<String, dynamic>> get portableRecordsSnapshot {
    final result = <Map<String, dynamic>>[];
    for (final kind in SyncEntityKind.values) {
      final records = _records[kind]!;
      final ids = records.keys.toList()..sort();
      for (final id in ids) {
        result.add(Map<String, dynamic>.from(records[id]!.toJson()));
      }
    }
    return result;
  }

  void restorePortableRecords(Iterable<Map<String, dynamic>> records) {
    if (_initialized || _disposed) return;
    _pendingRestore = <Map<String, dynamic>>[
      for (final record in records) Map<String, dynamic>.from(record),
    ];
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;

    try {
      _loadStoredRecords();
      final pending = _pendingRestore;
      if (pending != null) {
        _mergeDecodedRecords(pending);
      }

      final current = _captureEntities();
      for (final kind in SyncEntityKind.values) {
        final records = _records[kind]!;
        for (final entry in current[kind]!.entries) {
          records.putIfAbsent(
            entry.key,
            () => SyncRecord.bootstrap(
              kind: kind,
              id: entry.key,
              values: entry.value,
              deviceId: deviceId,
            ).copyWith(accountId: accountId),
          );
        }
      }

      _initialized = true;
      await _applyAllRecords();
      _lastEntityValues = _captureEntities();
      _rebuildConflicts();
      _persistRecords();

      orderStore.addListener(_onLocalChanged);
      productStore.addListener(_onLocalChanged);
      nodePresetStore.addListener(_onLocalChanged);
      focusStore.addListener(_onLocalChanged);
      _lastError = null;
    } catch (error) {
      _lastError = '网页同步历史初始化失败：$error';
    }
    if (!_disposed) notifyListeners();
  }

  void _loadStoredRecords() {
    final source = webStorageGet(_storageKey);
    if (source == null || source.trim().isEmpty) return;
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['schema'] != 1) return;
    final list = decoded['records'];
    if (list is! List) return;
    _mergeDecodedRecords(
      <Map<String, dynamic>>[
        for (final item in list)
          if (item is Map)
            item.map((key, value) => MapEntry(key.toString(), value)),
      ],
    );
  }

  void _mergeDecodedRecords(Iterable<Map<String, dynamic>> rawRecords) {
    for (final raw in rawRecords) {
      final incoming = SyncRecord.decode(jsonEncode(raw));
      if (incoming.accountId != null && incoming.accountId != accountId) {
        throw const FormatException('同步记录属于另一个账号');
      }
      if (incoming.fields['id']?.value != incoming.id) {
        throw const FormatException('同步记录身份不一致');
      }
      final bound = incoming.copyWith(accountId: accountId);
      final current = _records[bound.kind]![bound.id];
      _records[bound.kind]![bound.id] =
          current == null ? bound : _mergeEngine.merge(current, bound);
    }
  }

  void _persistRecords() {
    if (_disposed) return;
    webStorageSet(
      _storageKey,
      jsonEncode(<String, dynamic>{
        'schema': 1,
        'records': portableRecordsSnapshot,
      }),
    );
  }

  void _onLocalChanged() {
    if (!_initialized || _disposed || _applyingRemote) return;
    _changeDebounce?.cancel();
    _changeDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(flushNow()),
    );
  }

  void notifySettingsChanged() => _onLocalChanged();

  Future<void> flushNow() async {
    if (!_initialized || _disposed || _syncPaused) return;
    _changeDebounce?.cancel();
    await _enqueue(_flushLocalChanges);
  }

  Future<List<Map<String, dynamic>>> exportPeerRecords() async {
    await flushNow();
    return portableRecordsSnapshot;
  }

  /// Replaces browser sync history after an explicit full-backup restore.
  ///
  /// Old backups may not contain CRDT history. In that case the newly restored
  /// workspace is bootstrapped as the fresh baseline instead of letting stale
  /// browser records overwrite it on the next online sync.
  Future<void> replacePortableRecordsForCurrentWorkspace(
    List<Map<String, dynamic>>? incoming,
  ) async {
    if (!_initialized || _disposed) return;
    await _enqueue(() async {
      for (final kind in SyncEntityKind.values) {
        _records[kind]!.clear();
      }

      if (incoming != null) {
        _mergeDecodedRecords(incoming);
      }

      final current = _captureEntities();
      for (final kind in SyncEntityKind.values) {
        final records = _records[kind]!;
        for (final entry in current[kind]!.entries) {
          records.putIfAbsent(
            entry.key,
            () => SyncRecord.bootstrap(
              kind: kind,
              id: entry.key,
              values: entry.value,
              deviceId: deviceId,
            ).copyWith(accountId: accountId),
          );
        }
      }

      _lastEntityValues = current;
      _rebuildConflicts();
      _persistRecords();
      _lastSuccessfulSyncAt = DateTime.now();
      _lastError = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> mergePeerRecords(
    List<Map<String, dynamic>> incoming,
  ) async {
    if (!_initialized || _disposed) return;
    await _enqueue(() async {
      await _flushLocalChanges();
      _mergeDecodedRecords(incoming);
      _applyingRemote = true;
      try {
        await _applyAllRecords();
      } finally {
        _applyingRemote = false;
      }
      _lastEntityValues = _captureEntities();
      _rebuildConflicts();
      _persistRecords();
      _lastSuccessfulSyncAt = DateTime.now();
      _lastError = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _flushLocalChanges() async {
    if (_disposed || _applyingRemote) return;
    final current = _captureEntities();
    var changed = false;

    for (final kind in SyncEntityKind.values) {
      final previousValues = _lastEntityValues[kind]!;
      final currentValues = current[kind]!;
      final ids = <String>{...previousValues.keys, ...currentValues.keys};

      for (final id in ids) {
        final before = previousValues[id];
        final after = currentValues[id];
        if (syncJsonEquals(before, after)) continue;

        final existing = _records[kind]![id];
        SyncRecord next;
        if (after == null) {
          if (existing == null) {
            if (before == null) continue;
            next = SyncRecord.bootstrap(
              kind: kind,
              id: id,
              values: before,
              deviceId: deviceId,
            ).copyWith(accountId: accountId);
          } else {
            next = existing;
          }
          next = _mergeEngine.markDeleted(next, deviceId: deviceId);
        } else if (existing == null) {
          next = SyncRecord.bootstrap(
            kind: kind,
            id: id,
            values: after,
            deviceId: deviceId,
          ).copyWith(accountId: accountId);
        } else {
          next = _mergeEngine.applyLocalSnapshot(
            record: existing,
            previousValues: before ?? after,
            nextValues: after,
            deviceId: deviceId,
          );
        }
        _records[kind]![id] = next.copyWith(accountId: accountId);
        changed = true;
      }
    }

    _lastEntityValues = current;
    if (changed) {
      _rebuildConflicts();
      _persistRecords();
      _lastSuccessfulSyncAt = DateTime.now();
      _lastError = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _applyAllRecords() async {
    _applyOrderRecords(_records[SyncEntityKind.order]!);
    _applyProductRecords(_records[SyncEntityKind.product]!);
    _applyPresetRecords(_records[SyncEntityKind.nodePreset]!);
    _applyFocusRecords(_records[SyncEntityKind.focusSession]!);
    await _applySettingsRecords(_records[SyncEntityKind.settings]!);
  }

  void _applyOrderRecords(Map<String, SyncRecord> records) {
    final result = <QueueOrder>[];
    final existingIds = <String>{};

    for (final existing in orderStore.orders) {
      existingIds.add(existing.id);
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = _mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.orderToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.orderFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }

    for (final record in records.values) {
      if (existingIds.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.orderFromFields(fields));
      } catch (_) {}
    }

    if (!_sameOrders(orderStore.orders, result)) {
      orderStore.replaceAll(result);
    }
  }

  void _applyProductRecords(Map<String, SyncRecord> records) {
    final result = <FinishedProduct>[];
    final existingIds = <String>{};

    for (final existing in productStore.products) {
      existingIds.add(existing.id);
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = _mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.productToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.productFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }

    for (final record in records.values) {
      if (existingIds.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.productFromFields(fields));
      } catch (_) {}
    }

    if (!_sameProducts(productStore.products, result)) {
      productStore.replaceAll(result);
    }
  }

  void _applyPresetRecords(Map<String, SyncRecord> records) {
    final result = <NodePreset>[];
    final existingIds = <String>{};

    for (final existing in nodePresetStore.presets) {
      existingIds.add(existing.id);
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = _mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.nodePresetToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.nodePresetFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }

    for (final record in records.values) {
      if (existingIds.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.nodePresetFromFields(fields));
      } catch (_) {}
    }

    if (!syncJsonEquals(_presetFields(nodePresetStore.presets), _presetFields(result))) {
      nodePresetStore.replaceAll(result);
    }
  }

  void _applyFocusRecords(Map<String, SyncRecord> records) {
    final result = <FocusSession>[];
    final existingIds = <String>{};

    for (final existing in focusStore.sessions) {
      existingIds.add(existing.id);
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = _mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.focusSessionToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.focusSessionFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }

    for (final record in records.values) {
      if (existingIds.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.focusSessionFromFields(fields));
      } catch (_) {}
    }

    if (!syncJsonEquals(_focusFields(focusStore.sessions), _focusFields(result))) {
      focusStore.replaceAll(result);
    }
  }

  Future<void> _applySettingsRecords(Map<String, SyncRecord> records) async {
    final record = records[settingsRecordId];
    if (record == null) return;
    final local = captureSettings();
    final fields = _mergeEngine.materializeKeepingLocalConflicts(record, local);
    if (fields == null || syncJsonEquals(fields, local)) return;
    await applySettings(fields);
  }

  void _rebuildConflicts() {
    final next = <SyncConflictView>[];
    for (final kind in SyncEntityKind.values) {
      for (final record in _records[kind]!.values) {
        for (final conflict in record.conflicts.values) {
          next.add(
            SyncConflictView(
              kind: kind,
              recordId: record.id,
              conflict: conflict,
            ),
          );
        }
      }
    }
    _conflicts = List<SyncConflictView>.unmodifiable(next);
  }

  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> _captureEntities() {
    return <SyncEntityKind, Map<String, Map<String, dynamic>>>{
      SyncEntityKind.order: <String, Map<String, dynamic>>{
        for (final order in orderStore.orders)
          order.id: SyncEntityCodec.orderToFields(order),
      },
      SyncEntityKind.product: <String, Map<String, dynamic>>{
        for (final product in productStore.products)
          product.id: SyncEntityCodec.productToFields(product),
      },
      SyncEntityKind.nodePreset: <String, Map<String, dynamic>>{
        for (final preset in nodePresetStore.presets)
          preset.id: SyncEntityCodec.nodePresetToFields(preset),
      },
      SyncEntityKind.focusSession: <String, Map<String, dynamic>>{
        for (final session in focusStore.sessions)
          session.id: SyncEntityCodec.focusSessionToFields(session),
      },
      SyncEntityKind.settings: <String, Map<String, dynamic>>{
        settingsRecordId: captureSettings(),
      },
    };
  }

  List<Map<String, dynamic>> _presetFields(Iterable<NodePreset> values) => [
    for (final item in values) SyncEntityCodec.nodePresetToFields(item),
  ];

  List<Map<String, dynamic>> _focusFields(Iterable<FocusSession> values) => [
    for (final item in values) SyncEntityCodec.focusSessionToFields(item),
  ];

  bool _sameOrders(Iterable<QueueOrder> left, Iterable<QueueOrder> right) =>
      syncJsonEquals(
        [for (final item in left) SyncEntityCodec.orderToFields(item)],
        [for (final item in right) SyncEntityCodec.orderToFields(item)],
      );

  bool _sameProducts(
    Iterable<FinishedProduct> left,
    Iterable<FinishedProduct> right,
  ) =>
      syncJsonEquals(
        [for (final item in left) SyncEntityCodec.productToFields(item)],
        [for (final item in right) SyncEntityCodec.productToFields(item)],
      );

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then<void>((_) async {
      if (_disposed) {
        completer.completeError(StateError('同步协调器已释放'));
        return;
      }
      _syncBusy = true;
      notifyListeners();
      try {
        completer.complete(await action());
      } catch (error, stack) {
        _lastError = '网页同步失败：$error';
        completer.completeError(error, stack);
      } finally {
        _syncBusy = false;
        if (!_disposed) notifyListeners();
      }
    }, onError: (_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changeDebounce?.cancel();
    orderStore.removeListener(_onLocalChanged);
    productStore.removeListener(_onLocalChanged);
    nodePresetStore.removeListener(_onLocalChanged);
    focusStore.removeListener(_onLocalChanged);
    super.dispose();
  }
}
