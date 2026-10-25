import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../account/account_models.dart';
import '../account/account_store.dart';
import '../portability/app_backup_data.dart';
import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/state/focus_store.dart';
import '../../features/orders/data/node_presets.dart';
import '../../features/orders/data/order_reference_image_store.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/domain/finished_product.dart';
import '../../features/products/state/product_store.dart';
import 'account_sync_record_store.dart';
import 'embedded_syncthing_bridge.dart';
import 'portable_sync_workspace_validator.dart';
import 'sync_entity_codec.dart';
import 'sync_gc_ack_store.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';
import 'sync_record_store.dart';
import 'sync_reference_image_gc.dart';

typedef SyncSettingsCapture = Map<String, dynamic> Function();
typedef SyncSettingsApply = Future<void> Function(Map<String, dynamic> settings);

@visibleForTesting
Future<void> runWorkspaceRestoreTransaction({
  required Future<void> Function() applyWorkspace,
  required Future<void> Function() commitSyncHistory,
  required Future<void> Function() rollbackWorkspace,
}) async {
  try {
    await applyWorkspace();
    await commitSyncHistory();
  } catch (error, stackTrace) {
    await rollbackWorkspace();
    Error.throwWithStackTrace(error, stackTrace);
  }
}

@visibleForTesting
bool shouldRetainRevokedTransportShare({
  required String transportId,
  required Set<String> activeTransportIds,
  required Set<String> reauthorizedTransportIds,
}) {
  final id = transportId.trim();
  return id.isNotEmpty &&
      (activeTransportIds.contains(id) ||
          reauthorizedTransportIds.contains(id));
}

class PortableWorkspaceSnapshot {
  const PortableWorkspaceSnapshot({
    required this.exportedAt,
    required this.orders,
    required this.products,
    required this.nodePresets,
    required this.focusSessions,
    required this.settings,
    required this.accountSyncState,
    required this.syncRecords,
  });

  final DateTime exportedAt;
  final List<QueueOrder> orders;
  final List<FinishedProduct> products;
  final List<NodePreset> nodePresets;
  final List<FocusSession> focusSessions;
  final Map<String, dynamic> settings;
  final AccountSyncState? accountSyncState;
  final List<Map<String, dynamic>> syncRecords;
}

class SyncConflictView {
  const SyncConflictView({
    required this.kind,
    required this.recordId,
    required this.conflict,
  });

  final SyncEntityKind kind;
  final String recordId;
  final SyncConflict conflict;

  String get entityLabel => switch (kind) {
    SyncEntityKind.order => '排单',
    SyncEntityKind.product => '成品',
    SyncEntityKind.nodePreset => '节点预设',
    SyncEntityKind.focusSession => '专注记录',
    SyncEntityKind.settings => '界面设置',
  };

  String get fieldLabel => syncFieldLabel(conflict.field);
}

String syncFieldLabel(String field) {
  return switch (field) {
    'title' => '名称',
    'clientName' => '单主',
    'platform' => '平台',
    'deadline' => '截稿日期',
    'nodePresetId' => '节点预设',
    'nodePresetSnapshot' => '节点预设快照',
    'currentNodeId' => '当前节点',
    'currentNodeProgress' => '节点小进度',
    'price' => '稿费',
    'feeEnabled' => '手续费',
    'huajiaLoveLevel' => '真爱永恒',
    'onlinePercent' => '线上比例',
    'supplementAmount' => '补款基准',
    'supplementFeeEnabled' => '补款手续费',
    'deductionAmount' => '减款基准',
    'deductionFeeEnabled' => '减款手续费',
    'description' => '备注',
    'tags' => '自定义标签',
    'referenceImages' => '参考图',
    'completedAt' => '交稿时间',
    'settledAt' => '结算时间',
    'settledIncome' => '结算收入',
    'archiveOutcome' => '归档结果',
    'settlementNodeId' => '结算节点',
    'customRefundAmount' => '退款金额',
    'isArchived' => '归档状态',
    'isPinned' => '置顶状态',
    'saleType' => '售卖方式',
    'soldCount' => '售出数量基准',
    'saleRecords' => '售出记录',
    'saleClientNames' => '售出单主',
    'archivedAt' => '归档时间',
    'themeMode' => '主题模式',
    'themePaletteId' => '主题色',
    'customThemePalettes' => '自定义主题色方案',
    'uiStyle' => 'UI风格',
    'uiTexture' => 'UI风格',
    'features' => '功能开关',
    'feature.clientInfo' => '显示单主信息',
    'feature.customTags' => '自定义标签开关',
    'feature.referenceImages' => '参考图开关',
    'feature.nodeProgress' => '节点小进度',
    'feature.search' => '搜索',
    'feature.sorting' => '排序',
    'feature.viewSwitch' => '列表 / 卡片视图切换',
    'feature.products' => '成品功能开关',
    'feature.schedule' => '日程功能开关',
    'feature.statistics' => '统计功能开关',
    'feature.deadlineReminders' => '截稿提醒开关',
    'feature.abstractMode' => '抽象版开关',
    'feature.abstractEffects' => '抽象版表现',
    'orderCardView' => '排单卡片视图',
    'productCardView' => '成品卡片视图',
    'orderSortMode' => '排单排序',
    'productSortMode' => '成品排序',
    'desktopNavigationOpen' => '电脑导航栏状态',
    'name' => '预设名称',
    'nodes' => '节点内容',
    'startedAt' => '专注开始时间',
    'endedAt' => '专注结束时间',
    'orderId' => '专注排单',
    'orderTitleSnapshot' => '排单标题快照',
    SyncRecord.deletedField => '删除状态',
    _ => field,
  };
}

class SyncCoordinator extends ChangeNotifier {
  static const settingsRecordId = 'app';
  static const _transportReauthorizationLifetime = Duration(minutes: 30);

  SyncCoordinator({
    required this.accountId,
    required this.deviceId,
    required this.deviceName,
    required this.accountStore,
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    FocusStore? focusStore,
    required this.captureSettings,
    required this.applySettings,
    SyncMergeEngine? mergeEngine,
    SyncRecordStore? recordStore,
    AccountSyncRecordStore? accountSyncStore,
    SyncGcAckStore? gcAckStore,
    EmbeddedSyncthingBridge bridge = const EmbeddedSyncthingBridge(),
  }) : focusStore = focusStore ?? FocusStore(),
       _mergeEngine = mergeEngine ?? SyncMergeEngine(),
       _recordStore = recordStore ?? SyncRecordStore(),
       _referenceImageStore = OrderReferenceImageStore(
         syncRecordStore: recordStore,
       ),
       _accountSyncStore = accountSyncStore ?? AccountSyncRecordStore(),
       _gcAckStore = gcAckStore ?? SyncGcAckStore(recordStore: recordStore),
       _bridge = bridge;

  final String accountId;
  String deviceId;
  final String deviceName;
  final AccountStore accountStore;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final FocusStore focusStore;
  final SyncSettingsCapture captureSettings;
  final SyncSettingsApply applySettings;
  final SyncMergeEngine _mergeEngine;
  final SyncRecordStore _recordStore;
  final OrderReferenceImageStore _referenceImageStore;
  final AccountSyncRecordStore _accountSyncStore;
  final SyncGcAckStore _gcAckStore;
  final EmbeddedSyncthingBridge _bridge;
  final Lock _pauseLock = Lock();

  bool _initialized = false;
  bool _applyingRemote = false;
  bool _applyingAccount = false;
  bool _disposed = false;
  bool _syncBusy = false;
  bool _transportPrepared = false;
  bool _syncPaused = false;
  bool _removingLocalAccount = false;
  bool _pollQueued = false;
  bool _foregroundTransportEnabled = true;
  bool _awaitingInitialRemoteWorkspace = false;
  Timer? _changeDebounce;
  Timer? _pollTimer;
  Future<void> _tail = Future<void>.value();

  // Every workspace entity, including UI settings, goes through the same
  // capture -> baseline -> merge -> apply pipeline.  Keep one baseline map so
  // a new entity cannot accidentally grow a second, special-case sync path.
  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> _lastEntityValues = {
    for (final kind in SyncEntityKind.values)
      kind: <String, Map<String, dynamic>>{},
  };
  List<SyncConflictView> _conflicts = const <SyncConflictView>[];
  EmbeddedSyncthingStatus _transportStatus = const EmbeddedSyncthingStatus(
    available: false,
    running: false,
  );
  DateTime? _lastSuccessfulSyncAt;
  String? _lastError;
  bool _hasRestoredSyncBaseline = false;
  final Map<SyncEntityKind, Map<String, SyncRecord>> _lastFlushedRecords = {
    for (final kind in SyncEntityKind.values) kind: <String, SyncRecord>{},
  };

  bool get initialized => _initialized;
  bool get syncBusy => _syncBusy;
  bool get syncPaused => _syncPaused;
  bool get transportPrepared => _transportPrepared;
  EmbeddedSyncthingStatus get transportStatus => _transportStatus;
  List<SyncConflictView> get conflicts =>
      List<SyncConflictView>.unmodifiable(_conflicts);
  int get conflictCount => _conflicts.length;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastError => _lastError;

