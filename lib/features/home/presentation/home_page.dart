import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/account/account_models.dart';
import '../../../core/account/account_store.dart';
import '../../../core/features/app_feature_store.dart';
import '../../../core/notifications/order_deadline_reminder_service.dart';
import '../../../core/onboarding/interaction_hint_store.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/storage/app_data_persistence.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../account/presentation/account_page.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/presentation/add_order_page.dart';
import '../../orders/presentation/node_preset_page.dart';
import '../../orders/presentation/order_queue_page.dart';
import '../../orders/state/order_store.dart';
import '../../products/presentation/add_product_page.dart';
import '../../products/presentation/product_page.dart';
import '../../products/state/product_store.dart';
import '../../schedule/presentation/schedule_page.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../sync/presentation/device_sync_page.dart';
import 'abstract_mode_guide.dart';
import 'app_drawer.dart';
import 'archive_page.dart';
import 'feature_toggle_page.dart';
import 'first_run_guide.dart';
import 'reminder_background_guide.dart';
import 'settings_page.dart';
import 'theme_color_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.accountId,
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    super.key,
  });

  final String accountId;
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
  final AppDataPersistence _persistence = const AppDataPersistence();
  final OrderDeadlineReminderService _reminderService =
      const OrderDeadlineReminderService();
  final InteractionHintStore _hintStore = const InteractionHintStore();
  late final SyncCoordinator _syncCoordinator;

  static const _orderCardViewSettingKey = 'orderCardView';
  static const _productCardViewSettingKey = 'productCardView';
  static const _orderSortModeSettingKey = 'orderSortMode';
  static const _productSortModeSettingKey = 'productSortMode';
  static const _desktopNavigationOpenSettingKey = 'desktopNavigationOpen';
  static const _featureSettingPrefix = 'feature.';

  int _index = 0;
  bool _ready = false;
  bool _orderCardView = false;
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
  bool _saving = false;
  bool _saveAgain = false;
  bool _notificationPermissionChecked = false;
  bool _localDataHealthy = true;
  bool _abstractFeatureToggleHidden = false;
  bool _abstractGuidePromptVisible = false;
  bool _lastAbstractMode = false;
  bool _syncConflictPromptVisible = false;
  bool _syncConflictPromptedUntilClear = false;
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
    _syncCoordinator = SyncCoordinator(
      accountId: widget.accountId,
      deviceId: currentDeviceId,
      deviceName: deviceName,
      accountStore: widget.accountStore,
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      captureSettings: _captureSyncSettings,
      applySettings: _applySyncSettings,
    );
    _syncCoordinator.addListener(_onSyncCoordinatorChanged);

    widget.themeStore.addListener(_onThemeSettingsChanged);
    widget.featureStore.addListener(_onFeatureSettingsChanged);
    widget.accountStore.addListener(_onAccountStoreChanged);
    _restoreLocalData();
  }

  Future<void> _restoreLocalData() async {
    String? errorMessage;
    var isNewAccount = false;
    var bootstrapOnly = false;
    var hasWorkspaceSettings = false;
    var consumedPortableSyncHistory = false;

    try {
      final backup = await _persistence.load(accountId: widget.accountId);
      isNewAccount = backup == null;
      bootstrapOnly = backup?.settings['bootstrapOnly'] == true;
      hasWorkspaceSettings =
          backup != null &&
          !bootstrapOnly &&
          (backup.settings.containsKey('themeMode') ||
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
        );

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
    if (!mounted || !widget.featureStore.abstractMode) return;
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
  }

  void _onAccountStoreChanged() {
    final snapshot = widget.accountStore.syncSnapshot;
    if (snapshot?.accountId != widget.accountId) return;
    _accountSyncSnapshot = snapshot;
    _scheduleSave();
  }

  void _onSyncCoordinatorChanged() {
    if (!mounted || !_ready) return;

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
      _refreshDesktopCollectionRootIfNeeded();
    });

    _scheduleSave();
    _scheduleReminderSync();
    _syncCoordinator.notifySettingsChanged();

    if (_ready && enteredAbstractMode) {
      unawaited(_showAbstractModeGuideOnce());
    }
  }

  void _onThemeSettingsChanged() {
    if (!mounted) return;
    _scheduleSave();
    _syncCoordinator.notifySettingsChanged();
  }

  Map<String, dynamic> _captureSyncSettings() {
    final features = widget.featureStore.toJson();
    return <String, dynamic>{
      'id': SyncCoordinator.settingsRecordId,
      'themeMode': widget.themeStore.mode.name,
      'themePaletteId': widget.themeStore.paletteId,
      for (final entry in features.entries)
        '$_featureSettingPrefix${entry.key}': entry.value,
      _orderCardViewSettingKey: _orderCardView,
      _productCardViewSettingKey: _productCardView,
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

    final paletteId = settings['themePaletteId'];
    if (paletteId is String && AppThemePalettes.containsId(paletteId)) {
      await widget.themeStore.setPaletteId(paletteId);
    } else if (paletteId != null) {
      throw const FormatException('同步主题色无效。');
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

    var layoutChanged = false;
    final nextOrderCardView = settings[_orderCardViewSettingKey];
    if (nextOrderCardView is bool && nextOrderCardView != _orderCardView) {
      _orderCardView = nextOrderCardView;
      layoutChanged = true;
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
      accountSyncState: _accountSyncSnapshot,
      settings: <String, dynamic>{
        'syncBaselineRecords': _syncCoordinator.syncBaselineSettings,
        ..._captureSyncSettings(),
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready || !_localDataHealthy) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveDebounce?.cancel();
      unawaited(_flushSyncThenPersist());
    }
  }

  Future<void> _prepareForSignOut() async {
    _saveDebounce?.cancel();
    _reminderDebounce?.cancel();
    if (_ready && _localDataHealthy) {
      await _flushSyncThenPersist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _reminderDebounce?.cancel();
    widget.themeStore.removeListener(_onThemeSettingsChanged);
    widget.featureStore.removeListener(_onFeatureSettingsChanged);
    widget.accountStore.removeListener(_onAccountStoreChanged);
    _syncCoordinator.removeListener(_onSyncCoordinatorChanged);
    _orderStore.removeListener(_onOrderStoreChanged);
    _productStore.removeListener(_scheduleSave);
    _nodePresetStore.removeListener(_scheduleSave);

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

    _desktopContentNavigatorObserver.deactivate();
    _syncCoordinator.dispose();
    _orderStore.dispose();
    _productStore.dispose();
    _nodePresetStore.dispose();
    super.dispose();
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
        syncCoordinator: _syncCoordinator,
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
      AppToolMenu.archiveTool => ArchivePage(
        accountId: widget.accountId,
        orderStore: _orderStore,
        productStore: _productStore,
        nodePresetStore: _nodePresetStore,
        featureStore: widget.featureStore,
      ),
      AppToolMenu.syncTool => DeviceSyncPage(coordinator: _syncCoordinator),
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
        themeStore: widget.themeStore,
        featureStore: widget.featureStore,
        accountStore: widget.accountStore,
        syncCoordinator: _syncCoordinator,
        onApplyWorkspaceSettings: _applySyncSettings,
        onOpenThemeColor: () =>
            _selectDesktopTool(AppToolMenu.themeColorTool),
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
      AppToolMenu.archiveTool => '归档',
      AppToolMenu.syncTool => '设备同步',
      AppToolMenu.accountTool => '账号与设备',
      AppToolMenu.settingsTool => '设置',
      AppToolMenu.themeColorTool => 'UI主题色',
      _ => current.label,
    };
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = width >= 900;

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

    return Scaffold(
      drawer: _ready && _localDataHealthy
          ? AppDrawer(
              orderStore: _orderStore,
              productStore: _productStore,
              nodePresetStore: _nodePresetStore,
              themeStore: widget.themeStore,
              featureStore: widget.featureStore,
              accountStore: widget.accountStore,
              syncCoordinator: _syncCoordinator,
              onApplyWorkspaceSettings: _applySyncSettings,
              onBeforeSignOut: _prepareForSignOut,
              onShowTutorial: () => unawaited(_showTutorial()),
              showFeatureToggle:
                  !widget.featureStore.abstractMode ||
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
      body: !_ready
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
                        ? SizedBox(
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
                onPressed: _openAddOrder,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增排单'),
              ),
              '成品' => FloatingActionButton.extended(
                onPressed: _openAddProduct,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增成品'),
              ),
              _ => null,
            },
      bottomNavigationBar: !_ready || tabs.length <= 1 || useDesktopLayout
          ? null
          : NavigationBar(
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
