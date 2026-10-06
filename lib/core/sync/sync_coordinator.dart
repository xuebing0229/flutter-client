import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../account/account_models.dart';
import '../account/account_store.dart';
import '../portability/app_backup_data.dart';
import '../../features/orders/data/node_presets.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/domain/finished_product.dart';
import '../../features/products/state/product_store.dart';
import 'account_sync_record_store.dart';
import 'embedded_syncthing_bridge.dart';
import 'portable_sync_workspace_validator.dart';
import 'sync_entity_codec.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';
import 'sync_record_store.dart';

typedef SyncSettingsCapture = Map<String, dynamic> Function();
typedef SyncSettingsApply = Future<void> Function(Map<String, dynamic> settings);

class PortableWorkspaceSnapshot {
  const PortableWorkspaceSnapshot({
    required this.exportedAt,
    required this.orders,
    required this.products,
    required this.nodePresets,
    required this.settings,
    required this.accountSyncState,
    required this.syncRecords,
  });

  final DateTime exportedAt;
  final List<QueueOrder> orders;
  final List<FinishedProduct> products;
  final List<NodePreset> nodePresets;
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
    'themeMode' => '主题模式',
    'themePaletteId' => '主题色',
    'features' => '功能开关',
    'orderCardView' => '排单卡片视图',
    'productCardView' => '成品卡片视图',
    'orderSortMode' => '排单排序',
    'productSortMode' => '成品排序',
    'desktopNavigationOpen' => '电脑导航栏状态',
    'name' => '预设名称',
    'nodes' => '节点内容',
    SyncRecord.deletedField => '删除状态',
    _ => field,
  };
}

class SyncCoordinator extends ChangeNotifier {
  static const settingsRecordId = 'app';

  SyncCoordinator({
    required this.accountId,
    required this.deviceId,
    required this.deviceName,
    required this.accountStore,
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.captureSettings,
    required this.applySettings,
    SyncMergeEngine? mergeEngine,
    SyncRecordStore? recordStore,
    AccountSyncRecordStore? accountSyncStore,
    EmbeddedSyncthingBridge bridge = const EmbeddedSyncthingBridge(),
  }) : _mergeEngine = mergeEngine ?? SyncMergeEngine(),
       _recordStore = recordStore ?? SyncRecordStore(),
       _accountSyncStore = accountSyncStore ?? AccountSyncRecordStore(),
       _bridge = bridge;

  final String accountId;
  final String deviceId;
  final String deviceName;
  final AccountStore accountStore;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final SyncSettingsCapture captureSettings;
  final SyncSettingsApply applySettings;
  final SyncMergeEngine _mergeEngine;
  final SyncRecordStore _recordStore;
  final AccountSyncRecordStore _accountSyncStore;
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
      for (var attempt = 0; attempt < 3; attempt++) {
        await _flushLocalChanges();
        await _reconcileFromSyncDirectory(seedMissing: false);

        final state = accountStore.syncSnapshot;
        if (state == null ||
            state.accountId != accountId ||
            state.isRevoked(deviceId)) {
          throw StateError('当前设备已经不能导出这个账号的数据。');
        }

        final orderFields = _captureOrders();
        final productFields = _captureProducts();
        final presetFields = _capturePresets();
        final settings = captureSettings();
        final orders = <QueueOrder>[...orderStore.orders];
        final products = <FinishedProduct>[...productStore.products];
        final presets = <NodePreset>[
          for (final preset in nodePresetStore.presets) preset.snapshot(),
        ];
        final accountSnapshot = state;

        final records = await _recordStore.exportPortableRecords(
          accountId: accountId,
        );

        final storesUnchanged =
            syncJsonEquals(orderFields, _captureOrders()) &&
            syncJsonEquals(productFields, _captureProducts()) &&
            syncJsonEquals(presetFields, _capturePresets()) &&
            syncJsonEquals(settings, captureSettings()) &&
            syncJsonEquals(
              accountSnapshot.toJson(),
              accountStore.syncSnapshot?.toJson(),
            );
        if (!storesUnchanged) continue;

        if (!PortableSyncWorkspaceValidator.recordsMatchWorkspace(
          accountId: accountId,
          records: records,
          orders: orderFields,
          products: productFields,
          presets: presetFields,
          settings: settings,
          mergeEngine: _mergeEngine,
        )) {
          // Syncthing can land a file while the export is being read. Reconcile
          // that version into the stores, then capture the package again.
          continue;
        }

        return PortableWorkspaceSnapshot(
          exportedAt: DateTime.now(),
          orders: orders,
          products: products,
          nodePresets: presets,
          settings: settings,
          accountSyncState: accountSnapshot,
          syncRecords: records,
        );
      }