  Map<String, dynamic> get syncBaselineSettings {
    return <String, dynamic>{
      for (final kind in SyncEntityKind.values)
        kind.directoryName: [
          for (final id in (_lastFlushedRecords[kind]!.keys.toList()..sort()))
            _lastFlushedRecords[kind]![id]!.toJson(),
        ],
    };
  }

  List<Map<String, dynamic>> _portableRecordsFromCurrentBaseline() {
    final result = <Map<String, dynamic>>[];
    for (final kind in SyncEntityKind.values) {
      final records = _lastFlushedRecords[kind]!;
      final ids = records.keys.toList()..sort();
      for (final id in ids) {
        result.add(Map<String, dynamic>.from(records[id]!.toJson()));
      }
    }
    return result;
  }

  void restoreSyncBaseline(Object? raw) {
    if (_initialized || _disposed || raw is! Map) return;

    var baselinePresent = false;
    for (final kind in SyncEntityKind.values) {
      if (raw.containsKey(kind.directoryName)) baselinePresent = true;
      final items = raw[kind.directoryName];
      if (items is! List) continue;

      final records = _lastFlushedRecords[kind]!;
      for (final item in items) {
        if (item is! Map) continue;
        try {
          final record = SyncRecord.decode(jsonEncode(item));
          if (record.kind != kind) continue;
          if (record.accountId != null && record.accountId != accountId) {
            continue;
          }
          records[record.id] = record.copyWith(accountId: accountId);
        } catch (_) {
          // A malformed optional baseline must not block the workspace.
        }
      }
    }
    _hasRestoredSyncBaseline = baselinePresent;
  }

  /// Call this when a locally selectable workspace setting changes.
  void notifySettingsChanged() {
    if (_disposed || !_initialized || _applyingRemote) return;
    _onLocalChanged();
  }

  Set<String> get conflictedOrderIds => <String>{
    for (final item in _conflicts)
      if (item.kind == SyncEntityKind.order) item.recordId,
  };

  Set<String> get conflictedProductIds => <String>{
    for (final item in _conflicts)
      if (item.kind == SyncEntityKind.product) item.recordId,
  };

  String? get pairingPayload {
    final syncthingDeviceId = _transportStatus.deviceId;
    if (syncthingDeviceId == null || syncthingDeviceId.isEmpty) return null;
    final currentDevice = accountStore.syncSnapshot?.devices[deviceId];
    if (currentDevice == null) return null;
    return _bridge.pairingPayload(
      accountId: accountId,
      deviceId: syncthingDeviceId,
      deviceName: currentDevice.name,
      appDeviceId: deviceId,
      devicePlatform: currentDevice.platform,
    );
  }

  Future<void> flushNow() async {
    if (_disposed || !_initialized) return;
    _changeDebounce?.cancel();
    await _enqueue(() async {
      await _flushLocalChanges();
    });
  }

  Future<List<Map<String, dynamic>>> exportPortableRecords() async {
    return (await exportPortableWorkspace()).syncRecords;
  }

