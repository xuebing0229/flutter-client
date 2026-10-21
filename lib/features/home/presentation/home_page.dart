import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/account/account_models.dart';
import '../../../core/account/account_store.dart';
import '../../../core/changelog/adventurer_news.dart';
import '../../../core/desktop_pet/desktop_pet_service.dart';
import '../../../core/features/app_feature_store.dart';
import '../../../core/finance/pricing_preset_store.dart';
import '../../../core/notifications/order_deadline_reminder_service.dart';
import '../../../core/onboarding/interaction_hint_store.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/storage/app_data_persistence.dart';
import '../../../core/sync/public_peer_sync_service.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/theme/app_ui_style.dart';
import '../../../core/theme/guild_visual_theme.dart';
import '../../account/presentation/account_page.dart';
import '../../imports/presentation/screenshot_import_page.dart';
import '../../focus/state/focus_store.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/data/order_reference_image_store.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/presentation/add_order_page.dart';
import '../../orders/presentation/node_preset_page.dart';
import '../../orders/presentation/order_detail_page.dart';
import '../../orders/presentation/order_queue_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/presentation/add_product_page.dart';
import '../../products/presentation/product_page.dart';
import '../../products/state/product_store.dart';
import '../../schedule/presentation/schedule_page.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../shared/domain/receipt_style_store.dart';
import '../../shared/presentation/pricing_preset_page.dart';
import '../../sync/presentation/device_sync_page.dart';
import 'abstract_mode_guide.dart';
import 'adventurer_news_dialog.dart';
import 'app_drawer.dart';
import 'archive_page.dart';
import 'desktop_pet_page.dart';
import 'feature_toggle_page.dart';
import 'feedback_page.dart';
import 'first_run_guide.dart';
import 'reminder_background_guide.dart';
import 'settings_page.dart';
import 'theme_color_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.accountId,
    this.newsStore = const AdventurerNewsStore(),
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    super.key,
  });

  final String accountId;
  final AdventurerNewsStore newsStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final OrderStore _orderStore = OrderStore();
  final ProductStore _productStore = ProductStore();
  final NodePresetStore _nodePresetStore = NodePresetStore();
  final PricingPresetStore _pricingPresetStore = PricingPresetStore();
  final ReceiptStyleStore _receiptStyleStore = ReceiptStyleStore();
  final FocusStore _focusStore = FocusStore();
  final OrderReferenceImageStore _referenceImageStore =
      OrderReferenceImageStore();
  final AppDataPersistence _persistence = const AppDataPersistence();
  final OrderDeadlineReminderService _reminderService =
      const OrderDeadlineReminderService();
  final InteractionHintStore _hintStore = const InteractionHintStore();
  final DesktopPetService _desktopPetService = DesktopPetService();
  late final DesktopPetAccountSync _desktopPetAccountSync;
  late final SyncCoordinator _syncCoordinator;
  PublicPeerSyncService? _publicPeerSync;

  static const _orderCardViewSettingKey = 'orderCardView';
  static const _orderOverviewViewSettingKey = 'orderOverviewView';
  static const _orderOverviewCardWidthSettingKey = 'orderOverviewCardWidth';
  static const _productCardViewSettingKey = 'productCardView';
  static const _pricingPresetsSettingKey = 'pricingAdjustmentPresets';
  static const _receiptStyleSettingKey = 'receiptStyle';
  static const _orderSortModeSettingKey = 'orderSortMode';
  static const _productSortModeSettingKey = 'productSortMode';
  static const _desktopNavigationOpenSettingKey = 'desktopNavigationOpen';
  static const _featureSettingPrefix = 'feature.';

  int _index = 0;
  bool _ready = false;
  bool _orderCardView = false;
  bool _orderOverviewView = false;
  double _orderOverviewCardWidth = 150;
  bool _productCardView = false;
  String _orderSortMode = 'defaultOrder';
  String _productSortMode = 'defaultOrder';
  bool _desktopNavigationOpen = true;
  String? _desktopToolSelection;
  GlobalKey<NavigatorState> _desktopContentNavigatorKey =
      GlobalKey<NavigatorState>();
  late _DesktopContentNavigatorObserver _desktopContentNavigatorObserver;
  bool _desktopContentHasNestedRoute = false;
  bool _desktopRootRefreshPending = false;
  bool _desktopAddEditorOpen = false;
  Timer? _saveDebounce;
  Timer? _reminderDebounce;
  Timer? _focusPersistenceHeartbeat;
  Timer? _desktopPetAccountSyncDebounce;
  Timer? _desktopPetLegacySeedTimer;
  String? _focusRecoverySessionId;
  DateTime? _focusRecoveryCutoff;
  bool _saving = false;
  bool _saveAgain = false;
  bool _notificationPermissionChecked = false;
  bool _localDataHealthy = true;
  bool _abstractFeatureToggleHidden = false;
  bool _abstractGuidePromptVisible = false;
  bool _lastAbstractMode = false;
  bool _newsPromptAttempted = false;
  bool _syncConflictPromptVisible = false;
  bool _syncConflictPromptedUntilClear = false;
  bool _desktopPetAccountSyncReady = false;
  bool _applyingSyncedDesktopPet = false;
  bool _leavingAccount = false;
  Map<String, dynamic>? _syncProgressOverlay;
  String? _syncProgressOverlaySignature;
  AccountSyncState? _accountSyncSnapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _desktopContentNavigatorObserver = _DesktopContentNavigatorObserver(
      _onDesktopNavigatorNestedStateChanged,
    );
    _accountSyncSnapshot = widget.accountStore.syncSnapshot;
    _lastAbstractMode = widget.featureStore.abstractMode;

    var deviceName = '本机';
    final currentDeviceId = widget.accountStore.currentDeviceId!;
    for (final device in widget.accountStore.activeDevices) {
      if (device.id == currentDeviceId) {
        deviceName = device.name;
        break;
      }
    }
    _desktopPetService.settings.bindAccount(widget.accountId);
    _desktopPetAccountSync = DesktopPetAccountSync(
      settings: _desktopPetService.settings,
    );
    _syncCoordinator = SyncCoordinator(
      accountId: widget.accountId,
      deviceId: currentDeviceId,
      deviceName: deviceName,
      accountStore: widget.accountStore,
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      focusStore: _focusStore,
      captureSettings: _captureSyncSettings,
      applySettings: _applySyncSettings,
    );
    _syncCoordinator.addListener(_onSyncCoordinatorChanged);

    widget.themeStore.addListener(_onThemeSettingsChanged);
    widget.featureStore.addListener(_onFeatureSettingsChanged);
    widget.accountStore.addListener(_onAccountStoreChanged);
    if (Platform.isWindows) {
      _desktopPetService.settings.addListener(_onDesktopPetSettingsChanged);
    }
    _restoreLocalData();
  }

  Future<void> _restoreLocalData() async {
    String? errorMessage;
    var isNewAccount = false;
    var bootstrapOnly = false;
    var hasWorkspaceSettings = false;
    var consumedPortableSyncHistory = false;
    var hadDesktopPetConfigBeforeSync = false;

    try {
      if (Platform.isWindows) {
        hadDesktopPetConfigBeforeSync =
            await _desktopPetService.settings.hasLocalConfigFile();
        await _desktopPetService.settings.load();
      }
      final backup = await _persistence.load(accountId: widget.accountId);
      isNewAccount = backup == null;
      bootstrapOnly = backup?.settings['bootstrapOnly'] == true;
      hasWorkspaceSettings =
          backup != null &&
          !bootstrapOnly &&
          (backup.settings.containsKey('themeMode') ||
              backup.settings.containsKey('uiStyle') ||
              backup.settings.containsKey('uiTexture') ||
              backup.settings.containsKey('features') ||
              backup.settings.keys.any(
                (key) => key.startsWith(_featureSettingPrefix),
              ));
      if (backup != null) {
        _syncCoordinator.restoreSyncBaseline(
          backup.settings['syncBaselineRecords'],
        );
        final portableHistory = backup.syncRecords;
        if (portableHistory != null) {
          await _syncCoordinator.restorePortableBackupBeforeInitialize(backup);
          consumedPortableSyncHistory = true;
        }

        backup.restoreInto(
          orderStore: _orderStore,
          productStore: _productStore,
          nodePresetStore: _nodePresetStore,
          focusStore: _focusStore,
        );
        final restoredActiveFocus = _focusStore.activeSession;
        if (restoredActiveFocus != null) {
          _focusRecoverySessionId = restoredActiveFocus.id;
          final foregroundExit = await _persistence.loadFocusForegroundExit(
            accountId: widget.accountId,
          );
          _focusRecoveryCutoff = foregroundExit ?? backup.exportedAt;
        }

        // A bootstrap-only package deliberately contains account identity but no
        // workspace settings. Do not treat it as authoritative local state.
        if (hasWorkspaceSettings) {
          // Theme, feature switches and layout belong to the account workspace.
          // Restore all of them before sync starts so switching accounts cannot
          // leak the previous account's in-memory settings into this one.
          await _applySyncSettings(backup.settings);
        }

        if (backup.accountSyncState != null) {
          await widget.accountStore.mergeSyncedState(backup.accountSyncState!);
        }
      }
    } catch (error) {
      _localDataHealthy = false;
      _nodePresetStore.replaceAll(const <NodePreset>[defaultNodePreset]);
      errorMessage = '本地数据读取失败：$error';
    }

    _orderStore.addListener(_onOrderStoreChanged);
    _productStore.addListener(_scheduleSave);
    _nodePresetStore.addListener(_scheduleSave);
    _pricingPresetStore.addListener(_onSharedWorkspaceSettingChanged);
    _receiptStyleStore.addListener(_onSharedWorkspaceSettingChanged);
    _focusStore.addListener(_onFocusStoreChanged);
    _refreshFocusPersistenceHeartbeat();

    if (_localDataHealthy) {
      if (!hasWorkspaceSettings) {
        await widget.themeStore.resetToDefaults();
        await widget.featureStore.resetToDefaults();
      }
      await _syncCoordinator.initialize(
        seedLocalWorkspace: !bootstrapOnly,
        seedLocalSettings:
            !bootstrapOnly && (hasWorkspaceSettings || isNewAccount),
      );
      _startPublicPeerSync();
      if (Platform.isWindows) {
        _applyingSyncedDesktopPet = true;
        try {
          // Pull an already-synced desktop-pet workspace first. Never let a
          // clean/reinstalled PC publish its empty runtime config over the
          // copy that a phone is relaying.
          await _desktopPetAccountSync.reconcile(widget.accountId);
        } catch (_) {
          // The auxiliary manifest/assets can still be arriving from another
          // device. Normal sync notifications retry without blocking work data.
        } finally {
          _applyingSyncedDesktopPet = false;
        }
        _desktopPetAccountSyncReady = true;

        // v171 and earlier kept desktop-pet data only on Windows. Give an
        // existing remote workspace a short chance to arrive before seeding
        // this legacy local copy for the first time.
        if (hadDesktopPetConfigBeforeSync &&
            _desktopPetService.settings.accountSyncRevision == null) {
          _desktopPetLegacySeedTimer = Timer(
            const Duration(seconds: 8),
            () => unawaited(_reconcileDesktopPetAccountSync(
              seedLocalIfMissing: true,
            )),
          );
        }
      }
      if (consumedPortableSyncHistory) {
        // The portable history is a one-time handoff. Persist the materialized
        // workspace again without embedding it, otherwise every launch would
        // roll the live sync directory back to the transfer snapshot.
        await _persistCurrentData();
      }
    }

    if (!mounted) return;

    setState(() => _ready = true);
    _onSyncCoordinatorChanged();
    unawaited(_syncReminders());
    unawaited(_syncDesktopPet());
    if (_focusRecoverySessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showFocusRecoveryIfNeeded());
      });
    }

    if (errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage!),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    } else if (isNewAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showFirstRunGuideOnce());
      });
    }

    if (errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showAdventurerNewsOnce());
      });
    }
  }

  Future<void> _showAdventurerNewsOnce() async {
    if (_newsPromptAttempted || !mounted) return;
    _newsPromptAttempted = true;
    try {
      final notice = await widget.newsStore.pending();
      if (!mounted || notice == null) return;
      final acknowledged = await showAdventurerNewsDialog(
        context,
        notice: notice,
      );
      if (acknowledged) {
        await widget.newsStore.acknowledge(notice.currentBuild);
      }
    } catch (_) {
      // A changelog popup must never break or overwrite work data.
    }
  }

  Future<void> _showFirstRunGuideOnce() async {
    if (await _hintStore.hasSeenFirstRunGuide(widget.accountId)) return;
    if (!mounted) return;

    await _hintStore.markFirstRunGuideSeen(widget.accountId);
    if (!mounted) return;
    await showFirstRunGuide(context);
  }

  Future<void> _showTutorial() async {
    if (!mounted) return;
    if (widget.featureStore.abstractMode) {
      await showAbstractModeGuide(context);
    } else {
      await showFirstRunGuide(context, detailed: true);
    }
  }

  Future<void> _showAbstractModeGuideOnce() async {
    if (_abstractGuidePromptVisible || !mounted) return;
    if (await _hintStore.hasSeenAbstractModeGuide(widget.accountId)) return;
    if (!mounted || !widget.featureStore.abstractMode) return;

    _abstractGuidePromptVisible = true;
    try {
      await showAbstractModeGuide(context, forced: true);
      await _hintStore.markAbstractModeGuideSeen(widget.accountId);
    } finally {
      _abstractGuidePromptVisible = false;
    }
  }

  void _hideFeatureToggleForAbstractSession() {
    if (!mounted ||
        !widget.featureStore.abstractMode ||
        !widget.featureStore.abstractEffects) {
      return;
    }
    setState(() {
      _abstractFeatureToggleHidden = true;
      if (_desktopToolSelection == AppToolMenu.featureToggleTool) {
        _desktopToolSelection = null;
        _replaceDesktopContentNavigator();
      }
    });
  }

  void _onOrderStoreChanged() {
    _scheduleSave();
    _scheduleReminderSync();
    if (_ready) {
      unawaited(_syncDesktopPet());
    }
  }

  void _onAccountStoreChanged() {
    final snapshot = widget.accountStore.syncSnapshot;
    if (widget.accountStore.status != AccountStatus.unlocked ||
        snapshot?.accountId != widget.accountId) {
      if (!_leavingAccount && Platform.isWindows) {
        _leavingAccount = true;
        _desktopPetAccountSyncDebounce?.cancel();
        _desktopPetLegacySeedTimer?.cancel();
        unawaited(_desktopPetService.stopForAccountExit());
      }
      return;
    }
    _accountSyncSnapshot = snapshot;
    _scheduleSave();
    _publicPeerSync?.requestSync();
  }

  void _startPublicPeerSync() {
    if (_publicPeerSync != null) return;
    final currentDeviceId = widget.accountStore.currentDeviceId;
    final state = widget.accountStore.syncSnapshot;
    if (currentDeviceId == null || state == null) return;

    final service = PublicPeerSyncService(
      accountId: widget.accountId,
      deviceId: currentDeviceId,
      captureAccountState: () =>
          widget.accountStore.syncSnapshot ?? state,
      mergeAccountState: widget.accountStore.mergeSyncedState,
      exportRecords: _syncCoordinator.exportPeerRecords,
      mergeRecords: _syncCoordinator.mergePeerRecords,
      captureAssetPaths: () => <String>{
        for (final order in _orderStore.orders)
          for (final image in order.referenceImages) image.relativePath,
        for (final product in _productStore.products)
          for (final image in product.referenceImages) image.relativePath,
      },
      assetExists: (path) async =>
          (await _referenceImageStore.readAssetBytes(
            accountId: widget.accountId,
            relativePath: path,
          )) !=
          null,
      readAsset: (path) => _referenceImageStore.readAssetBytes(
        accountId: widget.accountId,
        relativePath: path,
      ),
      writeAsset: (path, bytes) => _referenceImageStore.writeAssetBytes(
        accountId: widget.accountId,
        relativePath: path,
        bytes: bytes,
      ),
    );
    _publicPeerSync = service;
    unawaited(service.start());
  }

  Map<String, dynamic>? _activeSyncProgress(
    Map<String, dynamic>? progress,
  ) {
    if (progress == null) return null;
    final completion = ((progress['completion'] as num?)?.toDouble() ?? 100)
        .clamp(0, 100)
        .toDouble();
    final globalBytes = (progress['globalBytes'] as num?)?.toInt() ?? 0;
    final needBytes = (progress['needBytes'] as num?)?.toInt() ?? 0;
    final globalItems = (progress['globalItems'] as num?)?.toInt() ?? 0;
    final needItems = (progress['needItems'] as num?)?.toInt() ?? 0;
    final hasData = globalBytes > 0 || globalItems > 0;
    final unfinished = completion < 99.95 || needBytes > 0 || needItems > 0;
    if (!hasData || !unfinished) return null;
    return Map<String, dynamic>.from(progress);
  }

  String? _syncProgressSignature(Map<String, dynamic>? progress) {
    if (progress == null) return null;
    final completion = ((progress['completion'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100)
        .toDouble();
    return <Object?>[
      completion.toStringAsFixed(1),
      progress['needBytes'],
      progress['needItems'],
      progress['direction'],
      progress['deviceName'],
      progress['remoteState'],
    ].join('|');
  }

  void _onSyncCoordinatorChanged() {
    if (!mounted || !_ready) return;

    final transportStatus = _syncCoordinator.transportStatus;
    final nextProgress = transportStatus.connectedDeviceIds.isEmpty
        ? null
        : _activeSyncProgress(transportStatus.syncProgress);
    final nextSignature = _syncProgressSignature(nextProgress);
    if (nextSignature != _syncProgressOverlaySignature) {
      setState(() {
        _syncProgressOverlay = nextProgress;
        _syncProgressOverlaySignature = nextSignature;
      });
    }

    if (Platform.isWindows && _desktopPetAccountSyncReady) {
      _scheduleDesktopPetAccountReconcile();
    }

    final conflicts = _syncCoordinator.conflicts;
    if (conflicts.isEmpty) {
      _syncConflictPromptedUntilClear = false;
      return;
    }

    // One conflict batch gets one interruption. Resolving one item changes the
    // conflict list, but must not pop the same modal again for every remaining
    // item. The latch resets only after the batch is fully cleared.
    if (_syncConflictPromptVisible || _syncConflictPromptedUntilClear) {
      return;
    }

    _syncConflictPromptedUntilClear = true;
    _syncConflictPromptVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _syncConflictPromptVisible = false;
        return;
      }
      unawaited(_showSyncConflictPrompt());
    });
  }

  void _onDesktopPetSettingsChanged() {
    if (!Platform.isWindows ||
        !_ready ||
        !_desktopPetAccountSyncReady ||
        _applyingSyncedDesktopPet) {
      return;
    }
    _desktopPetLegacySeedTimer?.cancel();
    _desktopPetAccountSyncDebounce?.cancel();
    _desktopPetAccountSyncDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_publishDesktopPetAccountSync()),
    );
  }

  void _scheduleDesktopPetAccountReconcile() {
    if (!Platform.isWindows ||
        !_ready ||
        !_desktopPetAccountSyncReady ||
        _applyingSyncedDesktopPet) {
      return;
    }
    _desktopPetAccountSyncDebounce?.cancel();
    _desktopPetAccountSyncDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_reconcileDesktopPetAccountSync()),
    );
  }

  Future<void> _publishDesktopPetAccountSync() async {
    if (!Platform.isWindows || !_desktopPetAccountSyncReady) return;
    try {
      await _desktopPetAccountSync.publish(widget.accountId);
    } catch (_) {
      // Desktop-pet account sync is supplementary; the shared workspace keeps
      // retrying through normal Syncthing scans and future local changes.
    }
  }

  Future<void> _reconcileDesktopPetAccountSync({
    bool seedLocalIfMissing = false,
  }) async {
    if (!Platform.isWindows ||
        !_desktopPetAccountSyncReady ||
        _applyingSyncedDesktopPet) {
      return;
    }
    _applyingSyncedDesktopPet = true;
    try {
      await _desktopPetAccountSync.reconcile(
        widget.accountId,
        seedLocalIfMissing: seedLocalIfMissing,
      );
      if (_ready && mounted) {
        await _syncDesktopPet();
      }
    } catch (_) {
      // A half-arrived auxiliary file must never block the main work data.
    } finally {
      _applyingSyncedDesktopPet = false;
    }
  }

  Future<void> _showSyncConflictPrompt() async {
    try {
      final count = _syncCoordinator.conflictCount;
      if (count == 0 || !mounted) return;

      final openSyncPage = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('发现同步冲突'),
          content: Text('检测到 $count 项数据在不同设备上被同时修改，需要你确认保留哪一版。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后处理'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('去处理'),
            ),
          ],
        ),
      );

      if (openSyncPage == true && mounted) {
        if (MediaQuery.sizeOf(context).width >= 900) {
          _selectDesktopTool(AppToolMenu.syncTool);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DeviceSyncPage(coordinator: _syncCoordinator),
            ),
          );
        }
      }
    } finally {
      _syncConflictPromptVisible = false;
    }
  }

  void _onFeatureSettingsChanged() {
    if (!mounted) return;

    final abstractMode = widget.featureStore.abstractMode;
    final enteredAbstractMode = !_lastAbstractMode && abstractMode;
    final leftAbstractMode = _lastAbstractMode && !abstractMode;
    _lastAbstractMode = abstractMode;

    if (!widget.featureStore.deadlineReminders) {
      _notificationPermissionChecked = false;
    }

    setState(() {
      _index = 0;
      if (leftAbstractMode) {
        _abstractFeatureToggleHidden = false;
      }
      final petFocusAvailable =
          (Platform.isWindows &&
              widget.featureStore.enabled(AppFeature.desktopPet)) ||
          widget.featureStore.enabled(AppFeature.focus);
      if (!petFocusAvailable &&
          _desktopToolSelection == AppToolMenu.desktopPetTool) {
        _desktopToolSelection = null;
        _replaceDesktopContentNavigator();
      } else {
        _refreshDesktopCollectionRootIfNeeded();
      }
    });

    _scheduleSave();
    _scheduleReminderSync();
    _syncCoordinator.notifySettingsChanged();
    if (_ready) {
      unawaited(_syncDesktopPet());
    }

    if (_ready && enteredAbstractMode) {
      unawaited(_showAbstractModeGuideOnce());
    }
  }

  void _onFocusStoreChanged() {
    _scheduleSave();
    _refreshFocusPersistenceHeartbeat();
    if (_ready && Platform.isWindows) {
      unawaited(_syncDesktopPet());
    }
  }

  void _refreshFocusPersistenceHeartbeat() {
    if (_focusStore.activeSession == null) {
      _focusPersistenceHeartbeat?.cancel();
      _focusPersistenceHeartbeat = null;
      return;
    }
    _focusPersistenceHeartbeat ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_ready && _localDataHealthy) {
          _scheduleSave();
        }
      },
    );
  }

  Future<void> _showFocusRecoveryIfNeeded() async {
    final sessionId = _focusRecoverySessionId;
    final cutoff = _focusRecoveryCutoff;
    _focusRecoverySessionId = null;
    _focusRecoveryCutoff = null;
    if (sessionId == null || cutoff == null || !mounted) return;

    final active = _focusStore.activeSession;
    if (active == null || active.id != sessionId) return;

    String two(int value) => value.toString().padLeft(2, '0');
    final local = cutoff.toLocal();
    final cutoffText =
        '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现未结束的专注'),
        content: Text(
          '上次离开公会时，这次专注还在计时。'
          '你可以继续计时、按上次离开时间（$cutoffText）结束，或作废这次记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('作废本次'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('end'),
            child: const Text('按离开时间结束'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('continue'),
            child: const Text('继续计时'),
          ),
        ],
      ),
    );

    final current = _focusStore.activeSession;
    if (current == null || current.id != sessionId) return;
    if (action == 'end') {
      _focusStore.stopActiveAt(cutoff);
    } else if (action == 'discard') {
      _focusStore.discardActive();
    }
  }

  Future<QueueOrder?> _currentDesktopPetOrder() async {
    await _desktopPetService.settings.load();
    final selectedOrderId = _desktopPetService.settings.currentOrderId;
    if (selectedOrderId == null || selectedOrderId.isEmpty) return null;

    for (final order in _orderStore.orders) {
      if (order.id == selectedOrderId &&
          !order.isArchived &&
          !order.isCompleted) {
        return order;
      }
    }

    // The selected order may have been completed, archived, or deleted.
    // Clear the local-only selection instead of silently switching to
    // another order.
    await _desktopPetService.settings.clearCurrentOrderSelection();
    return null;
  }

  Color _desktopPetOnColor(Color color) {
    return color.computeLuminance() > 0.48 ? Colors.black : Colors.white;
  }

  ColorScheme _desktopPetColorScheme() {
    final brightness = switch (widget.themeStore.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    final palette = widget.themeStore.palette;
    final colors = palette.previewColors;
    final primary = colors.first;
    final secondary = colors.length > 1 ? colors[1] : primary;
    final tertiary = colors.length > 2 ? colors[2] : secondary;
    final primaryContainer = colors.length > 3 ? colors[3] : primary;
    final secondaryContainer = colors.length > 4 ? colors[4] : secondary;
    final tertiaryContainer = colors.length > 2 ? colors.last : primary;
    final base = ColorScheme.fromSeed(
      seedColor: brightness == Brightness.dark
          ? palette.effectiveDarkSeed
          : palette.lightSeed,
      brightness: brightness,
    );

    return base.copyWith(
      primary: primary,
      onPrimary: _desktopPetOnColor(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: _desktopPetOnColor(primaryContainer),
      secondary: secondary,
      onSecondary: _desktopPetOnColor(secondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _desktopPetOnColor(secondaryContainer),
      tertiary: tertiary,
      onTertiary: _desktopPetOnColor(tertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _desktopPetOnColor(tertiaryContainer),
      surface: base.surface,
      onSurface: base.onSurface,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurfaceVariant: base.onSurfaceVariant,
      outline: base.outline,
      outlineVariant: base.outlineVariant,
      inversePrimary: primary,
      surfaceTint: Colors.transparent,
    );
  }

  Future<void> _syncDesktopPet() async {
    if (!Platform.isWindows || _leavingAccount) return;
    try {
      final order = await _currentDesktopPetOrder();
      if (!mounted) return;
      final colors = _desktopPetColorScheme();
      await _desktopPetService.sync(
        enabled: widget.featureStore.enabled(AppFeature.desktopPet),
        currentOrderTitle: order?.title,
        currentOrderNode: order?.currentNode.name,
        currentOrderDeadline: order?.deadline,
        bubbleBackgroundArgb: colors.surfaceContainerHigh.toARGB32(),
        bubbleForegroundArgb: colors.onSurface.toARGB32(),
        bubbleBorderArgb: colors.outlineVariant.toARGB32(),
        bubbleAccentArgb: colors.primary.toARGB32(),
        focusEnabled: widget.featureStore.enabled(AppFeature.focus),
        focusStartedAt: widget.featureStore.enabled(AppFeature.focus)
            ? _focusStore.activeSession?.startedAt
            : null,
      );
    } catch (_) {
      // Desktop pet is optional. A host/config failure must not bubble into
      // the main Guild UI zone or interrupt order/focus editing.
    }
  }

  void _onThemeSettingsChanged() {
    if (!mounted) return;
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
    if (_ready) {
      unawaited(_syncDesktopPet());
    }
  }

  void _onSharedWorkspaceSettingChanged() {
    if (!mounted) return;
    _scheduleSave();
    if (_ready) {
      _syncCoordinator.notifySettingsChanged();
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (!_ready || !mounted) return;
    if (widget.themeStore.mode == ThemeMode.system) {
      unawaited(_syncDesktopPet());
    }
  }

  Map<String, dynamic> _captureSyncSettings() {
    final features = widget.featureStore.toJson();
    return <String, dynamic>{
      'id': SyncCoordinator.settingsRecordId,
      'themeMode': widget.themeStore.mode.name,
      'themePaletteId': widget.themeStore.paletteId,
      'customThemePalettes': widget.themeStore.exportCustomPalettes(),
      'uiStyle': widget.themeStore.style.id,
      for (final entry in features.entries)
        '$_featureSettingPrefix${entry.key}': entry.value,
      _orderCardViewSettingKey: _orderCardView,
      _orderOverviewViewSettingKey: _orderOverviewView,
      _orderOverviewCardWidthSettingKey: _orderOverviewCardWidth,
      _productCardViewSettingKey: _productCardView,
      _pricingPresetsSettingKey: _pricingPresetStore.toJson(),
      _receiptStyleSettingKey: _receiptStyleStore.toJson(),
      _orderSortModeSettingKey: _orderSortMode,
      _productSortModeSettingKey: _productSortMode,
      _desktopNavigationOpenSettingKey: _desktopNavigationOpen,
    };
  }

  Future<void> _applySyncSettings(Map<String, dynamic> settings) async {
    final modeName = settings['themeMode'];
    if (modeName is String) {
      final mode = switch (modeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => throw const FormatException('同步主题模式无效。'),
      };
      await widget.themeStore.setMode(mode);
    }

    if (settings.containsKey('customThemePalettes')) {
      await widget.themeStore.replaceCustomPalettesFromJson(
        settings['customThemePalettes'],
      );
    }

    final paletteId = settings['themePaletteId'];
    if (paletteId is String) {
      if (widget.themeStore.containsPaletteId(paletteId)) {
        await widget.themeStore.setPaletteId(paletteId);
      } else if (paletteId.startsWith('custom:')) {
        // A UI preference must never make otherwise valid work data
        // unreadable. Build 154 could persist a selected custom palette ID
        // into workspace settings without embedding the custom palette itself.
        // If that old preset is unavailable, keep/fall back to a valid local
        // palette and continue restoring orders/products normally.
        await widget.themeStore.setPaletteId(
          AppThemePalettes.guildOriginal.id,
        );
      } else {
        await widget.themeStore.setPaletteId(
          AppThemePalettes.guildOriginal.id,
        );
      }
    } else if (paletteId != null) {
      await widget.themeStore.setPaletteId(
        AppThemePalettes.guildOriginal.id,
      );
    }

    final styleId = settings['uiStyle'];
    if (styleId is String && AppUiStyle.containsId(styleId)) {
      await widget.themeStore.setStyle(AppUiStyle.byId(styleId));
    } else if (styleId == null) {
      final legacyTextureId = settings['uiTexture'];
      if (legacyTextureId == null) {
        await widget.themeStore.setStyle(AppUiStyle.classic);
      } else if (legacyTextureId is String) {
        await widget.themeStore.setStyle(
          AppUiStyle.fromLegacyTextureId(legacyTextureId),
        );
      } else {
        throw const FormatException('同步 UI 风格设置无效。');
      }
    } else {
      throw const FormatException('同步 UI 风格设置无效。');
    }

    // New settings records keep each feature as its own CRDT field so two
    // devices can toggle different switches without manufacturing a conflict.
    // Accept the old aggregate map when importing an earlier local backup.
    final legacyFeatures = settings['features'];
    if (legacyFeatures is Map) {
      await widget.featureStore.applyJson(legacyFeatures);
    } else if (legacyFeatures != null) {
      throw const FormatException('同步功能开关设置无效。');
    }

    final nextFeatures = widget.featureStore.toJson();
    var hasFeatureFields = false;
    for (final feature in AppFeature.values) {
      final key = '$_featureSettingPrefix${feature.name}';
      if (!settings.containsKey(key)) continue;
      final value = settings[key];
      if (value is! bool) {
        throw FormatException('同步功能开关 ${feature.name} 格式无效。');
      }
      nextFeatures[feature.name] = value;
      hasFeatureFields = true;
    }
    if (hasFeatureFields) {
      await widget.featureStore.applyJson(nextFeatures);
    }

    if (settings.containsKey(_pricingPresetsSettingKey)) {
      _pricingPresetStore.applyJson(settings[_pricingPresetsSettingKey]);
    }
    if (settings.containsKey(_receiptStyleSettingKey)) {
      _receiptStyleStore.applyJson(settings[_receiptStyleSettingKey]);
    }

    var layoutChanged = false;
    final nextOrderCardView = settings[_orderCardViewSettingKey];
    if (nextOrderCardView is bool && nextOrderCardView != _orderCardView) {
      _orderCardView = nextOrderCardView;
      layoutChanged = true;
    }
    final nextOverviewView = settings[_orderOverviewViewSettingKey];
    if (nextOverviewView is bool && nextOverviewView != _orderOverviewView) {
      _orderOverviewView = nextOverviewView;
      layoutChanged = true;
    }
    final nextOverviewWidth = settings[_orderOverviewCardWidthSettingKey];
    if (nextOverviewWidth is num && nextOverviewWidth.isFinite) {
      final normalized = nextOverviewWidth.toDouble().clamp(72, 280).toDouble();
      if (normalized != _orderOverviewCardWidth) {
        _orderOverviewCardWidth = normalized;
        layoutChanged = true;
      }
    } else if (nextOverviewWidth != null) {
      throw const FormatException('同步总概览卡片大小格式无效。');
    }
    final nextProductCardView = settings[_productCardViewSettingKey];
    if (nextProductCardView is bool &&
        nextProductCardView != _productCardView) {
      _productCardView = nextProductCardView;
      layoutChanged = true;
    }
    final nextOrderSortMode = _normalizeOrderSortMode(
      settings[_orderSortModeSettingKey],
    );
    if (nextOrderSortMode != null && nextOrderSortMode != _orderSortMode) {
      _orderSortMode = nextOrderSortMode;
      layoutChanged = true;
    }
    final nextProductSortMode = settings[_productSortModeSettingKey];
    if (nextProductSortMode is String &&
        const <String>{
          'defaultOrder',
          'income',
          'soldCount',
        }.contains(nextProductSortMode) &&
        nextProductSortMode != _productSortMode) {
      _productSortMode = nextProductSortMode;
      layoutChanged = true;
    }
    final nextNavigationOpen = settings[_desktopNavigationOpenSettingKey];
    if (nextNavigationOpen is bool &&
        nextNavigationOpen != _desktopNavigationOpen) {
      _desktopNavigationOpen = nextNavigationOpen;
      layoutChanged = true;
    }

    if (layoutChanged && mounted) {
      setState(() {
        _refreshDesktopCollectionRootIfNeeded();
      });
      _scheduleSave();
    }
  }

  String? _normalizeOrderSortMode(Object? value) {
    if (value is! String) return null;
    return switch (value) {
      'defaultOrder' => 'defaultOrder',
      'income' => 'income',
      'deadline' || 'remainingTime' => 'deadline',
      _ => null,
    };
  }

  void _scheduleSave() {
    if (!_ready || !_localDataHealthy) return;

    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 350),
      _persistCurrentData,
    );
    _publicPeerSync?.requestSync();
  }

  void _scheduleReminderSync() {
    if (!_ready) return;

    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_syncReminders()),
    );
  }

  bool get _ownsCurrentAccountSession =>
      widget.accountStore.isUnlocked &&
      widget.accountStore.accountId == widget.accountId;

  Future<void> _syncReminders() async {
    if (!Platform.isAndroid) return;
    if (!_ownsCurrentAccountSession) return;

    if (!_localDataHealthy) {
      try {
        await _reminderService.clearAll(accountId: widget.accountId);
      } catch (_) {}
      return;
    }

    try {
      final hasActiveDeadline = _orderStore.orders.any(
        (order) =>
            !order.isArchived && !order.isCompleted && order.deadline != null,
      );

      if (!widget.featureStore.deadlineReminders) {
        await _reminderService.clearAll(accountId: widget.accountId);
        return;
      }

      if (hasActiveDeadline && !_notificationPermissionChecked) {
        _notificationPermissionChecked = true;
        final granted = await _reminderService.ensurePermission();
        if (!_ownsCurrentAccountSession) return;
        if (granted && mounted) {
          await showReminderBackgroundGuide(
            context: context,
            reminderService: _reminderService,
          );
          if (!_ownsCurrentAccountSession) return;
        }
      }

      if (!_ownsCurrentAccountSession) return;
      await _reminderService.syncOrders(
        accountId: widget.accountId,
        orders: _orderStore.orders,
      );
    } catch (_) {
      // Reminder failures must never block local order data.
    }
  }

  Future<void> _persistCurrentData() async {
    if (!_localDataHealthy) return;

    if (_saving) {
      _saveAgain = true;
      return;
    }

    _saving = true;
    try {
      do {
        _saveAgain = false;
        final backup = _captureCurrentBackup();
        await _persistence.save(backup, accountId: widget.accountId);
      } while (_saveAgain);
    } finally {
      _saving = false;
    }
  }

  Future<void> _flushSyncThenPersist() async {
    try {
      await _syncCoordinator.flushNow();
    } catch (_) {
      // A local backup is still more useful than dropping it because the
      // transport is temporarily unavailable.
    }
    await _persistCurrentData();
  }

  AppBackupData _captureCurrentBackup() {
    return AppBackupData.capture(
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      focusStore: _focusStore,
      accountSyncState: _accountSyncSnapshot,
      settings: <String, dynamic>{
        'syncBaselineRecords': _syncCoordinator.syncBaselineSettings,
        ..._captureSyncSettings(),
      },
    );
  }

  // Lifecycle events can overlap: a slow disk flush from an earlier
  // background transition must never stop transport after a new resume.
  int _syncLifecycleGeneration = 0;

  Future<void> _leaveForegroundSync(int generation) async {
    _saveDebounce?.cancel();
    try {
      await _flushSyncThenPersist();
    } finally {
      if (mounted && generation == _syncLifecycleGeneration) {
        await _syncCoordinator.deactivateTransportForBackground();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready || !_localDataHealthy) return;
    if (state == AppLifecycleState.resumed) {
      ++_syncLifecycleGeneration;
      unawaited(_syncCoordinator.activateTransport());
      return;
    }
    if (state == AppLifecycleState.inactive) {
      final leftAt = DateTime.now();
      unawaited(
        _persistence.saveFocusForegroundExit(
          accountId: widget.accountId,
          value: leftAt,
        ),
      );
      _saveDebounce?.cancel();
      unawaited(_flushSyncThenPersist());
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final leftAt = DateTime.now();
      unawaited(
        _persistence.saveFocusForegroundExit(
          accountId: widget.accountId,
          value: leftAt,
        ),
      );
      unawaited(_leaveForegroundSync(++_syncLifecycleGeneration));
    }
  }

  Future<void> _prepareForSignOut() async {
    _leavingAccount = true;
    _saveDebounce?.cancel();
    _reminderDebounce?.cancel();
    _focusPersistenceHeartbeat?.cancel();
    _desktopPetAccountSyncDebounce?.cancel();
    _desktopPetLegacySeedTimer?.cancel();

    if (Platform.isWindows) {
      // Account chooser/login pages must never retain the previous account's
      // detached desktop-pet process.
      await _desktopPetService.stopForAccountExit();
    }

    if (_ready && _localDataHealthy) {
      await _flushSyncThenPersist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _reminderDebounce?.cancel();
    _focusPersistenceHeartbeat?.cancel();
    _desktopPetAccountSyncDebounce?.cancel();
    _desktopPetLegacySeedTimer?.cancel();
    if (Platform.isWindows) {
      _desktopPetService.settings.removeListener(_onDesktopPetSettingsChanged);
    }
    widget.themeStore.removeListener(_onThemeSettingsChanged);
    widget.featureStore.removeListener(_onFeatureSettingsChanged);
    widget.accountStore.removeListener(_onAccountStoreChanged);
    _syncCoordinator.removeListener(_onSyncCoordinatorChanged);
    _orderStore.removeListener(_onOrderStoreChanged);
    _productStore.removeListener(_scheduleSave);
    _nodePresetStore.removeListener(_scheduleSave);
    _focusStore.removeListener(_onFocusStoreChanged);

    // Remote revocation can dispose this page without going through the
    // explicit sign-out path. Capture and queue the final local snapshot
    // before the stores are disposed; persistence itself remains asynchronous
    // because State.dispose cannot be awaited.
    if (_ready && _localDataHealthy) {
      try {
        final backup = _captureCurrentBackup();
        unawaited(
          _persistence.save(backup, accountId: widget.accountId).catchError((
            _,
          ) {
            // Disposal must not surface a persistence failure into the UI zone.
          }),
        );
      } catch (_) {
        // Disposal must not throw if capturing the final snapshot fails.
      }
    }

    _publicPeerSync?.dispose();
    _publicPeerSync = null;
    _desktopContentNavigatorObserver.deactivate();
    _desktopPetService.dispose();
    _syncCoordinator.dispose();
    _orderStore.dispose();
    _productStore.dispose();
    _nodePresetStore.dispose();
    _focusStore.dispose();
    super.dispose();
  }

  Future<void> _chooseAddMethod({required bool products}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (dialogContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('手动导入'),
                subtitle: const Text('逐项填写订单信息'),
                onTap: () => Navigator.pop(dialogContext, 'manual'),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('截图导入'),
                subtitle: const Text('从平台截图识别多条，检查后批量添加'),
                onTap: () => Navigator.pop(dialogContext, 'screenshot'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == 'manual') {
      if (products) {
        _openAddProduct();
      } else {
        _openAddOrder();
      }
      return;
    }
    if (picked == 'screenshot') _openScreenshotImport(products: products);
  }

  void _openScreenshotImport({required bool products}) {
    final useDesktopLayout = MediaQuery.sizeOf(context).width >= 900;
    if (useDesktopLayout && _desktopAddEditorOpen) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => ScreenshotImportPage(
        accountId: widget.accountId,
        kind: products
            ? ScreenshotImportKind.products
            : ScreenshotImportKind.orders,
        orderStore: _orderStore,
        productStore: _productStore,
        presetStore: _nodePresetStore,
      ),
    );
    final desktopNavigator = useDesktopLayout
        ? _desktopContentNavigatorKey.currentState
        : null;
    if (desktopNavigator != null) {
      setState(() => _desktopAddEditorOpen = true);
      desktopNavigator.push(route).whenComplete(() {
        if (mounted) setState(() => _desktopAddEditorOpen = false);
      });
    } else {
      Navigator.of(context).push(route);
    }
  }

  void _openAddOrder() {
    FocusManager.instance.primaryFocus?.unfocus();
    final useDesktopLayout = MediaQuery.sizeOf(context).width >= 900;
    if (useDesktopLayout && _desktopAddEditorOpen) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => AddOrderPage(
        accountId: widget.accountId,
        store: _orderStore,
        nodePresetStore: _nodePresetStore,
        featureStore: widget.featureStore,
      ),
    );
    final desktopNavigator = useDesktopLayout
        ? _desktopContentNavigatorKey.currentState
        : null;
    if (desktopNavigator != null) {
      setState(() => _desktopAddEditorOpen = true);
      desktopNavigator.push(route).whenComplete(() {
        if (!mounted) return;
        setState(() => _desktopAddEditorOpen = false);
      });
      return;
    }
    Navigator.of(context).push(route);
  }

  void _openAddProduct() {
    FocusManager.instance.primaryFocus?.unfocus();
    final useDesktopLayout = MediaQuery.sizeOf(context).width >= 900;
    if (useDesktopLayout && _desktopAddEditorOpen) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => AddProductPage(
        accountId: widget.accountId,
        store: _productStore,
        featureStore: widget.featureStore,
      ),
    );
    final desktopNavigator = useDesktopLayout
        ? _desktopContentNavigatorKey.currentState
        : null;
    if (desktopNavigator != null) {
      setState(() => _desktopAddEditorOpen = true);
      desktopNavigator.push(route).whenComplete(() {
        if (!mounted) return;
        setState(() => _desktopAddEditorOpen = false);
      });
      return;
    }
    Navigator.of(context).push(route);
  }

  void _replaceDesktopContentNavigator() {
    _desktopContentNavigatorObserver.deactivate();
    _desktopContentNavigatorKey = GlobalKey<NavigatorState>();
    _desktopContentNavigatorObserver = _DesktopContentNavigatorObserver(
      _onDesktopNavigatorNestedStateChanged,
    );
    _desktopContentHasNestedRoute = false;
    _desktopRootRefreshPending = false;
  }

  void _refreshDesktopCollectionRootIfNeeded() {
    // Do not throw the user out of an open detail/editor when settings arrive
    // from the other device. Refresh the retained root as soon as they return.
    if (_desktopContentHasNestedRoute || _desktopToolSelection != null) {
      _desktopRootRefreshPending = true;
      return;
    }
    _replaceDesktopContentNavigator();
  }

  void _onDesktopNavigatorNestedStateChanged(bool hasNestedRoute) {
    if (!mounted) return;
    if (_desktopContentHasNestedRoute != hasNestedRoute) {
      setState(() => _desktopContentHasNestedRoute = hasNestedRoute);
    }
    if (!hasNestedRoute &&
        _desktopRootRefreshPending &&
        _desktopToolSelection == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _desktopContentHasNestedRoute ||
            _desktopToolSelection != null) {
          return;
        }
        setState(_replaceDesktopContentNavigator);
      });
    }
  }

  void _setOrderCardView(bool value) {
    if (_orderCardView == value) return;
    setState(() {
      _orderCardView = value;
      _refreshDesktopCollectionRootIfNeeded();
    });
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  void _setProductCardView(bool value) {
    if (_productCardView == value) return;
    setState(() {
      _productCardView = value;
      _refreshDesktopCollectionRootIfNeeded();
    });
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  void _setOrderSortMode(String value) {
    if (_orderSortMode == value) return;
    setState(() {
      _orderSortMode = value;
      _refreshDesktopCollectionRootIfNeeded();
    });
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  void _setProductSortMode(String value) {
    if (_productSortMode == value) return;
    setState(() {
      _productSortMode = value;
      _refreshDesktopCollectionRootIfNeeded();
    });
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  void _setDesktopNavigationOpen(bool value) {
    if (_desktopNavigationOpen == value) return;
    setState(() => _desktopNavigationOpen = value);
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  void _selectDesktopTab(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = value;
      _desktopToolSelection = null;
      _desktopAddEditorOpen = false;
      _replaceDesktopContentNavigator();
    });
  }

  Future<void> _openOrderFromFocus(String orderId) async {
    if (!_orderStore.contains(orderId) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          accountId: widget.accountId,
          store: _orderStore,
          orderId: orderId,
          nodePresetStore: _nodePresetStore,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  void _selectDesktopTool(String? tool) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _desktopToolSelection = tool;
      _desktopAddEditorOpen = false;
      _replaceDesktopContentNavigator();
    });
  }

  Widget _buildDesktopToolPage(String tool) {
    return switch (tool) {
      AppToolMenu.nodePresetTool => NodePresetPage(store: _nodePresetStore),
      AppToolMenu.featureToggleTool => FeatureTogglePage(
        store: widget.featureStore,
        onHideFeatureToggle: _hideFeatureToggleForAbstractSession,
      ),
      AppToolMenu.desktopPetTool => DesktopPetPage(
        orderStore: _orderStore,
        focusStore: _focusStore,
        settings: _desktopPetService.settings,
        onOpenOrder: _openOrderFromFocus,
        showDesktopPet:
            Platform.isWindows &&
            widget.featureStore.enabled(AppFeature.desktopPet),
        showFocus: widget.featureStore.enabled(AppFeature.focus),
      ),
      AppToolMenu.archiveTool => ArchivePage(
        accountId: widget.accountId,
        orderStore: _orderStore,
        productStore: _productStore,
        nodePresetStore: _nodePresetStore,
        featureStore: widget.featureStore,
        syncCoordinator: _syncCoordinator,
      ),
      AppToolMenu.syncTool => DeviceSyncPage(coordinator: _syncCoordinator),
      AppToolMenu.feedbackTool => const FeedbackPage(),
      AppToolMenu.accountTool => AccountPage(
        store: widget.accountStore,
        buildTransferPackage: () =>
            buildAccountTransferPackage(widget.accountStore),
        syncCoordinator: _syncCoordinator,
        onBeforeSignOut: _prepareForSignOut,
        onRevokeDevice: _syncCoordinator.revokeDevice,
      ),
      AppToolMenu.settingsTool => SettingsPage(
        orderStore: _orderStore,
        productStore: _productStore,
        nodePresetStore: _nodePresetStore,
        focusStore: _focusStore,
        themeStore: widget.themeStore,
        featureStore: widget.featureStore,
        desktopPetSettings: _desktopPetService.settings,
        accountStore: widget.accountStore,
        syncCoordinator: _syncCoordinator,
        onApplyWorkspaceSettings: _applySyncSettings,
        // Keep SettingsPage alive while opening the palette picker. The update
        // download state lives in SettingsPage, so replacing the whole desktop
        // tool page here would make an in-progress Windows update appear to
        // restart after changing the UI theme color.
      ),
      AppToolMenu.themeColorTool => ThemeColorPage(
        store: widget.themeStore,
        onBack: () => _selectDesktopTool(AppToolMenu.settingsTool),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildLocalDataFailure(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 56, color: colors.error),
              const SizedBox(height: 16),
              const Text(
                '本地工作数据读取失败',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '为避免用空数据覆盖已有内容，当前账号暂时不可编辑。请返回账号选择，检查本地文件或从其他设备重新加入。',
                style: TextStyle(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    unawaited(widget.accountStore.returnToAccountChooser()),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('返回账号选择'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <_HomeTab>[
      _HomeTab(
        label: '排单',
        icon: Icons.format_list_bulleted_rounded,
        selectedIcon: Icons.view_list_rounded,
        page: OrderQueuePage(
          accountId: widget.accountId,
          store: _orderStore,
          nodePresetStore: _nodePresetStore,
          featureStore: widget.featureStore,
          syncCoordinator: _syncCoordinator,
          cardView: _orderCardView,
          onCardViewChanged: _setOrderCardView,
          sortModeName: _orderSortMode,
          onSortModeChanged: _setOrderSortMode,
        ),
      ),
      if (widget.featureStore.products)
        _HomeTab(
          label: '成品',
          icon: Icons.image_outlined,
          selectedIcon: Icons.image_rounded,
          page: ProductPage(
            accountId: widget.accountId,
            store: _productStore,
            featureStore: widget.featureStore,
            syncCoordinator: _syncCoordinator,
            cardView: _productCardView,
            onCardViewChanged: _setProductCardView,
            sortModeName: _productSortMode,
            onSortModeChanged: _setProductSortMode,
          ),
        ),
      if (widget.featureStore.schedule)
        _HomeTab(
          label: '日程',
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_rounded,
          page: SchedulePage(
            accountId: widget.accountId,
            store: _orderStore,
            productStore: _productStore,
            nodePresetStore: _nodePresetStore,
            featureStore: widget.featureStore,
          ),
        ),
      if (widget.featureStore.statistics)
        _HomeTab(
          label: '统计',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
          page: StatisticsPage(store: _orderStore, productStore: _productStore),
        ),
    ];

    if (_index >= tabs.length) {
      _index = 0;
    }

    final current = tabs[_index];
    final title = switch (_desktopToolSelection) {
      AppToolMenu.nodePresetTool => '节点预设',
      AppToolMenu.featureToggleTool => '附加功能开关',
      AppToolMenu.desktopPetTool =>
        Platform.isWindows &&
                widget.featureStore.enabled(AppFeature.desktopPet)
            ? '桌宠'
            : '专注',
      AppToolMenu.archiveTool => '归档',
      AppToolMenu.syncTool => '设备同步',
      AppToolMenu.feedbackTool => '问题反馈',
      AppToolMenu.accountTool => '账号与设备',
      AppToolMenu.settingsTool => '设置',
      AppToolMenu.themeColorTool => 'UI主题色',
      _ => current.label,
    };
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = width >= 900;
    final uiStyle = GuildStyleTheme.of(context);

    final tabBody = IndexedStack(
      index: _index,
      children: [
        for (final tab in tabs)
          KeyedSubtree(key: ValueKey(tab.label), child: tab.page),
      ],
    );

    final desktopContent = Navigator(
      key: _desktopContentNavigatorKey,
      observers: <NavigatorObserver>[_desktopContentNavigatorObserver],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _desktopToolSelection == null
            ? tabBody
            : KeyedSubtree(
                key: ValueKey('desktop-tool-$_desktopToolSelection'),
                child: _buildDesktopToolPage(_desktopToolSelection!),
              ),
      ),
    );

    final scaffold = Scaffold(
      // The tab pages already reserve bottom-nav clearance. Glass keeps real
      // content behind the bottom chrome so the document-style blur can show.
      extendBody: uiStyle.isGlass && !useDesktopLayout,
      drawer: _ready && _localDataHealthy
          ? AppDrawer(
              orderStore: _orderStore,
              productStore: _productStore,
              nodePresetStore: _nodePresetStore,
              focusStore: _focusStore,
              desktopPetSettings: _desktopPetService.settings,
              onOpenOrder: _openOrderFromFocus,
              themeStore: widget.themeStore,
              featureStore: widget.featureStore,
              accountStore: widget.accountStore,
              syncCoordinator: _syncCoordinator,
              onApplyWorkspaceSettings: _applySyncSettings,
              onBeforeSignOut: _prepareForSignOut,
              onShowTutorial: () => unawaited(_showTutorial()),
              showFeatureToggle:
                  !widget.featureStore.abstractMode ||
                  !widget.featureStore.abstractEffects ||
                  !_abstractFeatureToggleHidden,
              onHideFeatureToggle: _hideFeatureToggleForAbstractSession,
            )
          : null,
      appBar: _desktopToolSelection == null
          ? AppBar(
              leading: useDesktopLayout
                  ? IconButton(
                      tooltip: _desktopNavigationOpen ? '收起主导航' : '展开主导航',
                      icon: Icon(
                        _desktopNavigationOpen
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                      ),
                      onPressed: () =>
                          _setDesktopNavigationOpen(!_desktopNavigationOpen),
                    )
                  : null,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: GuildStyleBackdrop(
        child: !_ready
          ? const Center(child: CircularProgressIndicator())
          : !_localDataHealthy
          ? _buildLocalDataFailure(context)
          : useDesktopLayout
          ? Row(
              children: [
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.centerLeft,
                    child: _desktopNavigationOpen
                        ? GuildStyledSurface(
                            role: GuildSurfaceRole.chrome,
                            backdropAvailable: false,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            child: SizedBox(
                            width: 320,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListView(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    8,
                                  ),
                                  children: [
                                    for (
                                      var index = 0;
                                      index < tabs.length;
                                      index++
                                    )
                                      AppMenuTile(
                                        icon: tabs[index].icon,
                                        selectedIcon: tabs[index].selectedIcon,
                                        title: tabs[index].label,
                                        selected:
                                            _desktopToolSelection == null &&
                                            _index == index,
                                        onTap: () => _selectDesktopTab(index),
                                      ),
                                  ],
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: AppToolMenu(
                                    orderStore: _orderStore,
                                    productStore: _productStore,
                                    nodePresetStore: _nodePresetStore,
                                    focusStore: _focusStore,
                                    desktopPetSettings:
                                        _desktopPetService.settings,
                                    onOpenOrder: _openOrderFromFocus,
                                    themeStore: widget.themeStore,
                                    featureStore: widget.featureStore,
                                    accountStore: widget.accountStore,
                                    syncCoordinator: _syncCoordinator,
                                    onApplyWorkspaceSettings:
                                        _applySyncSettings,
                                    onBeforeSignOut: _prepareForSignOut,
                                    onShowTutorial: () =>
                                        unawaited(_showTutorial()),
                                    showFeatureToggle:
                                        !widget.featureStore.abstractMode ||
                                        !widget.featureStore.abstractEffects ||
                                        !_abstractFeatureToggleHidden,
                                    onHideFeatureToggle:
                                        _hideFeatureToggleForAbstractSession,
                                    onSelectTool: _selectDesktopTool,
                                    selectedTool:
                                        _desktopToolSelection ==
                                            AppToolMenu.themeColorTool
                                        ? AppToolMenu.settingsTool
                                        : _desktopToolSelection,
                                    showTrailing: false,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: _desktopNavigationOpen ? 1 : 0,
                  child: const VerticalDivider(width: 1),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: desktopContent,
                  ),
                ),
              ],
            )
          : tabBody,
      ),
      floatingActionButton:
          !_ready ||
              !_localDataHealthy ||
              _desktopToolSelection != null ||
              (useDesktopLayout &&
                  (_desktopAddEditorOpen ||
                      _desktopContentHasNestedRoute ||
                      _desktopRootRefreshPending))
          ? null
          : switch (current.label) {
              '排单' => FloatingActionButton.extended(
                onPressed: () => unawaited(_chooseAddMethod(products: false)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增排单'),
              ),
              '成品' => FloatingActionButton.extended(
                onPressed: () => unawaited(_chooseAddMethod(products: true)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增成品'),
              ),
              _ => null,
            },
      bottomNavigationBar: !_ready || tabs.length <= 1 || useDesktopLayout
          ? null
          : GuildStyledSurface(
              role: GuildSurfaceRole.chrome,
              backdropAvailable: uiStyle.isGlass,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              child: NavigationBar(
                backgroundColor:
                    uiStyle.isClassic ? null : Colors.transparent,
                selectedIndex: _index,
                onDestinationSelected: (value) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() => _index = value);
                },
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label,
                    ),
                ],
              ),
            ),
    );

    final progress = _syncProgressOverlay;
    final showProgress =
        progress != null &&
        !(useDesktopLayout && _desktopToolSelection == AppToolMenu.syncTool);
    if (!showProgress) return scaffold;

    return Stack(
      fit: StackFit.expand,
      children: [
        scaffold,
        Positioned(
          top: useDesktopLayout ? 8 : null,
          bottom: useDesktopLayout
              ? null
              : (tabs.length > 1 ? 88 : 12),
          left: 16,
          right: 16,
          child: SafeArea(
            top: useDesktopLayout,
            bottom: !useDesktopLayout,
            child: Center(
              child: IgnorePointer(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _ForegroundSyncProgressPopup(progress: progress),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ForegroundSyncProgressPopup extends StatelessWidget {
  const _ForegroundSyncProgressPopup({required this.progress});

  final Map<String, dynamic> progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completion = ((progress['completion'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100)
        .toDouble();
    final percent = completion >= 99.95
        ? '100%'
        : '${completion.toStringAsFixed(1)}%';
    final direction = progress['direction']?.toString();
    final deviceName = progress['deviceName']?.toString().trim() ?? '';
    final remoteState = progress['remoteState']?.toString().trim();
    final repairingHandshake =
        remoteState == 'notSharing' || remoteState == 'paused';
    final peerLabel = deviceName.isEmpty ? '另一台设备' : '「$deviceName」';
    final title = repairingHandshake ? '正在修复同步通道' : '正在同步 $percent';
    final subtitle = remoteState == 'paused'
        ? '$peerLabel 已连接，但同步目录处于暂停状态，正在恢复'
        : remoteState == 'notSharing'
        ? '$peerLabel 已连接，正在重新确认双向共享目录'
        : direction == 'sending'
        ? '正在同步到$peerLabel'
        : '正在接收另一台设备的数据';

    return GuildContentPanel(
      role: GuildSurfaceRole.chrome,
      classicRadius: 16,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            Icon(Icons.sync_rounded, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: repairingHandshake ? null : completion / 100,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopContentNavigatorObserver extends NavigatorObserver {
  _DesktopContentNavigatorObserver(this.onNestedStateChanged);

  final ValueChanged<bool> onNestedStateChanged;
  int _routeCount = 0;
  bool _active = true;

  void deactivate() {
    _active = false;
  }

  void _notify() {
    if (_active) onNestedStateChanged(_routeCount > 1);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeCount += 1;
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routeCount > 0) _routeCount -= 1;
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routeCount > 0) _routeCount -= 1;
    _notify();
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    _notify();
  }
}

class _HomeTab {
  const _HomeTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}