      throw StateError('导出期间数据持续发生变化，请稍后重试。');
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
    required void Function() applyWorkspace,
    Directory? assetSourceDirectory,
  }) {
    if (_disposed || !_initialized) {
      throw StateError('同步协调器尚未准备好，不能恢复同步历史。');
    }

    _changeDebounce?.cancel();
    return _enqueue(() async {
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
      if (_transportPrepared) {
        await _bridge.requestScan(accountId: accountId);
      }
    });
  }

  Future<void> _restorePortableBackup({
    required AppBackupData backup,
    required void Function()? applyWorkspace,
    Directory? assetSourceDirectory,
  }) async {
    PortableSyncWorkspaceValidator.validateBackup(
      backup: backup,
      accountId: accountId,
    );
    final records = backup.syncRecords!;

    await _recordStore.replacePortableRecords(
      accountId: accountId,
      records: records,
      assetSourceDirectory: assetSourceDirectory,
      requiredIds: <SyncEntityKind, Set<String>>{
        SyncEntityKind.order: <String>{
          for (final order in backup.orders) order.id,
        },
        SyncEntityKind.product: <String>{
          for (final product in backup.products) product.id,
        },
        SyncEntityKind.nodePreset: <String>{
          for (final preset in backup.nodePresets) preset.id,
        },
      },
    );

    if (applyWorkspace != null) {
      _applyingRemote = true;
      try {
        applyWorkspace();
      } finally {
        _applyingRemote = false;
      }
    }
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;

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
      await _reconcileFromSyncDirectory(seedMissing: true);
    });

    if (_disposed) return;
    accountStore.addListener(_onAccountChanged);
    orderStore.addListener(_onLocalChanged);
    productStore.addListener(_onLocalChanged);
    nodePresetStore.addListener(_onLocalChanged);
    _initialized = true;
    notifyListeners();

    final account = accountStore.syncSnapshot;
    final currentTransportId = account?.devices[deviceId]?.syncTransportId
        ?.trim();
    final needsFirstTransportBootstrap =
        (currentTransportId == null || currentTransportId.isEmpty) &&
        (account?.activeDevices.any((device) {
              final remoteTransportId = device.syncTransportId?.trim();
              return device.id != deviceId &&
                  remoteTransportId != null &&
                  remoteTransportId.isNotEmpty;
            }) ??
            false);

    // A newly joined Windows device has received the account identity but has
    // never created its permanent Syncthing folder, so auto-start is not set
    // yet. Force that first preparation only when a known remote transport
    // exists; after pairing succeeds the transport records auto-start normally.
    if (_syncPaused) {
      unawaited(_keepPreparedFolderPaused());
    } else {
      unawaited(_prepareTransport(force: needsFirstTransportBootstrap));
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_disposed || _pollQueued) return;
      _pollQueued = true;
      unawaited(() async {
        try {
          await _enqueue<void>(() async {
            await _reconcileFromSyncDirectory(seedMissing: false);
            await _refreshTransportStatus();
          });
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
    return _enqueue(() async {
      if (_syncPaused) return;
      await _prepareTransport(force: true);
    });
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

  Future<void> bootstrapPeerTransport({
    required String deviceId,
    required String name,
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
      await _bridge.pairDevice(
        accountId: accountId,
        deviceId: remoteId,
        name: remoteName,
      );
      await _refreshTransportStatus();
    });
  }

  Future<void> refreshNow() {
    return _enqueue(() async {
      if (!_transportPrepared) {
        await _prepareTransport(force: true);
      }
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
      await accountStore.revokeDevice(appDeviceId);
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
      _lastError = '同步核心启动失败：$error';
    }
    if (!_disposed) notifyListeners();
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

  Future<void> _refreshTransportStatus() async {
    try {
      _transportStatus = await _bridge.status(accountId: accountId);
      if (_transportStatus.error != null) {
        _lastError = _transportStatus.error;
      }

      final ownTransportId = _transportStatus.deviceId?.trim();
      if (ownTransportId != null && ownTransportId.isNotEmpty) {
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
    if (_disposed || _applyingRemote || _applyingAccount) return;

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

  Future<void> _reconcileFromSyncDirectory({required bool seedMissing}) async {
    if (_disposed) return;

    // The poller and the 220 ms local debounce share the same queue. Flush
    // entity changes before reading remote records so an already-queued poll
    // cannot apply an older disk snapshot over a just-edited store.
    _changeDebounce?.cancel();
    await _syncAccountState();
    await _flushLocalEntityChanges();
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

    if (seedMissing) {
      final localEntities = _captureEntities();
      for (final kind in SyncEntityKind.values) {
        await _seedMissing(
          kind: kind,
          local: localEntities[kind]!,
          records: recordsByKind[kind]!,
        );
      }
    }

    _applyingRemote = true;
    try {
      for (final kind in SyncEntityKind.values) {
        await _applyEntityRecords(kind, recordsByKind[kind]!);
      }
    } finally {
      _applyingRemote = false;
    }

    _lastEntityValues = _captureEntities();
    for (final kind in SyncEntityKind.values) {
      _lastFlushedRecords[kind] = recordsByKind[kind]!;
    }
    _hasRestoredSyncBaseline = false;
    _conflicts = _collectConflicts(recordsByKind);
    _lastSuccessfulSyncAt = DateTime.now();
    _lastError = null;
    if (!_disposed) notifyListeners();
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
      if (activeTransportIds.contains(transportId)) {
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
    if (settings == null || syncJsonEquals(settings, local)) return;

    try {
      await applySettings(settings);
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

  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> _captureEntities() {
    return <SyncEntityKind, Map<String, Map<String, dynamic>>>{
      SyncEntityKind.order: _captureOrders(),
      SyncEntityKind.product: _captureProducts(),
      SyncEntityKind.nodePreset: _capturePresets(),
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

  void _enqueueBackground(Future<void> Function() action) {
    if (_disposed || _removingLocalAccount) return;
    unawaited(
      _enqueue(action).catchError((Object _, StackTrace __) {
        // Background work reports through lastError; do not surface an
        // unhandled Future error into the Flutter zone.
      }),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail
        .then<void>((_) async {
          if (_disposed) {
            if (!completer.isCompleted) {
              completer.completeError(StateError('同步协调器已关闭。'));
            }
            return;
          }
          _syncBusy = true;
          if (!_disposed) notifyListeners();
          try {
            final result = await action();
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            _lastError = error.toString();
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          } finally {
            _syncBusy = false;
            if (!_disposed) notifyListeners();
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
    }
    super.dispose();
  }
}