  Future<PortableWorkspaceSnapshot> exportPortableWorkspace() {
    if (_disposed || !_initialized) {
      throw StateError('同步协调器尚未准备好。');
    }

    _changeDebounce?.cancel();
    return _enqueue(() async {
      var pausedTransportForExport = false;
      try {
        // A complete backup must capture the workspace JSON and the synced
        // record history as one consistent point-in-time snapshot. Syncthing
        // writes the same directory independently of this Dart queue, so pause
        // only the transport folder for the few moments needed to capture it.
        // This does not change the user's persisted sync-pause setting.
        if (_transportPrepared && !_syncPaused) {
          await _bridge.setAccountFolderPaused(
            accountId: accountId,
            paused: true,
          );
          pausedTransportForExport = true;
          // Let any file operation already in flight finish before reading.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }

        var lastInstability = '同步历史与当前工作区不一致';
        for (var attempt = 0; attempt < 5; attempt++) {
          await _flushLocalChanges();

          // Export is also a safe repair point for older workspaces whose
          // portable history predates newer entity/settings fields.
          await _reconcileFromSyncDirectory(seedMissing: true);

          final state = accountStore.syncSnapshot;
          if (state == null ||
              state.accountId != accountId ||
              state.isRevoked(deviceId)) {
            throw StateError('当前设备已经不能导出这个账号的数据。');
          }

          final orderFields = _captureOrders();
          final productFields = _captureProducts();
          final presetFields = _capturePresets();
          final focusFields = _captureFocusSessions();
          final settings = captureSettings();
          final orders = <QueueOrder>[...orderStore.orders];
          final products = <FinishedProduct>[...productStore.products];
          final presets = <NodePreset>[
            for (final preset in nodePresetStore.presets) preset.snapshot(),
          ];
          final focusSessions = <FocusSession>[...focusStore.sessions];

          // Reconcile already produced a single merged/canonical record set.
          // Re-reading the directory here creates a second snapshot boundary
          // and can disagree with the workspace we just applied.
          final records = _portableRecordsFromCurrentBaseline();

          final storesUnchanged =
              syncJsonEquals(orderFields, _captureOrders()) &&
              syncJsonEquals(productFields, _captureProducts()) &&
              syncJsonEquals(presetFields, _capturePresets()) &&
              syncJsonEquals(focusFields, _captureFocusSessions()) &&
              syncJsonEquals(settings, captureSettings());
          if (!storesUnchanged) {
            lastInstability = '本地工作数据在导出期间持续变化';
            await Future<void>.delayed(const Duration(milliseconds: 40));
            continue;
          }

          if (!PortableSyncWorkspaceValidator.recordsMatchWorkspace(
            accountId: accountId,
            records: records,
            orders: orderFields,
            products: productFields,
            presets: presetFields,
            focusSessions: focusFields,
            settings: settings,
            mergeEngine: _mergeEngine,
          )) {
            lastInstability = '同步历史与当前工作区仍不一致';
            await Future<void>.delayed(const Duration(milliseconds: 40));
            continue;
          }

          final accountSnapshot = accountStore.syncSnapshot;
          if (accountSnapshot == null ||
              accountSnapshot.accountId != accountId ||
              accountSnapshot.isRevoked(deviceId)) {
            throw StateError('当前设备已经不能导出这个账号的数据。');
          }

          return PortableWorkspaceSnapshot(
            exportedAt: DateTime.now(),
            orders: orders,
            products: products,
            nodePresets: presets,
            focusSessions: focusSessions,
            settings: settings,
            accountSyncState: accountSnapshot,
            syncRecords: records,
          );
        }

        throw StateError('$lastInstability，已停止导出以避免生成不完整备份。');
      } finally {
        if (pausedTransportForExport) {
          try {
            await _bridge.setAccountFolderPaused(
              accountId: accountId,
              paused: false,
            );
            await _bridge.requestScan(accountId: accountId);
          } catch (error) {
            _lastError = '备份完成后恢复设备同步失败：$error';
            if (!_disposed) notifyListeners();
          }
        }
      }
    });
  }

  Future<void> restorePortableBackupBeforeInitialize(
    AppBackupData backup,
  ) async {
    if (_disposed || _initialized) {
      throw StateError('只能在同步协调器初始化前恢复同步历史。');
    }

    await _restorePortableBackup(backup: backup, applyWorkspace: null);
  }

  Future<void> restorePortableBackupForCurrentWorkspace({
    required AppBackupData backup,
    required Future<void> Function() applyWorkspace,
    Directory? assetSourceDirectory,
  }) {
    if (_disposed || !_initialized) {
      throw StateError('同步协调器尚未准备好，不能恢复同步历史。');
    }

    _changeDebounce?.cancel();
    return _enqueue(() async {
      var pausedTransportForRestore = false;
      try {
        // Replacing the portable sync directory while Syncthing is scanning it
        // can race with remote writes and is especially fragile on Windows,
        // where an active watcher may keep directory handles open. Pause only
        // the configured folder for the short restore transaction; this does
        // not change the user's persisted sync-pause preference.
        if (_transportPrepared && !_syncPaused) {
          await _bridge.setAccountFolderPaused(
            accountId: accountId,
            paused: true,
          );
          pausedTransportForRestore = true;
          // Let any scan/file operation already in flight leave the folder
          // before the directory swap begins.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }

        await _restorePortableBackup(
          backup: backup,
          applyWorkspace: applyWorkspace,
          assetSourceDirectory: assetSourceDirectory,
        );

        _lastEntityValues = _captureEntities();

        // Older complete backups can legitimately predate the settings entity.
        // Re-seed anything absent after applying the imported workspace so a
        // restore cannot silently leave UI settings outside the sync graph.
        await _reconcileFromSyncDirectory(seedMissing: true);
      } finally {
        if (pausedTransportForRestore) {
          try {
            await _bridge.setAccountFolderPaused(
              accountId: accountId,
              paused: false,
            );
            await _bridge.requestScan(accountId: accountId);
          } catch (error) {
            // The workspace restore itself has already succeeded or rolled
            // back. Keep that result authoritative and surface only the
            // transport recovery problem through normal sync diagnostics.
            _lastError = '备份恢复后恢复设备同步失败：$error';
            if (!_disposed) notifyListeners();
          }
        } else if (_transportPrepared && !_syncPaused) {
          try {
            await _bridge.requestScan(accountId: accountId);
          } catch (error) {
            _lastError = '备份恢复后触发设备同步失败：$error';
            if (!_disposed) notifyListeners();
          }
        }
      }
    });
  }

  Future<void> _restorePortableBackup({
    required AppBackupData backup,
    required Future<void> Function()? applyWorkspace,
    Directory? assetSourceDirectory,
  }) async {
    PortableSyncWorkspaceValidator.validateBackup(
      backup: backup,
      accountId: accountId,
    );
    final records = backup.syncRecords!;

    final requiredIds = <SyncEntityKind, Set<String>>{
      SyncEntityKind.order: <String>{
        for (final order in backup.orders) order.id,
      },
      SyncEntityKind.product: <String>{
        for (final product in backup.products) product.id,
      },
      SyncEntityKind.nodePreset: <String>{
        for (final preset in backup.nodePresets) preset.id,
      },
      SyncEntityKind.focusSession: <String>{
        for (final session in backup.focusSessions) session.id,
      },
    };

    if (applyWorkspace == null) {
      await _recordStore.replacePortableRecords(
        accountId: accountId,
        records: records,
        assetSourceDirectory: assetSourceDirectory,
        requiredIds: requiredIds,
      );
      return;
    }

    final previousOrders = <QueueOrder>[...orderStore.orders];
    final previousProducts = <FinishedProduct>[...productStore.products];
    final previousPresets = <NodePreset>[
      for (final preset in nodePresetStore.presets) preset.snapshot(),
    ];
    final previousFocusSessions = <FocusSession>[...focusStore.sessions];
    final previousSettings = Map<String, dynamic>.from(captureSettings());

    _applyingRemote = true;
    try {
      await runWorkspaceRestoreTransaction(
        applyWorkspace: applyWorkspace,
        commitSyncHistory: () => _recordStore.replacePortableRecords(
          accountId: accountId,
          records: records,
          assetSourceDirectory: assetSourceDirectory,
          requiredIds: requiredIds,
        ),
        rollbackWorkspace: () async {
          nodePresetStore.replaceAll(previousPresets);
          orderStore.replaceAll(previousOrders);
          productStore.replaceAll(previousProducts);
          focusStore.replaceAll(previousFocusSessions);
          await applySettings(previousSettings);
        },
      );
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> initialize({
    bool seedLocalWorkspace = true,
    bool seedLocalSettings = true,
  }) async {
    if (_initialized || _disposed) return;

    _awaitingInitialRemoteWorkspace = !seedLocalWorkspace;
    await _loadSyncPauseState();

    if (_hasRestoredSyncBaseline) {
      _lastEntityValues = <SyncEntityKind, Map<String, Map<String, dynamic>>>{
        for (final kind in SyncEntityKind.values)
          kind: _baselineValues(kind),
      };
      final settings = _lastEntityValues[SyncEntityKind.settings]!;
      settings.putIfAbsent(settingsRecordId, captureSettings);
    } else {
      _lastEntityValues = _captureEntities();
    }

    await _enqueue(() async {
      await _syncAccountState();
      await _reconcileFromSyncDirectory(
        seedMissing: true,
        seedSettings: seedLocalSettings,
      );
    });

    if (_disposed) return;
    accountStore.addListener(_onAccountChanged);
    orderStore.addListener(_onLocalChanged);
    productStore.addListener(_onLocalChanged);
    nodePresetStore.addListener(_onLocalChanged);
    focusStore.addListener(_onLocalChanged);
    _initialized = true;
    notifyListeners();

    final account = accountStore.syncSnapshot;
    final hasKnownRemoteTransportPeer =
        account?.activeDevices.any((device) {
          final remoteTransportId = device.syncTransportId?.trim();
          return device.id != deviceId &&
              remoteTransportId != null &&
              remoteTransportId.isNotEmpty;
        }) ??
        false;

    // A paired workspace must bring its transport back by itself. In
    // particular, do not rely only on the platform-local auto-start marker:
    // older installs or a previously stopped core can otherwise stay offline
    // until the user opens the sync page on that exact device.
    if (_syncPaused) {
      unawaited(_keepPreparedFolderPaused());
    } else {
      _enqueueBackground(() async {
        await _prepareTransport(force: hasKnownRemoteTransportPeer);
      });
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_disposed || _pollQueued) return;
      _pollQueued = true;
      unawaited(() async {
        try {
          await _enqueue<void>(() async {
            await _reconcileFromSyncDirectory(seedMissing: false);
            await _refreshTransportStatus();
            await _repairTransportIfNeeded();
          }, showBusy: false);
        } catch (_) {
          // Background polling reports through the coordinator state.
        } finally {
          _pollQueued = false;
        }
      }());
    });
  }

  void _onAccountChanged() {
    if (_applyingAccount) return;
    _onLocalChanged();
  }

  void _onLocalChanged() {
    if (!_initialized ||
        _applyingRemote ||
        _applyingAccount ||
        _removingLocalAccount ||
        _disposed) {
      return;
    }
    _changeDebounce?.cancel();
    _changeDebounce = Timer(const Duration(milliseconds: 220), () {
      if (_disposed) return;
      _enqueueBackground(() async {
        await _flushLocalChanges();
      });
    });
  }

  Future<void> activateTransport() {
    _foregroundTransportEnabled = true;
    return _enqueue(() async {
      if (_syncPaused) return;
      await _prepareTransport(force: true);
    });
  }

  Future<void> deactivateTransportForBackground() {
    _foregroundTransportEnabled = false;
    return _enqueue(() async {
      // A resume may be queued after this stop request but before its turn.
      // Never stop the newly foregrounded transport for a stale exit event.
      if (_syncPaused || _foregroundTransportEnabled) return;
      try {
        await _bridge.stop(accountId: accountId);
      } finally {
        _transportPrepared = false;
        _transportStatus = const EmbeddedSyncthingStatus(
          available: true,
          running: false,
        );
        if (!_disposed) notifyListeners();
      }
    }, showBusy: false);
  }

  Future<void> pauseTransport() {
    return _pauseLock.synchronized(() async {
      return _enqueue(() async {
        if (_syncPaused) return;

        if (_transportPrepared) {
          await _bridge.setAccountFolderPaused(
            accountId: accountId,
            paused: true,
          );
        }
        _transportPrepared = false;
        _syncPaused = true;
        await _persistSyncPauseState();
        await _refreshTransportStatus();
      });
    });
  }

  Future<void> resumeTransport() {
    return _pauseLock.synchronized(() async {
      return _enqueue(() async {
        if (!_syncPaused) {
          await _prepareTransport(force: true);
          return;
        }

        _syncPaused = false;
        await _persistSyncPauseState();
        await _prepareTransport(force: true);
      });
    });
  }

  Future<void> _keepPreparedFolderPaused() async {
    try {
      final status = await _bridge.status(accountId: accountId);
      if (status.running) {
        await _bridge.setAccountFolderPaused(
          accountId: accountId,
          paused: true,
        );
      }
      _transportStatus = status;
    } catch (error) {
      _lastError = '读取已暂停的同步状态失败：$error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> prepareForLocalAccountRemoval() {
    if (_disposed || _removingLocalAccount) return Future<void>.value();

    _removingLocalAccount = true;
    _changeDebounce?.cancel();

    return _enqueue(() async {
      try {
        await _bridge.removeAccountFolder(accountId: accountId);
        _transportPrepared = false;
        _pollTimer?.cancel();
      } catch (_) {
        _removingLocalAccount = false;
        rethrow;
      }
    });
  }

  Future<List<AccountDevice>> unacknowledgedRevokedDevices() async {
    final state = accountStore.syncSnapshot;
    if (state == null || state.accountId != accountId) {
      return const <AccountDevice>[];
    }

    final result = <AccountDevice>[];
    for (final entry in state.revocations.entries) {
      if (entry.key == deviceId) continue;
      final device = state.devices[entry.key];
      if (device == null) continue;
      final acknowledged = await _accountSyncStore.hasRevocationAck(
        accountId: accountId,
        deviceId: entry.key,
        revokedAt: entry.value.revokedAt,
      );
      if (!acknowledged) result.add(device);
    }
    result.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return result;
  }

  Future<void> forceFinalizeRevokedDevice(String appDeviceId) {
    return _enqueue(() async {
      final state = accountStore.syncSnapshot;
      if (state == null || state.accountId != accountId) {
        throw StateError('当前账号状态不可用。');
      }
      if (appDeviceId == deviceId) {
        throw const FormatException('不能强制清理当前设备。');
      }

      final revocation = state.revocations[appDeviceId];
      final device = state.devices[appDeviceId];
      if (revocation == null || device == null) {
        throw const FormatException('这台设备没有待完成的解绑记录。');
      }

      final alreadyAcknowledged = await _accountSyncStore.hasRevocationAck(
        accountId: accountId,
        deviceId: appDeviceId,
        revokedAt: revocation.revokedAt,
      );
      if (!alreadyAcknowledged) {
        // The user explicitly confirmed that this installation has already
        // been uninstalled/lost and can never come back to acknowledge its
        // tombstone. Finalize that exact revocation on its behalf so every
        // surviving peer can stop sharing to the dead transport.
        await _accountSyncStore.writeRevocationAck(
          accountId: accountId,
          deviceId: appDeviceId,
          revokedAt: revocation.revokedAt,
        );
      }

      if (!_transportPrepared) {
        await _prepareTransport(force: true);
      }

      final transportId = device.syncTransportId?.trim();
      if (_transportPrepared) {
        if (transportId != null && transportId.isNotEmpty) {
          await _clearTransportReauthorization(transportId);
          try {
            await _bridge.unshareDevice(
              accountId: accountId,
              deviceId: transportId,
            );
          } catch (_) {
            // The ACK is durable in the shared account state; normal
            // revocation enforcement will retry the transport cleanup.
          }
        }
        try {
          await _bridge.requestScan(accountId: accountId);
        } catch (_) {}
        await _refreshTransportStatus();
      }
    });
  }

  Future<void> bootstrapPeerTransport({
    required String deviceId,
    required String name,
    String? appDeviceId,
    String? platform,
  }) {
    return _enqueue(() async {
      if (_syncPaused) {
        throw StateError('同步已暂停，请先恢复同步后再添加设备。');
      }

      final remoteId = deviceId.trim();
      if (remoteId.length < 20) {
        throw const FormatException('新设备同步身份无效。');
      }

      if (!_transportPrepared) {
        await _prepareTransport(force: true);
      }
      if (!_transportPrepared) {
        throw StateError(_lastError ?? '同步核心尚未准备好，请稍后重试。');
      }
      if (remoteId == _transportStatus.deviceId?.trim()) {
        throw const FormatException('不能把当前设备作为新设备确认。');
      }

      final remoteName = name.trim();
      if (remoteName.isEmpty) {
        throw const FormatException('新设备名称无效。');
      }
      // A previously unbound installation can legitimately rejoin with the
      // same Syncthing identity but a new app-device ID. Keep this explicit
      // user-approved transport share alive long enough for the new device to
      // publish that app-device record; otherwise an older acknowledged
      // tombstone can immediately unshare it again and create an endless
      // "repairing sync channel" loop.
      await _authorizeTransportRejoin(remoteId);
      var transportShared = false;
      try {
        await _bridge.pairDevice(
          accountId: accountId,
          deviceId: remoteId,
          name: remoteName,
        );
        transportShared = true;

        final provisionalAppDeviceId = appDeviceId?.trim();
        final provisionalPlatform = platform?.trim();
        if (provisionalAppDeviceId != null &&
            provisionalAppDeviceId.length >= 16 &&
            provisionalPlatform != null &&
            provisionalPlatform.isNotEmpty) {
          await accountStore.bindSyncTransportId(
            appDeviceId: provisionalAppDeviceId,
            syncTransportId: remoteId,
            name: remoteName,
            platform: provisionalPlatform,
          );
          // Commit the new app-device record before the receiver tears down the
          // bootstrap folder. This removes the old race where a historical
          // tombstone could unshare the transport before the new device became
          // visible to the source account.
          await _syncAccountState();
          await _bridge.requestScan(accountId: accountId);
        }

        await _refreshTransportStatus();
      } catch (_) {
        if (transportShared) {
          try {
            await _bridge.unshareDevice(
              accountId: accountId,
              deviceId: remoteId,
            );
          } catch (_) {}
        }
        await _clearTransportReauthorization(remoteId);
        rethrow;
      }
    });
  }

  Future<void> refreshNow() {
    return _enqueue(() async {
      // A manual sync is also an explicit repair request. Re-prepare the
      // transport even when it was prepared earlier, because the embedded
      // process or the folder's peer configuration may have disappeared since
      // then. This keeps one-device operation sufficient.
      await _prepareTransport(force: true);
      if (!_transportPrepared) {
        throw StateError(_lastError ?? '同步核心尚未准备好，请稍后重试。');
      }

      await _flushLocalChanges();
      await _bridge.requestScan(accountId: accountId);
      await _reconcileFromSyncDirectory(seedMissing: true);
      await _refreshTransportStatus();
    });
  }

  Future<void> pairFromPayload(String source) {
    return _enqueue(() async {
      if (_syncPaused) {
        throw StateError('同步已暂停，请先恢复同步后再添加设备。');
      }

      final parsed = _bridge.parsePairingPayload(source, accountId: accountId);
      final remoteAppDeviceId = parsed.appDeviceId;
      if (remoteAppDeviceId == deviceId) {
        throw const FormatException('不能把当前设备作为另一台设备重复配对。');
      }
      if (parsed.deviceId == _transportStatus.deviceId) {
        throw const FormatException('不能扫描当前设备自己的同步二维码。');
      }

      // Validate first, then treat the transport share + identity binding as
      // one logical transaction. Persisting the binding before Syncthing
      // succeeds can strand the app-device ID on a transport ID that was never
      // actually paired, while sharing first without rollback can leak the
      // account folder if the binding write later fails.
      accountStore.validateSyncTransportBinding(
        appDeviceId: remoteAppDeviceId,
        syncTransportId: parsed.deviceId,
      );

      var transportShared = false;
      try {
        await _bridge.pairDevice(
          accountId: accountId,
          deviceId: parsed.deviceId,
          name: parsed.deviceName,
        );
        transportShared = true;

        await accountStore.bindSyncTransportId(
          appDeviceId: remoteAppDeviceId,
          syncTransportId: parsed.deviceId,
          name: parsed.deviceName,
          platform: parsed.devicePlatform,
        );
      } catch (_) {
        if (transportShared) {
          try {
            await _bridge.unshareDevice(
              accountId: accountId,
              deviceId: parsed.deviceId,
            );
          } catch (_) {
            // The next status/revocation pass will still refuse an unbound
            // app-device identity; keep the original pairing error.
          }
        }
        rethrow;
      }
      _transportPrepared = true;
      await _refreshTransportStatus();
      await _syncAccountState();
      notifyListeners();
    });
  }

  Future<void> revokeDevice(String appDeviceId) {
    return _enqueue(() async {
      final transportId =
          accountStore.syncSnapshot?.devices[appDeviceId]?.syncTransportId;
      await accountStore.revokeDevice(appDeviceId);
      if (transportId?.trim().isNotEmpty == true) {
        await _clearTransportReauthorization(transportId!);
      }
      await _syncAccountState();

      if (_transportPrepared) {
        try {
          await _bridge.requestScan(accountId: accountId);
        } catch (_) {}
      }

      final state = accountStore.syncSnapshot;
      if (state != null && state.accountId == accountId) {
        await _enforceTransportRevocations(state);
      }
    });
  }

  Future<void> resolveConflict(SyncConflictView view, int candidateIndex) {
    return _enqueue(() async {
      final record = await _recordStore.readMergedRecord(
        accountId: accountId,
        kind: view.kind,
        recordId: view.recordId,
      );
      if (record == null) return;

      final resolved = _mergeEngine.resolveConflict(
        record: record,
        conflictId: view.conflict.id,
        candidateIndex: candidateIndex,
        deviceId: deviceId,
      );
      await _recordStore.write(accountId: accountId, record: resolved);
      await _reconcileFromSyncDirectory(seedMissing: false);
      if (_transportPrepared) {
        await _bridge.requestScan(accountId: accountId);
      }
    });
  }

  Future<void> _prepareTransport({bool force = false}) async {
    if (_syncPaused) {
      _transportPrepared = false;
      return;
    }

    try {
      final before = accountStore.syncSnapshot;
      if (before == null || before.accountId != accountId) {
        _transportPrepared = false;
        return;
      }
      if (before.isRevoked(deviceId)) {
        _transportPrepared = false;
        await _enforceTransportRevocations(before);
        return;
      }

      final path = await _recordStore.rootPath(accountId);
      final prepared = await _bridge.prepare(
        accountId: accountId,
        folderPath: path,
        force: force,
      );
      if (_disposed) return;

      if (prepared) {
        await _bridge.setAccountFolderPaused(
          accountId: accountId,
          paused: false,
        );
      }

      final after = accountStore.syncSnapshot;
      if (after == null ||
          after.accountId != accountId ||
          after.isRevoked(deviceId)) {
        _transportPrepared = prepared;
        if (prepared) {
          await _enforceTransportRevocations(after ?? before);
        }
        return;
      }

      _transportPrepared = prepared;
      await _refreshTransportStatus();
      if (prepared) {
        _lastError = null;
        final current = accountStore.syncSnapshot;
        if (current != null &&
            current.accountId == accountId &&
            !current.isRevoked(deviceId)) {
          await _pairKnownTransportPeers(current);
          await _refreshTransportStatus();
        }
        await _bridge.requestScan(accountId: accountId);
      }
    } catch (error) {
      if (_disposed) return;
      final message = error.toString();
      if (message.contains('仍在继续启动') ||
          message.contains('正在启动，请稍后重试')) {
        _lastError = '同步核心启动时间较长，仍在继续尝试。';
      } else {
        _lastError = '同步核心启动失败：$error';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<File> _transportReauthorizationFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}accounts'
      '${Platform.pathSeparator}$accountId'
      '${Platform.pathSeparator}transport-reauthorizations-v1.json',
    );
  }

  Future<Map<String, DateTime>> _loadTransportReauthorizations() async {
    final file = await _transportReauthorizationFile();
    if (!await file.exists()) return <String, DateTime>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, DateTime>{};
      final now = DateTime.now().toUtc();
      final result = <String, DateTime>{};
      for (final entry in decoded.entries) {
        final id = entry.key.toString().trim();
        final value = entry.value;
        if (id.isEmpty || value is! String) continue;
        final expiresAt = DateTime.tryParse(value)?.toUtc();
        if (expiresAt == null || !expiresAt.isAfter(now)) continue;
        result[id] = expiresAt;
      }
      return result;
    } catch (_) {
      return <String, DateTime>{};
    }
  }

  Future<void> _saveTransportReauthorizations(
    Map<String, DateTime> values,
  ) async {
    final file = await _transportReauthorizationFile();
    if (values.isEmpty) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, String>{
        for (final entry in values.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _authorizeTransportRejoin(String transportId) async {
    final id = transportId.trim();
    if (id.isEmpty) return;
    final values = await _loadTransportReauthorizations();
    values[id] = DateTime.now().toUtc().add(
      _transportReauthorizationLifetime,
    );
    await _saveTransportReauthorizations(values);
  }

  Future<void> _clearTransportReauthorization(String transportId) async {
    final id = transportId.trim();
    if (id.isEmpty) return;
    final values = await _loadTransportReauthorizations();
    if (values.remove(id) == null) return;
    await _saveTransportReauthorizations(values);
  }

  Future<File> _syncPauseFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}accounts'
      '${Platform.pathSeparator}$accountId${Platform.pathSeparator}sync-paused',
    );
  }

  Future<void> _loadSyncPauseState() async {
    try {
      _syncPaused = await (await _syncPauseFile()).exists();
    } catch (_) {
      _syncPaused = false;
    }
  }

  Future<void> _persistSyncPauseState() async {
    final file = await _syncPauseFile();
    if (_syncPaused) {
      await file.parent.create(recursive: true);
      await file.writeAsString('1', flush: true);
    } else if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _pairKnownTransportPeers(AccountSyncState state) async {
    final ownTransportId = _transportStatus.deviceId?.trim();

    for (final device in state.activeDevices) {
      if (device.id == deviceId) continue;
      final remoteTransportId = device.syncTransportId?.trim();
      if (remoteTransportId == null ||
          remoteTransportId.isEmpty ||
          remoteTransportId == ownTransportId) {
        continue;
      }

      try {
        await _bridge.pairDevice(
          accountId: accountId,
          deviceId: remoteTransportId,
          name: device.name.trim().isEmpty ? '工作台设备' : device.name,
        );
      } catch (error) {
        _lastError = '恢复已知设备同步关系失败：$error';
      }
    }
  }

  Future<void> _repairTransportIfNeeded() async {
    if (_disposed || _syncPaused || !_foregroundTransportEnabled) return;

    final state = accountStore.syncSnapshot;
    if (state == null ||
        state.accountId != accountId ||
        state.isRevoked(deviceId)) {
      return;
    }

    final ownTransportId = _transportStatus.deviceId?.trim();
    final expectedRemoteIds = <String>{};
    for (final device in state.activeDevices) {
      if (device.id == deviceId) continue;
      final remoteTransportId = device.syncTransportId?.trim();
      if (remoteTransportId == null ||
          remoteTransportId.isEmpty ||
          remoteTransportId == ownTransportId) {
        continue;
      }
      expectedRemoteIds.add(remoteTransportId);
    }
    if (expectedRemoteIds.isEmpty) {
      return;
    }

    if (!_transportPrepared ||
        !_transportStatus.running ||
        _transportStatus.folderState == null) {
      await _prepareTransport(force: true);
      return;
    }

    final configuredRemoteIds = _transportStatus.configuredDevices
        .map((item) => item['deviceId']?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final connectedExpectedIds = expectedRemoteIds.intersection(
      _transportStatus.connectedDeviceIds.toSet(),
    );

    // Device connectivity alone is not a completed sync handshake. Syncthing
    // reports "valid" only when the peer shares this exact account folder back.
    // The previous repair path returned as soon as the peer existed in config,
    // which could leave a connected notSharing/paused peer stuck at 0% forever.
    final brokenFolderHandshake = connectedExpectedIds.where((id) {
      final remoteState = _transportStatus.remoteFolderStates[id]?.trim();
      return remoteState == 'notSharing' || remoteState == 'paused';
    }).toSet();

    final missingConfiguredPeer =
        !expectedRemoteIds.every(configuredRemoteIds.contains);
    if (missingConfiguredPeer) {
      // Repair only configuration that is actually missing on this device.
      // Remote "notSharing" / "paused" states belong to the peer and cannot be
      // fixed by repeatedly rewriting our local Syncthing configuration.
      await _pairKnownTransportPeers(state);
      await _refreshTransportStatus();
      return;
    }

    if (brokenFolderHandshake.isNotEmpty) {
      _lastError =
          '设备已经连接，但另一台设备的同步目录尚未共享或已暂停。'
          '请让另一台设备保持打开并恢复同步。';
    }
  }

  Future<void> _refreshTransportStatus() async {
    try {
      _transportStatus = await _bridge.status(accountId: accountId);
      if (_transportStatus.error != null) {
        _lastError = _transportStatus.error;
      } else if (_transportStatus.folderErrors.isNotEmpty) {
        _lastError = '同步目录错误：${_transportStatus.folderErrors.first}';
      }

      final ownTransportId = _transportStatus.deviceId?.trim();
      if (ownTransportId != null && ownTransportId.isNotEmpty) {
        final canonicalDeviceId =
            await accountStore.reconcileCurrentDeviceTransportIdentity(
          syncTransportId: ownTransportId,
        );
        if (canonicalDeviceId != null && canonicalDeviceId != deviceId) {
          deviceId = canonicalDeviceId;
        }

        final currentDevice = accountStore.syncSnapshot?.devices[deviceId];
        if (currentDevice == null) {
          throw StateError('当前设备记录不存在。');
        }
        await accountStore.bindSyncTransportId(
          appDeviceId: deviceId,
          syncTransportId: ownTransportId,
          name: currentDevice.name,
          platform: currentDevice.platform,
        );
      }

      final state = accountStore.syncSnapshot;
      if (state != null && state.accountId == accountId) {
        await _enforceTransportRevocations(state);
      }
    } catch (error) {
      _lastError = '读取同步状态失败：$error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _flushLocalChanges() async {
    if (_disposed || _applyingRemote || _applyingAccount) return;

    await _syncAccountState();
    await _flushLocalEntityChanges();
  }

  Future<void> _flushLocalEntityChanges() async {
    if (_disposed ||
        _applyingRemote ||
        _applyingAccount ||
        _awaitingInitialRemoteWorkspace) {
      return;
    }

    final accountAfterSync = accountStore.syncSnapshot;
    if (accountAfterSync == null ||
        accountAfterSync.accountId != accountId ||
        accountAfterSync.isRevoked(deviceId)) {
      return;
    }

    final currentEntities = _captureEntities();

    var wrote = false;
    for (final kind in SyncEntityKind.values) {
      wrote |= await _flushKind(
        kind: kind,
        previous: _lastEntityValues[kind]!,
        current: currentEntities[kind]!,
      );
    }

    _lastEntityValues = currentEntities;

    if (wrote) {
      _lastSuccessfulSyncAt = DateTime.now();
      if (_transportPrepared) {
        await _bridge.requestScan(accountId: accountId);
      }
      await _rebuildConflicts();
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _flushKind({
    required SyncEntityKind kind,
    required Map<String, Map<String, dynamic>> previous,
    required Map<String, Map<String, dynamic>> current,
  }) async {
    var wrote = false;
    final ids = <String>{...previous.keys, ...current.keys};

    for (final id in ids) {
      final before = previous[id];
      final after = current[id];
      if (syncJsonEquals(before, after)) continue;

      final currentRecord = await _recordStore.readMergedRecord(
        accountId: accountId,
        kind: kind,
        recordId: id,
      );
      final baselineRecord = _lastFlushedRecords[kind]![id];
      SyncRecord localRecord;

      if (after == null) {
        final baseRecord = baselineRecord ?? currentRecord;
        if (baseRecord == null) {
          if (before == null) continue;
          localRecord = SyncRecord.bootstrap(
            kind: kind,
            id: id,
            values: before,
            deviceId: deviceId,
          );
        } else {
          localRecord = baseRecord;
        }
        localRecord = _mergeEngine.markDeleted(
          localRecord,
          deviceId: deviceId,
        );
      } else if (baselineRecord != null) {
        // Edit the last record this device actually observed, not the remote
        // version that may have arrived since. Otherwise concurrent edits are
        // incorrectly stamped as happening after that remote version.
        localRecord = _mergeEngine.applyLocalSnapshot(
          record: baselineRecord,
          previousValues: before ?? after,
          nextValues: after,
          deviceId: deviceId,
        );
      } else if (currentRecord == null) {
        localRecord = SyncRecord.bootstrap(
          kind: kind,
          id: id,
          values: after,
          deviceId: deviceId,
        );
      } else {
        localRecord = _mergeEngine.applyLocalSnapshot(
          record: currentRecord,
          previousValues: before ?? after,
          nextValues: after,
          deviceId: deviceId,
        );
      }

      final record = currentRecord == null
          ? localRecord
          : _mergeEngine.merge(currentRecord, localRecord);

      await _recordStore.write(accountId: accountId, record: record);
      _lastFlushedRecords[kind]![id] = record;
      wrote = true;
    }

    return wrote;
  }

  Future<void> _reconcileFromSyncDirectory({
    required bool seedMissing,
    bool seedSettings = true,
  }) async {
    if (_disposed) return;

    // The poller and the 220 ms local debounce share the same queue. Flush
    // entity changes before reading remote records so an already-queued poll
    // cannot apply an older disk snapshot over a just-edited store.
    _changeDebounce?.cancel();
    await _syncAccountState();
    if (!_awaitingInitialRemoteWorkspace) {
      await _flushLocalEntityChanges();
    }
    final accountAfterSync = accountStore.syncSnapshot;
    if (accountAfterSync == null ||
        accountAfterSync.accountId != accountId ||
        accountAfterSync.isRevoked(deviceId)) {
      return;
    }

    final recordsByKind = <SyncEntityKind, Map<String, SyncRecord>>{};
    for (final kind in SyncEntityKind.values) {
      final records = await _recordStore.readAllMerged(
        accountId: accountId,
        kind: kind,
      );
      await _mergePersistedBaseline(kind, records);
      recordsByKind[kind] = records;
    }

    if (seedMissing && !_awaitingInitialRemoteWorkspace) {
      final localEntities = _captureEntities();
      for (final kind in SyncEntityKind.values) {
        if (kind == SyncEntityKind.settings && !seedSettings) continue;
        await _seedMissing(
          kind: kind,
          local: localEntities[kind]!,
          records: recordsByKind[kind]!,
        );
      }
    }

    await _migrateLegacyFeatureSettings(recordsByKind[SyncEntityKind.settings]!);

    // Schema upgrades can add fields to an existing entity. If the local
    // object already has the new field but the older sync record does not,
    // normal change detection sees no edit (for example missing vs null) and
    // would leave the record permanently incomplete. Backfill those fields
    // before applying/exporting so the portable history exactly represents
    // the current workspace.
    if (!_awaitingInitialRemoteWorkspace) {
      final localEntities = _captureEntities();
      for (final kind in SyncEntityKind.values) {
        await _backfillMissingRecordFields(
          kind: kind,
          local: localEntities[kind]!,
          records: recordsByKind[kind]!,
        );
      }
      await _removeSupersededLegacySettings(
        recordsByKind[SyncEntityKind.settings]!,
      );
    }

    _applyingRemote = true;
    try {
      for (final kind in SyncEntityKind.values) {
        await _applyEntityRecords(kind, recordsByKind[kind]!);
      }
    } finally {
      _applyingRemote = false;
    }

    await _persistFocusNormalization(
      recordsByKind[SyncEntityKind.focusSession]!,
    );

    var gcChanged = false;
    if (!_awaitingInitialRemoteWorkspace) {
      await _gcAckStore.writeSnapshot(
        accountId: accountId,
        deviceId: deviceId,
        recordsByKind: recordsByKind,
      );
      gcChanged = await _compactAcknowledgedHistory(recordsByKind);
      if (gcChanged) {
        // Publish the post-GC state as this device's new acknowledgement.
        await _gcAckStore.writeSnapshot(
          accountId: accountId,
          deviceId: deviceId,
          recordsByKind: recordsByKind,
        );
      }
    }

    _lastEntityValues = _captureEntities();
    for (final kind in SyncEntityKind.values) {
      _lastFlushedRecords[kind] = recordsByKind[kind]!;
    }
    if (_awaitingInitialRemoteWorkspace) {
      final hasRemoteSettings =
          recordsByKind[SyncEntityKind.settings]!.containsKey(settingsRecordId);
      final hasRemotePresets = recordsByKind[SyncEntityKind.nodePreset]!.isNotEmpty;
      if (hasRemoteSettings && hasRemotePresets) {
        _awaitingInitialRemoteWorkspace = false;
      }
    }
    _hasRestoredSyncBaseline = false;
    _conflicts = _collectConflicts(recordsByKind);
    _lastSuccessfulSyncAt = DateTime.now();
    _lastError = null;
    if (gcChanged && _transportPrepared) {
      try {
        await _bridge.requestScan(accountId: accountId);
      } catch (error) {
        _lastError = '同步历史优化后触发扫描失败：$error';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> _compactAcknowledgedHistory(
    Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  ) async {
    final state = accountStore.syncSnapshot;
    if (state == null || state.accountId != accountId) return false;

    final activeDeviceIds = <String>{
      for (final device in state.activeDevices) device.id,
    };
    if (activeDeviceIds.isEmpty) return false;

    await _gcAckStore.pruneDevices(
      accountId: accountId,
      activeDeviceIds: activeDeviceIds,
    );
    final acknowledgements = await _gcAckStore.readAll(accountId);
    if (!activeDeviceIds.every(acknowledgements.containsKey)) {
      // An old/offline active device has not joined the GC protocol yet.
      // Keeping history is safer than making that device capable of reviving
      // or double-applying stale data later.
      return false;
    }

    var changed = false;
    final protectedReferencePaths = syncGcProtectedReferencePaths(
      recordsByKind: recordsByKind,
      mergeEngine: _mergeEngine,
    );

    for (final kind in SyncEntityKind.values) {
      final records = recordsByKind[kind]!;
      final entries = records.entries.toList(growable: false);

      for (final entry in entries) {
        final record = entry.value;
        if (record.conflicts.isNotEmpty ||
            _mergeEngine.hasUnsupportedOperations(record)) {
          // Do not let an older app garbage-collect a newer operation kind it
          // cannot materialize. Keeping the record is safe; a newer peer can
          // compact it once every active device understands the operation.
          continue;
        }

        final hasFullOperations =
            record.operations.values.any((operation) => !operation.compacted);
        final hasOnlyCompactedOperations =
            record.operations.isNotEmpty && !hasFullOperations;

        // A compacted marker proves that every active device acknowledged the
        // full operation in the previous GC phase. Each device may therefore
        // remove its own orphaned image immediately when it sees that marker,
        // before a different peer strips the final cleanup metadata.
        if (hasOnlyCompactedOperations) {
          final orphanedImages = syncGcOrphanReferenceImages(
            record: record,
            protectedPaths: protectedReferencePaths,
          );
          if (orphanedImages.isNotEmpty) {
            await _referenceImageStore.deleteImages(
              accountId: accountId,
              images: orphanedImages,
              requestScan: false,
            );
          }
        }

        final key = _gcAckStore.recordKey(record);
        final signature = await _gcAckStore.signature(record);
        final seenByAll = activeDeviceIds.every(
          (id) => acknowledgements[id]?[key] == signature,
        );
        if (!seenByAll) continue;

        if (hasFullOperations) {
          // First phase: fold live operations, or mark a deletion as globally
          // acknowledged. Reference-image metadata deliberately survives in
          // the compacted marker for per-device physical cleanup.
          final compacted = _mergeEngine.compactAcknowledgedOperations(
            record,
            deviceId: deviceId,
          );
          if (!syncJsonEquals(record.toJson(), compacted.toJson())) {
            await _recordStore.write(accountId: accountId, record: compacted);
            records[record.id] = compacted;
            changed = true;
          }
          continue;
        }

        if (record.isDeleted) {
          // Second phase for deletions: every device has acknowledged the
          // compacted tombstone, and each had an opportunity to remove local
          // image files from the preserved metadata.
          await _recordStore.deleteRecord(
            accountId: accountId,
            kind: kind,
            recordId: record.id,
          );
          records.remove(record.id);
          changed = true;
          continue;
        }

        if (record.operations.isNotEmpty) {
          // Second phase for live records: every device has acknowledged the
          // folded state, so the tiny operation markers can disappear.
          final stripped = record.copyWith(
            operations: const <String, SyncOperation>{},
          );
          await _recordStore.write(accountId: accountId, record: stripped);
          records[record.id] = stripped;
          changed = true;
        }
      }
    }

    return changed;
  }

  Future<void> _mergePersistedBaseline(
    SyncEntityKind kind,
    Map<String, SyncRecord> records,
  ) async {
    if (!_hasRestoredSyncBaseline) return;

    for (final entry in _lastFlushedRecords[kind]!.entries) {
      final baseline = entry.value;
      final current = records[entry.key];
      if (current == null) {
        records[entry.key] = baseline;
        await _recordStore.write(accountId: accountId, record: baseline);
        continue;
      }

      final merged = _mergeEngine.merge(current, baseline);
      if (syncJsonEquals(current.toJson(), merged.toJson())) continue;

      records[entry.key] = merged;
      await _recordStore.write(accountId: accountId, record: merged);
    }
  }

  Future<void> _syncAccountState() async {
    final local = accountStore.syncSnapshot;
    if (local == null || local.accountId != accountId) return;

    final merged = await _accountSyncStore.readMerged(
      accountId: accountId,
      seed: local,
    );

    if (merged != null && merged.isRevoked(deviceId)) {
      // AccountStore notifies synchronously when the revoked state is applied,
      // which can dispose HomePage. Persist the acknowledgement first so a
      // successful read of the revocation cannot lose its only ACK window.
      final revocation = merged.revocations[deviceId];
      if (revocation != null) {
        await _acknowledgeRevocation(revocation);
      }
    }

    if (merged != null && !syncJsonEquals(local.toJson(), merged.toJson())) {
      _applyingAccount = true;
      try {
        await accountStore.mergeSyncedState(merged);
      } finally {
        _applyingAccount = false;
      }
    }

    final current = accountStore.syncSnapshot;
    if (current == null || current.accountId != accountId) {
      return;
    }
    if (current.isRevoked(deviceId)) {
      await _enforceTransportRevocations(current);
      return;
    }

    await _accountSyncStore.write(
      accountId: accountId,
      deviceId: deviceId,
      state: current,
    );
    await _enforceTransportRevocations(current);
  }

  Future<void> _enforceTransportRevocations(AccountSyncState state) async {
    if (_disposed) return;
    if (state.isRevoked(deviceId)) {
      final revocation = state.revocations[deviceId];
      if (revocation == null) return;

      await _acknowledgeRevocation(revocation);
      return;
    }

    if (!_transportPrepared) return;

    final configuredTransportIds = <String>{
      for (final item in _transportStatus.configuredDevices)
        if ((item['deviceId'] as String?)?.trim().isNotEmpty == true)
          (item['deviceId'] as String).trim(),
    };

    final activeTransportIds = <String>{
      for (final device in state.activeDevices)
        if (device.syncTransportId?.trim().isNotEmpty == true)
          device.syncTransportId!.trim(),
    };
    final reauthorizedTransportIds =
        (await _loadTransportReauthorizations()).keys.toSet();

    // Once the rejoined app-device record has propagated, the normal active
    // device binding is enough; remove the temporary local authorization.
    for (final transportId
        in activeTransportIds.intersection(reauthorizedTransportIds)) {
      await _clearTransportReauthorization(transportId);
    }

    for (final entry in state.revocations.entries) {
      final revokedId = entry.key;
      if (revokedId == deviceId) continue;
      final transportId = state.devices[revokedId]?.syncTransportId?.trim();
      if (transportId == null || transportId.isEmpty) {
        continue;
      }

      // Keep the transport share until that exact revocation has been observed
      // and acknowledged by the remote app-device.
      final acknowledged = await _accountSyncStore.hasRevocationAck(
        accountId: accountId,
        deviceId: revokedId,
        revokedAt: entry.value.revokedAt,
      );
      if (!acknowledged) continue;

      // The same physical Syncthing identity may be explicitly re-authorized
      // after a revoked device rejoins and receives a new app-device ID.
      // During the short bootstrap window the new app-device record may not
      // have arrived yet, so also honor the persisted explicit rejoin marker.
      if (shouldRetainRevokedTransportShare(
        transportId: transportId,
        activeTransportIds: activeTransportIds,
        reauthorizedTransportIds: reauthorizedTransportIds,
      )) {
        continue;
      }

      // Do not remember an unshare forever: a stale/foreign config could add
      // the device back later. Folder-scoped status lets the next refresh
      // detect that and remove it again.
      if (_transportStatus.running &&
          !configuredTransportIds.contains(transportId)) {
        continue;
      }

      try {
        await _bridge.unshareDevice(
          accountId: accountId,
          deviceId: transportId,
        );
      } catch (_) {
        // Keep it pending so the next pass retries.
      }
    }
  }

  Future<void> _acknowledgeRevocation(DeviceRevocation revocation) async {
    try {
      // A revoked device acknowledges the exact tombstone before peers stop
      // sharing the folder. This avoids the old half-state where an offline
      // peer could be unshared before ever learning that it had been revoked.
      await _accountSyncStore.writeRevocationAck(
        accountId: accountId,
        deviceId: deviceId,
        revokedAt: revocation.revokedAt,
      );
    } catch (error) {
      _lastError = '写入设备撤销确认失败：$error';
      return;
    }

    if (!_transportPrepared) return;
    try {
      await _bridge.requestScan(accountId: accountId);
    } catch (error) {
      _lastError = '发送设备撤销确认失败：$error';
    }
  }

  Future<void> _seedMissing({
    required SyncEntityKind kind,
    required Map<String, Map<String, dynamic>> local,
    required Map<String, SyncRecord> records,
  }) async {
    for (final entry in local.entries) {
      if (records.containsKey(entry.key)) continue;
      final record = SyncRecord.bootstrap(
        kind: kind,
        id: entry.key,
        values: entry.value,
        deviceId: deviceId,
      );
      await _recordStore.write(accountId: accountId, record: record);
      records[entry.key] = record;
    }
  }

  Map<String, dynamic> _normalizeMaterializedSettings(
    Map<String, dynamic> settings,
  ) {
    final normalized = <String, dynamic>{...settings};
    final hasFieldLevelFeatures = normalized.keys.any(
      (key) => key.startsWith('feature.'),
    );
    if (hasFieldLevelFeatures) {
      normalized.remove('features');
    }
    if (normalized.containsKey('uiStyle')) {
      normalized.remove('uiTexture');
    }
    return normalized;
  }

  Future<void> _backfillMissingRecordFields({
    required SyncEntityKind kind,
    required Map<String, Map<String, dynamic>> local,
    required Map<String, SyncRecord> records,
  }) async {
    for (final entry in local.entries) {
      final record = records[entry.key];
      if (record == null || record.isDeleted) continue;

      final fields = <String, SyncFieldValue>{...record.fields};
      var changed = false;
      for (final valueEntry in entry.value.entries) {
        final field = valueEntry.key;
        if (field == 'id' || fields.containsKey(field)) continue;
        fields[field] = SyncFieldValue(
          value: valueEntry.value,
          clock: SyncClock.empty().tick(deviceId),
          updatedBy: deviceId,
        );
        changed = true;
      }
      if (!changed) continue;

      final migrated = SyncRecord(
        accountId: record.accountId,
        kind: kind,
        id: record.id,
        fields: Map<String, SyncFieldValue>.unmodifiable(fields),
        operations: record.operations,
        conflicts: record.conflicts,
      );
      await _recordStore.write(accountId: accountId, record: migrated);
      records[entry.key] = migrated;
    }
  }

  Future<void> _removeSupersededLegacySettings(
    Map<String, SyncRecord> records,
  ) async {
    final record = records[settingsRecordId];
    if (record == null || !record.fields.containsKey('uiStyle')) return;
    if (!record.fields.containsKey('uiTexture') &&
        !record.conflicts.containsKey('uiTexture')) {
      return;
    }

    final fields = <String, SyncFieldValue>{...record.fields}
      ..remove('uiTexture');
    final conflicts = <String, SyncConflict>{...record.conflicts}
      ..remove('uiTexture');
    final migrated = SyncRecord(
      accountId: record.accountId,
      kind: record.kind,
      id: record.id,
      fields: Map<String, SyncFieldValue>.unmodifiable(fields),
      operations: record.operations,
      conflicts: Map<String, SyncConflict>.unmodifiable(conflicts),
    );
    await _recordStore.write(accountId: accountId, record: migrated);
    records[settingsRecordId] = migrated;
  }

  Future<void> _migrateLegacyFeatureSettings(
    Map<String, SyncRecord> records,
  ) async {
    final record = records[settingsRecordId];
    if (record == null) return;

    final legacy = record.fields['features']?.value;
    if (legacy is! Map) return;

    final before = _mergeEngine.materialize(record);
    if (before == null) return;
    final next = <String, dynamic>{...before};
    var changed = false;

    for (final entry in legacy.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name is! String || value is! bool) continue;
      final field = 'feature.$name';
      if (record.fields.containsKey(field)) continue;
      next[field] = value;
      changed = true;
    }
    if (!changed) return;

    final migrated = _mergeEngine.applyLocalSnapshot(
      record: record,
      previousValues: before,
      nextValues: next,
      deviceId: deviceId,
    );
    await _recordStore.write(accountId: accountId, record: migrated);
    records[settingsRecordId] = migrated;
  }

  Future<void> _applyEntityRecords(
    SyncEntityKind kind,
    Map<String, SyncRecord> records,
  ) async {
    switch (kind) {
      case SyncEntityKind.order:
        _applyOrderRecords(records);
      case SyncEntityKind.product:
        _applyProductRecords(records);
      case SyncEntityKind.nodePreset:
        _applyPresetRecords(records);
      case SyncEntityKind.focusSession:
        _applyFocusRecords(records);
      case SyncEntityKind.settings:
        await _applySettingsRecords(records);
    }
  }

  Future<void> _applySettingsRecords(
    Map<String, SyncRecord> records,
  ) async {
    final record = records[settingsRecordId];
    if (record == null) return;

    final local = captureSettings();
    final settings = _mergeEngine.materializeKeepingLocalConflicts(
      record,
      local,
    );
    if (settings == null) return;

    final normalized = _normalizeMaterializedSettings(settings);
    if (syncJsonEquals(normalized, local)) return;

    try {
      await applySettings(normalized);
    } catch (error) {
      _lastError = '应用远端界面设置失败：$error';
    }
  }

  void _applyOrderRecords(Map<String, SyncRecord> records) {
    final result = <QueueOrder>[];

    for (final existing in orderStore.orders) {
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
      if (orderStore.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.orderFromFields(fields));
      } catch (_) {
        // Invalid remote record stays on disk for later repair.
      }
    }

    if (!_sameOrderList(orderStore.orders, result)) {
      orderStore.replaceAll(result);
    }
  }

  void _applyProductRecords(Map<String, SyncRecord> records) {
    final result = <FinishedProduct>[];

    for (final existing in productStore.products) {
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
      if (productStore.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.productFromFields(fields));
      } catch (_) {
        // Invalid remote record stays on disk for later repair.
      }
    }

    if (!_sameProductList(productStore.products, result)) {
      productStore.replaceAll(result);
    }
  }

  void _applyPresetRecords(Map<String, SyncRecord> records) {
    final current = <String, NodePreset>{
      for (final preset in nodePresetStore.presets) preset.id: preset,
    };
    final result = <NodePreset>[];

    for (final existing in nodePresetStore.presets) {
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
      current.remove(existing.id);
    }

    for (final record in records.values) {
      if (current.containsKey(record.id) ||
          nodePresetStore.presets.any((preset) => preset.id == record.id)) {
        continue;
      }
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.nodePresetFromFields(fields));
      } catch (_) {
        // Keep processing other presets.
      }
    }

    final currentFields = _capturePresets();
    final resultFields = <String, Map<String, dynamic>>{
      for (final preset in result)
        preset.id: SyncEntityCodec.nodePresetToFields(preset),
    };
    if (!syncJsonEquals(currentFields, resultFields)) {
      nodePresetStore.replaceAll(result);
    }
  }

  void _applyFocusRecords(Map<String, SyncRecord> records) {
    final result = <FocusSession>[];

    for (final existing in focusStore.sessions) {
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
      if (focusStore.contains(record.id)) continue;
      final fields = _mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.focusSessionFromFields(fields));
      } catch (_) {
        // Invalid remote focus record stays on disk for later repair.
      }
    }

    if (!_sameFocusList(focusStore.sessions, result)) {
      focusStore.replaceAll(result);
    }
  }

  Future<void> _persistFocusNormalization(
    Map<String, SyncRecord> records,
  ) async {
    for (final session in focusStore.sessions) {
      final record = records[session.id];
      if (record == null) continue;
      final previous = _mergeEngine.materialize(record);
      if (previous == null) continue;
      final next = SyncEntityCodec.focusSessionToFields(session);
      if (syncJsonEquals(previous, next)) continue;

      final updated = _mergeEngine.applyLocalSnapshot(
        record: record,
        previousValues: previous,
        nextValues: next,
        deviceId: deviceId,
      );
      await _recordStore.write(accountId: accountId, record: updated);
      records[session.id] = updated;
    }
  }

  List<SyncConflictView> _collectConflicts(
    Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  ) {
    final result = <SyncConflictView>[];
    for (final kind in SyncEntityKind.values) {
      result.addAll(_viewsFor(kind, recordsByKind[kind]!));
    }
    result.sort((a, b) => b.conflict.createdAt.compareTo(a.conflict.createdAt));
    return result;
  }

  Iterable<SyncConflictView> _viewsFor(
    SyncEntityKind kind,
    Map<String, SyncRecord> records,
  ) sync* {
    for (final record in records.values) {
      for (final conflict in record.conflicts.values) {
        yield SyncConflictView(
          kind: kind,
          recordId: record.id,
          conflict: conflict,
        );
      }
    }
  }

  Future<void> _rebuildConflicts() async {
    final recordsByKind = <SyncEntityKind, Map<String, SyncRecord>>{};
    for (final kind in SyncEntityKind.values) {
      recordsByKind[kind] = await _recordStore.readAllMerged(
        accountId: accountId,
        kind: kind,
      );
    }
    _conflicts = _collectConflicts(recordsByKind);
  }

  Map<String, Map<String, dynamic>> _baselineValues(SyncEntityKind kind) {
    final values = <String, Map<String, dynamic>>{};
    for (final entry in _lastFlushedRecords[kind]!.entries) {
      final fields = _mergeEngine.materialize(entry.value);
      if (fields != null) values[entry.key] = fields;
    }
    return values;
  }

  Map<String, Map<String, dynamic>> _captureOrders() {
    return <String, Map<String, dynamic>>{
      for (final order in orderStore.orders)
        order.id: SyncEntityCodec.orderToFields(order),
    };
  }

  Map<String, Map<String, dynamic>> _captureProducts() {
    return <String, Map<String, dynamic>>{
      for (final product in productStore.products)
        product.id: SyncEntityCodec.productToFields(product),
    };
  }

  Map<String, Map<String, dynamic>> _capturePresets() {
    return <String, Map<String, dynamic>>{
      for (final preset in nodePresetStore.presets)
        preset.id: SyncEntityCodec.nodePresetToFields(preset),
    };
  }

  Map<String, Map<String, dynamic>> _captureFocusSessions() {
    return <String, Map<String, dynamic>>{
      for (final session in focusStore.sessions)
        session.id: SyncEntityCodec.focusSessionToFields(session),
    };
  }

  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> _captureEntities() {
    return <SyncEntityKind, Map<String, Map<String, dynamic>>>{
      SyncEntityKind.order: _captureOrders(),
      SyncEntityKind.product: _captureProducts(),
      SyncEntityKind.nodePreset: _capturePresets(),
      SyncEntityKind.focusSession: _captureFocusSessions(),
      SyncEntityKind.settings: <String, Map<String, dynamic>>{
        settingsRecordId: captureSettings(),
      },
    };
  }

  bool _sameOrderList(Iterable<QueueOrder> left, Iterable<QueueOrder> right) {
    final a = <Map<String, dynamic>>[
      for (final order in left) SyncEntityCodec.orderToFields(order),
    ];
    final b = <Map<String, dynamic>>[
      for (final order in right) SyncEntityCodec.orderToFields(order),
    ];
    return syncJsonEquals(a, b);
  }

  bool _sameProductList(
    Iterable<FinishedProduct> left,
    Iterable<FinishedProduct> right,
  ) {
    final a = <Map<String, dynamic>>[
      for (final product in left) SyncEntityCodec.productToFields(product),
    ];
    final b = <Map<String, dynamic>>[
      for (final product in right) SyncEntityCodec.productToFields(product),
    ];
    return syncJsonEquals(a, b);
  }

  bool _sameFocusList(
    Iterable<FocusSession> left,
    Iterable<FocusSession> right,
  ) {
    final a = <Map<String, dynamic>>[
      for (final session in left)
        SyncEntityCodec.focusSessionToFields(session),
    ];
    final b = <Map<String, dynamic>>[
      for (final session in right)
        SyncEntityCodec.focusSessionToFields(session),
    ];
    return syncJsonEquals(a, b);
  }

  void _enqueueBackground(Future<void> Function() action) {
    if (_disposed || _removingLocalAccount) return;
    unawaited(
      _enqueue(action, showBusy: false).catchError((Object _, StackTrace __) {
        // Background work reports through lastError; do not surface an
        // unhandled Future error into the Flutter zone.
      }),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action, {bool showBusy = true}) {
    final completer = Completer<T>();
    _tail = _tail
        .then<void>((_) async {
          if (_disposed) {
            if (!completer.isCompleted) {
              completer.completeError(StateError('同步协调器已关闭。'));
            }
            return;
          }
          if (showBusy) {
            _syncBusy = true;
            if (!_disposed) notifyListeners();
          }
          try {
            final result = await action();
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            _lastError = error.toString();
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          } finally {
            if (showBusy) {
              _syncBusy = false;
              if (!_disposed) notifyListeners();
            }
          }
        })
        .catchError((Object _, StackTrace __) {
          // Keep the queue alive after one failed iteration.
        });
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changeDebounce?.cancel();
    _pollTimer?.cancel();
    if (_initialized) {
      accountStore.removeListener(_onAccountChanged);
      orderStore.removeListener(_onLocalChanged);
      productStore.removeListener(_onLocalChanged);
      nodePresetStore.removeListener(_onLocalChanged);
      focusStore.removeListener(_onLocalChanged);
    }
    super.dispose();
  }
}
