import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_shell.dart';

import '../core/account/account_models.dart';
import '../core/account/web_account_store.dart';
import '../core/changelog/adventurer_news.dart';
import '../features/account/presentation/account_common_views.dart';
import '../features/account/presentation/web_existing_account_join_page.dart';
import '../core/features/app_feature_store.dart';
import '../core/finance/pricing_preset_store.dart';
import '../core/portability/app_backup_data.dart';
import '../core/portability/backup_asset_rules.dart';
import '../core/portability/web_backup_reader.dart';
import '../core/portability/full_backup_logic.dart';
import '../core/sync/public_peer_sync_service.dart';
import '../core/cloud_sync/public_peer_sync_factory.dart';
import '../core/settings/workspace_settings_codec.dart';
import '../core/settings/workspace_navigation_model.dart';
import '../core/sync/sync_coordinator_web.dart';
import '../core/theme/app_theme_store.dart';
import '../core/web/web_platform_bridge.dart';
import '../features/home/presentation/about_page.dart';
import '../features/home/presentation/adventurer_news_dialog.dart';
import '../features/home/presentation/app_drawer.dart';
import '../features/home/presentation/first_run_guide.dart';
import '../features/home/presentation/settings_common.dart';
import '../features/home/presentation/workspace_shell.dart';
import '../features/home/presentation/workspace_main_pages.dart';
import '../features/home/presentation/workspace_common_tool_pages.dart';
import '../features/home/presentation/quick_start_guide_helpers.dart';
import '../features/home/presentation/workspace_add_pages.dart';
import '../features/imports/data/screenshot_import_history.dart';
import '../features/focus/state/focus_store.dart';
import '../features/focus/presentation/focus_panel.dart';
import '../features/orders/data/node_presets.dart';
import '../features/orders/data/order_reference_image_store.dart';
import '../features/orders/domain/queue_order.dart';
import '../features/orders/presentation/order_detail_page.dart';
import '../features/orders/state/order_store.dart';
import '../features/products/state/product_store.dart';
import '../features/sync/presentation/sync_page_common.dart';
import '../features/shared/domain/collection_view_preferences.dart';
import '../features/shared/domain/receipt_style_store.dart';
import '../features/shared/presentation/layout_spacing.dart';
import '../features/shared/presentation/spotlight_guide.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final AppThemeStore _themeStore = AppThemeStore();
  final AppFeatureStore _featureStore = AppFeatureStore();
  final WebAccountStore _accountStore = WebAccountStore();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait<void>([
      _themeStore.load(),
      _featureStore.load(),
      _accountStore.load(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _themeStore.dispose();
    _featureStore.dispose();
    _accountStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _themeStore,
        _accountStore,
      ]),
      builder: (context, _) {
        return GuildMaterialApp(
          themeStore: _themeStore,
          home: _WebAccountGate(
            accountStore: _accountStore,
            themeStore: _themeStore,
            featureStore: _featureStore,
          ),
        );
      },
    );
  }
}


class _WebAccountGate extends StatefulWidget {
  const _WebAccountGate({
    required this.accountStore,
    required this.themeStore,
    required this.featureStore,
  });

  final WebAccountStore accountStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;

  @override
  State<_WebAccountGate> createState() => _WebAccountGateState();
}

class _WebAccountGateState extends State<_WebAccountGate> {
  final WebBackupReader _backupReader = const WebBackupReader();
  final OrderReferenceImageStore _referenceImageStore =
      OrderReferenceImageStore();
  bool _importing = false;

  Future<void> _importAccountBackup() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final imported = await _backupReader.pickAndRead();
      if (imported == null) return;
      final state = imported.backup.accountSyncState;
      if (state == null || !state.hasCredentials) {
        throw const FormatException(
          '这份备份没有完整账号凭据，不能用来在新浏览器登录。',
        );
      }

      final accountId = state.accountId;
      final workspaceKey = 'adventurers-guild.web.workspace.v2.$accountId';

      if (imported.includesAssets) {
        AppBackupData? previousBackup;
        final previousSource = webStorageGet(workspaceKey);
        if (previousSource != null && previousSource.trim().isNotEmpty) {
          try {
            previousBackup = AppBackupData.decode(previousSource);
          } catch (_) {
            // A damaged old workspace must not block a valid replacement.
          }
        }

        final importedPaths = <String>{};
        final importedImages = <OrderReferenceImage>[
          for (final order in imported.backup.orders) ...order.referenceImages,
          for (final product in imported.backup.products)
            ...product.referenceImages,
        ];
        for (final image in importedImages) {
          final bytes = imported.assets[image.relativePath];
          if (bytes == null) {
            throw FormatException('完整备份缺少参考图：${image.fileName}');
          }
          await _referenceImageStore.writeAssetBytes(
            accountId: accountId,
            relativePath: image.relativePath,
            bytes: bytes,
          );
          importedPaths.add(image.relativePath);
        }

        final importedDesktopPaths = BackupAssetRules.desktopPetAssetPaths(
          imported.backup.settings['desktopPetBackup'],
        );
        for (final path in importedDesktopPaths) {
          final bytes = imported.assets[path];
          if (bytes == null) {
            throw FormatException('桌宠备份缺少素材：$path');
          }
          await _referenceImageStore.writeAssetBytes(
            accountId: accountId,
            relativePath: path,
            bytes: bytes,
          );
        }

        if (previousBackup != null) {
          await _referenceImageStore.deleteImages(
            accountId: accountId,
            images: [
              for (final order in previousBackup.orders)
                for (final image in order.referenceImages)
                  if (!importedPaths.contains(image.relativePath)) image,
              for (final product in previousBackup.products)
                for (final image in product.referenceImages)
                  if (!importedPaths.contains(image.relativePath)) image,
            ],
          );
          final previousDesktopPaths = BackupAssetRules.desktopPetAssetPaths(
            previousBackup.settings['desktopPetBackup'],
          );
          await _referenceImageStore.deleteAssetPaths(
            accountId: accountId,
            relativePaths: previousDesktopPaths.difference(
              importedDesktopPaths,
            ),
          );
        }
      } else if (BackupAssetRules.desktopPetAssetPaths(
        imported.backup.settings['desktopPetBackup'],
      ).isNotEmpty) {
        throw const FormatException('这份备份包含桌宠素材记录，但没有随包素材文件。');
      }

      webStorageSet(
        workspaceKey,
        imported.backup.encode(pretty: false),
      );

      await widget.accountStore.importAccountState(
        state,
        select: true,
        stayLoggedIn: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('账号和本地数据已导入，请输入账号密码登录。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.accountStore.status) {
      AccountStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AccountStatus.unlocked => _WebWorkspace(
          accountStore: widget.accountStore,
          themeStore: widget.themeStore,
          featureStore: widget.featureStore,
        ),
      AccountStatus.locked => _WebLoginPage(store: widget.accountStore),
      AccountStatus.revoked => _WebRevokedPage(
          store: widget.accountStore,
          onImportBackup: _importAccountBackup,
        ),
      AccountStatus.unactivated => _WebAccountEntryPage(
          store: widget.accountStore,
          importing: _importing,
          onImportBackup: _importAccountBackup,
        ),
    };
  }
}

class _WebAccountEntryPage extends StatelessWidget {
  const _WebAccountEntryPage({
    required this.store,
    required this.importing,
    required this.onImportBackup,
  });

  final WebAccountStore store;
  final bool importing;
  final Future<void> Function() onImportBackup;

  @override
  Widget build(BuildContext context) {
    return AccountEntryView(
      accounts: [
        for (final account in store.localAccounts)
          AccountEntryItem(
            accountId: account.accountId,
            accountName: account.accountName,
          ),
      ],
      introText:
          '可以登录当前浏览器已经保存的账号，也可以注册新账号或从其他设备加入。',
      localAccountsTitle: '当前浏览器已有账号',
      onSelectAccount: store.selectLocalAccount,
      onRemoveAccount: (account) => _remove(context, account),
      onActivate: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _WebActivationPage(store: store),
        ),
      ),
      onJoin: importing
          ? () {}
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WebExistingAccountJoinPage(
                    store: store,
                    onImportBackup: onImportBackup,
                  ),
                ),
              ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    AccountEntryItem account,
  ) async {
    await store.selectLocalAccount(account.accountId);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('从当前浏览器移除“${account.accountName}”？'),
          content: const Text(
            '会移除当前浏览器里这个账号的登录与工作区记录，不会影响安卓、Windows 或其他设备。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('从本机移除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await store.removeSelectedLocalAccount();
    } else {
      await store.returnToAccountChooser();
    }
  }
}

class _WebActivationPage extends StatelessWidget {
  const _WebActivationPage({required this.store});

  final WebAccountStore store;

  @override
  Widget build(BuildContext context) {
    return AccountActivationView(
      onActivate: ({
        required activationCode,
        required accountName,
        required password,
      }) => store.activate(
        activationCode: activationCode,
        accountName: accountName,
        password: password,
      ),
      onActivated: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }
}

class _WebLoginPage extends StatelessWidget {
  const _WebLoginPage({required this.store});

  final WebAccountStore store;

  @override
  Widget build(BuildContext context) {
    return AccountLoginView(
      initialAccountName: store.accountName ?? '',
      onLogin: ({
        required accountName,
        required password,
      }) => store.unlock(
        accountName: accountName,
        password: password,
      ),
      onChooseOther: store.returnToAccountChooser,
      onRemove: () => _remove(context),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('从当前浏览器移除这个账号？'),
          content: const Text(
            '会移除当前浏览器里这个账号的登录与工作区记录，不会影响安卓、Windows 或其他设备。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('从本机移除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await store.removeSelectedLocalAccount();
    }
  }
}

class _WebRevokedPage extends StatelessWidget {
  const _WebRevokedPage({
    required this.store,
    required this.onImportBackup,
  });

  final WebAccountStore store;
  final Future<void> Function() onImportBackup;

  @override
  Widget build(BuildContext context) {
    return RevokedAccountView(
      description:
          '当前浏览器里的这个账号已经被解绑。要重新加入，需要从仍在使用的设备重新确认，或导入这个账号的完整备份。',
      onRejoin: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebExistingAccountJoinPage(
            store: store,
            onImportBackup: onImportBackup,
          ),
        ),
      ),
      onChooseOther: store.returnToAccountChooser,
      onRemove: store.removeSelectedLocalAccount,
    );
  }
}

class _WebWorkspace extends StatefulWidget {
  const _WebWorkspace({
    required this.accountStore,
    required this.themeStore,
    required this.featureStore,
  });

  final WebAccountStore accountStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;

  @override
  State<_WebWorkspace> createState() => _WebWorkspaceState();
}

class _WebWorkspaceState extends State<_WebWorkspace> {
  final QuickStartGuideTargets _quickStartGuideTargets =
      QuickStartGuideTargets();
  String? _guidedOrderId;
  bool _guidePreviewRouteOpen = false;
  static const String _legacyWorkspaceKey =
      'adventurers-guild.web.workspace.v1';
  static const String _manifestName = 'backup.json';

  final OrderStore _orderStore = OrderStore();
  final ProductStore _productStore = ProductStore();
  final NodePresetStore _nodePresetStore = NodePresetStore();
  final PricingPresetStore _pricingPresetStore = PricingPresetStore();
  final ReceiptStyleStore _receiptStyleStore = ReceiptStyleStore();
  final FocusStore _focusStore = FocusStore();
  late final SyncCoordinator _syncUi;
  PublicPeerSyncService? _peerSync;
  final OrderReferenceImageStore _referenceImageStore =
      OrderReferenceImageStore();
  final WebBackupReader _backupReader = const WebBackupReader();
  final ScreenshotImportHistory _screenshotImportHistory =
      const ScreenshotImportHistory();

  Timer? _saveDebounce;

  String get _accountId => widget.accountStore.accountId!;
  AccountSyncState get _accountState => widget.accountStore.syncSnapshot!;
  String get _webDeviceId => widget.accountStore.currentDeviceId!;
  String get _workspaceKey =>
      'adventurers-guild.web.workspace.v2.$_accountId';

  bool _ready = false;
  bool _busy = false;
  String _selectedTab = 'orders';
  String? _desktopToolSelection;
  CollectionViewPreferences _collectionViews =
      const CollectionViewPreferences();

  bool get _orderCardView => _collectionViews.orderCardView;
  bool get _orderOverviewView => _collectionViews.orderOverviewView;
  int get _orderOverviewColumns => _collectionViews.orderOverviewColumns;
  bool get _productCardView => _collectionViews.productCardView;
  bool get _productOverviewView => _collectionViews.productOverviewView;
  int get _productOverviewColumns => _collectionViews.productOverviewColumns;

  String get _orderSortMode => _collectionViews.orderSortMode;
  String get _productSortMode => _collectionViews.productSortMode;
  bool _desktopNavigationOpen = true;
  bool _nativeDeadlineReminderPreference = false;
  Map<String, dynamic> _retainedSettings = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _syncUi = SyncCoordinator.web(
      accountId: _accountId,
      deviceId: _webDeviceId,
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      focusStore: _focusStore,
      captureSettings: _captureSettings,
      applySettings: _applySettings,
    );
    _syncUi.addListener(_onSyncUiChanged);
    _orderStore.addListener(_scheduleSave);
    _productStore.addListener(_scheduleSave);
    _nodePresetStore.addListener(_scheduleSave);
    _pricingPresetStore.addListener(_scheduleSave);
    _receiptStyleStore.addListener(_scheduleSave);
    _focusStore.addListener(_scheduleSave);
    widget.featureStore.addListener(_onFeatureStoreChanged);
    widget.themeStore.addListener(_scheduleSave);
    unawaited(_restoreWorkspace());
  }

  void _onSyncUiChanged() {
    if (!_ready) return;
    // SyncCoordinator also notifies while applying a remote snapshot and while
    // its busy state changes. Treating those notifications as local edits
    // echoes the same snapshot back to the peer forever and continuously
    // rebuilds the web UI. Real local workspace changes already reach
    // _scheduleSave through the individual stores/theme/feature listeners.
    if (mounted) setState(() {});
  }

  void _startPublicPeerSync() {
    if (_peerSync != null) return;
    final service = createWorkspacePublicPeerSyncService(
      accountId: _accountId,
      deviceId: _webDeviceId,
      captureAccountState: () => _accountState,
      mergeAccountState: widget.accountStore.mergeCurrentAccountState,
      exportRecords: _syncUi.exportPeerRecords,
      mergeRecords: _syncUi.mergePeerRecords,
      orderStore: _orderStore,
      productStore: _productStore,
      referenceImageStore: _referenceImageStore,
    );
    _peerSync = service;
    unawaited(service.start());
  }

  void _onFeatureStoreChanged() {
    if (mounted) {
      final allowed = _tabs().map((item) => item.id).toSet();
      if (!allowed.contains(_selectedTab)) _selectedTab = 'orders';
      setState(() {});
    }
    _scheduleSave();
  }

  Future<void> _restoreWorkspace() async {
    var foundWorkspace = false;
    try {
      var source = webStorageGet(_workspaceKey);
      var migratedLegacy = false;
      if (source == null || source.trim().isEmpty) {
        final legacy = webStorageGet(_legacyWorkspaceKey);
        if (legacy != null && legacy.trim().isNotEmpty) {
          final legacyBackup = AppBackupData.decode(legacy);
          final legacyAccountId = legacyBackup.accountSyncState?.accountId;
          if (legacyAccountId == null || legacyAccountId == _accountId) {
            source = legacy;
            migratedLegacy = true;
          }
        }
      }

      if (source != null && source.trim().isNotEmpty) {
        foundWorkspace = true;
        final backup = AppBackupData.decode(source);
        final backupAccount = backup.accountSyncState;
        if (backupAccount != null && backupAccount.accountId != _accountId) {
          throw const FormatException('当前本机数据属于另一个账号。');
        }
        if (backupAccount != null) {
          await widget.accountStore.mergeCurrentAccountState(backupAccount);
        }
        _retainedSettings = Map<String, dynamic>.from(backup.settings);
        backup.restoreInto(
          orderStore: _orderStore,
          productStore: _productStore,
          nodePresetStore: _nodePresetStore,
          focusStore: _focusStore,
        );
        await _applySettings(backup.settings);
        if (backup.syncRecords != null) {
          _syncUi.restorePortableRecords(backup.syncRecords!);
        }
        if (migratedLegacy) {
          await _persistWorkspace();
          webStorageRemove(_legacyWorkspaceKey);
        }
      } else {
        _retainedSettings = <String, dynamic>{};
        await widget.themeStore.resetToDefaults();
        await widget.featureStore.resetToDefaults();
      }
      await _syncUi.initialize();
      _startPublicPeerSync();
    } catch (error) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('本机数据读取失败：$error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
      }
    }

    if (mounted) {
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          foundWorkspace
              ? _showDailyBackupReminder()
              : _showMissingWorkspaceRecoveryPrompt(),
        );
      });
    }
  }

  Future<void> _showMissingWorkspaceRecoveryPrompt() async {
    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('没有找到旧版数据'),
        content: const Text(
          '新版没有找到这个账号的旧数据。'
          '如果之前导出过完整备份，可以直接导入继续使用。\n\n'
          '建议定期导出完整备份，'
          '这样在更换浏览器、清理数据或迁移设备时，'
          '都可以用备份恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先空白使用'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入完整备份'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (restore == true) {
      await _importBackup(context);
      return;
    }
    await _showDailyBackupReminder();
  }

  Future<void> _showDailyBackupReminder() async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final reminderKey =
        'adventurers-guild.web.backup-reminder.v1.$_accountId';

    try {
      if (webStorageGet(reminderKey) == today) return;
      // Record the reminder as soon as it is shown so dismissing it still
      // keeps the promise of at most one reminder per local calendar day.
      webStorageSet(reminderKey, today);
    } catch (_) {
      // If browser storage is unavailable, showing the reminder is safer than
      // silently skipping backup guidance.
    }

    if (!mounted) return;
    final backupNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('今天备份了吗？'),
        content: const Text(
          '网页版数据保存在当前设备。建议定期导出完整备份，'
          '这样更换浏览器、清理数据或迁移设备时也能恢复排单、成品、节点和参考图。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('今天不再提醒'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('立即备份'),
          ),
        ],
      ),
    );

    if (backupNow == true && mounted) {
      await _exportBackup(context);
    }
  }

  Map<String, dynamic> _captureSettings() {
    return WorkspaceSettingsCodec.capture(
      themeStore: widget.themeStore,
      featureStore: widget.featureStore,
      pricingPresetStore: _pricingPresetStore,
      receiptStyleStore: _receiptStyleStore,
      collectionViews: _collectionViews,
      desktopNavigationOpen: _desktopNavigationOpen,
      retainedSettings: _retainedSettings,
      featureOverrides: <AppFeature, bool>{
        AppFeature.deadlineReminders: _nativeDeadlineReminderPreference,
      },
    );
  }

  Future<void> _applySettings(Map<String, dynamic> settings) async {
    final applied = await WorkspaceSettingsCodec.apply(
      settings: settings,
      themeStore: widget.themeStore,
      featureStore: widget.featureStore,
      pricingPresetStore: _pricingPresetStore,
      receiptStyleStore: _receiptStyleStore,
      collectionViews: _collectionViews,
      desktopNavigationOpen: _desktopNavigationOpen,
      passthroughFeatures: const <AppFeature>{
        AppFeature.deadlineReminders,
      },
      onPassthroughFeature: (feature, value) {
        if (feature == AppFeature.deadlineReminders) {
          _nativeDeadlineReminderPreference = value;
        }
      },
    );
    _collectionViews = applied.collectionViews;
    _desktopNavigationOpen = applied.desktopNavigationOpen;
  }

  AppBackupData _captureLocalBackup({bool portable = false}) {
    final settings = _captureSettings();
    return AppBackupData.capture(
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      focusStore: _focusStore,
      accountSyncState: _accountState,
      syncRecords: _syncUi.portableRecordsSnapshot,
      settings: settings,
    );
  }

  void _scheduleSave() {
    if (!_ready) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _persistWorkspace);
    _peerSync?.requestSync();
  }

  Future<void> _persistWorkspace() async {
    try {
      webStorageSet(
        _workspaceKey,
        _captureLocalBackup().encode(pretty: false),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本机数据保存失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<GuildWorkspaceTab> _tabs() {
    return <GuildWorkspaceTab>[
      for (final spec in workspaceTabSpecs(widget.featureStore))
        GuildWorkspaceTab(
          id: spec.id,
          label: spec.label,
          icon: spec.icon,
          selectedIcon: spec.selectedIcon,
          page: _tabBody(spec.id),
        ),
    ];
  }

  Widget _tabBody(String id) {
    return buildWorkspaceMainPage(
      id: id,
      accountId: _accountId,
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      pricingPresetStore: _pricingPresetStore,
      receiptStyleStore: _receiptStyleStore,
      featureStore: widget.featureStore,
      syncCoordinator: _syncUi,
      orderCardView: _orderCardView,
      onOrderCardViewChanged: (value) {
        setState(() {
          _collectionViews = _collectionViews.copyWith(orderCardView: value);
        });
        _scheduleSave();
      },
      orderOverviewView: _orderOverviewView,
      onOrderOverviewViewChanged: (value) {
        setState(() {
          _collectionViews = _collectionViews.copyWith(orderOverviewView: value);
        });
        _scheduleSave();
      },
      orderOverviewColumns: _orderOverviewColumns,
      onOrderOverviewColumnsChanged: (value) {
        setState(() {
          _collectionViews =
              _collectionViews.copyWith(orderOverviewColumns: value);
        });
        _scheduleSave();
      },
      orderSortMode: _orderSortMode,
      onOrderSortModeChanged: (value) {
        setState(() {
          _collectionViews = _collectionViews.copyWith(orderSortMode: value);
        });
        _scheduleSave();
      },
      productCardView: _productCardView,
      onProductCardViewChanged: (value) {
        setState(() {
          _collectionViews = _collectionViews.copyWith(productCardView: value);
        });
        _scheduleSave();
      },
      productOverviewView: _productOverviewView,
      onProductOverviewViewChanged: (value) {
        setState(() {
          _collectionViews =
              _collectionViews.copyWith(productOverviewView: value);
        });
        _scheduleSave();
      },
      productOverviewColumns: _productOverviewColumns,
      onProductOverviewColumnsChanged: (value) {
        setState(() {
          _collectionViews =
              _collectionViews.copyWith(productOverviewColumns: value);
        });
        _scheduleSave();
      },
      productSortMode: _productSortMode,
      onProductSortModeChanged: (value) {
        setState(() {
          _collectionViews = _collectionViews.copyWith(productSortMode: value);
        });
        _scheduleSave();
      },
      guideTargets: _quickStartGuideTargets,
      guideOrderId: _guidedOrderId,
    );
  }

  Future<void> _openFocusOrder(String orderId) async {
    if (!_orderStore.contains(orderId)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          accountId: _accountId,
          store: _orderStore,
          orderId: orderId,
          nodePresetStore: _nodePresetStore,
          pricingPresetStore: _pricingPresetStore,
          receiptStyleStore: _receiptStyleStore,
          featureStore: widget.featureStore,
        ),
      ),
    );
  }

  Future<void> _chooseAddMethod({required bool products}) async {
    final picked = await showGuildAddMethodPicker(context);
    if (!mounted || picked == null) return;

    final page = picked == GuildAddMethod.screenshot
        ? buildWorkspaceScreenshotImportPage(
            products: products,
            accountId: _accountId,
            orderStore: _orderStore,
            productStore: _productStore,
            nodePresetStore: _nodePresetStore,
          )
        : buildWorkspaceManualAddPage(
            products: products,
            accountId: _accountId,
            orderStore: _orderStore,
            productStore: _productStore,
            nodePresetStore: _nodePresetStore,
            pricingPresetStore: _pricingPresetStore,
            featureStore: widget.featureStore,
          );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _selectTab(int index) {
    final tabs = _tabs();
    if (index < 0 || index >= tabs.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedTab = tabs[index].id;
      _desktopToolSelection = null;
    });
  }

  void _selectDesktopTool(String tool) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _desktopToolSelection = tool);
  }

  void _openMobileTool(String tool) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _buildWebToolPage(tool),
      ),
    );
  }

  Future<void> _prepareQuickStartGuide() async {
    final tabs = _tabs();
    final orderIndex = tabs.indexWhere((tab) => tab.id == 'orders');
    if (orderIndex >= 0) {
      _selectTab(orderIndex);
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  QuickStartGuideActions get _quickStartGuideActions => QuickStartGuideActions(
        goTo: _goToGuideDestination,
        createFirstOrder: _createFirstOrderForGuide,
        waitForFirstOrderArchive: _waitForFirstOrderArchive,
        isAvailable: _isGuideDestinationAvailable,
        finish: _finishGuideNavigation,
      );

  bool _isGuideDestinationAvailable(
    QuickStartGuideDestination destination,
  ) =>
      quickStartDestinationAvailable(destination, widget.featureStore);

  int? _guideTabIndex(QuickStartGuideDestination destination) {
    final id = quickStartTabId(destination);
    if (id == null) return null;
    final tabs = _tabs();
    final index = tabs.indexWhere((tab) => tab.id == id);
    return index < 0 ? null : index;
  }

  String? _guideTool(QuickStartGuideDestination destination) =>
      quickStartTool(destination);

  Future<void> _closeGuidePreviewRoute() async {
    if (!_guidePreviewRouteOpen || !mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    _guidePreviewRouteOpen = false;
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _pushGuidePreviewPage(Widget page) async {
    if (!mounted) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
    _guidePreviewRouteOpen = true;
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _goToGuideDestination(
    QuickStartGuideDestination destination,
  ) async {
    if (!mounted || !_isGuideDestinationAvailable(destination)) return;
    await _closeGuidePreviewRoute();
    if (!mounted) return;

    final tabIndex = _guideTabIndex(destination);
    if (tabIndex != null) {
      _selectTab(tabIndex);
      if (MediaQuery.sizeOf(context).width >= 900 &&
          !_desktopNavigationOpen) {
        setState(() => _desktopNavigationOpen = true);
      }
      await WidgetsBinding.instance.endOfFrame;
      return;
    }

    if (destination == QuickStartGuideDestination.screenshotImport) {
      if (_desktopToolSelection != null) {
        setState(() => _desktopToolSelection = null);
      }
      await _pushGuidePreviewPage(
        buildQuickStartScreenshotImportPage(
          accountId: _accountId,
          orderStore: _orderStore,
          productStore: _productStore,
          nodePresetStore: _nodePresetStore,
          guideTargets: _quickStartGuideTargets,
        ),
      );
      return;
    }

    final tool = _guideTool(destination);
    if (tool == null) return;
    if (MediaQuery.sizeOf(context).width >= 900) {
      _selectDesktopTool(tool);
      if (!_desktopNavigationOpen) {
        setState(() => _desktopNavigationOpen = true);
      }
      await WidgetsBinding.instance.endOfFrame;
    } else {
      await _pushGuidePreviewPage(_buildWebToolPage(tool));
    }
  }

  Future<String?> _createFirstOrderForGuide() async {
    await _goToGuideDestination(QuickStartGuideDestination.orders);
    if (!mounted) return null;

    final beforeIds = _orderStore.orders.map((order) => order.id).toSet();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => buildQuickStartAddOrderPage(
          accountId: _accountId,
          orderStore: _orderStore,
          nodePresetStore: _nodePresetStore,
          pricingPresetStore: _pricingPresetStore,
          featureStore: widget.featureStore,
          guideTargets: _quickStartGuideTargets,
        ),
      ),
    );
    if (!mounted) return null;

    final createdId = findNewGuideOrderId(beforeIds, _orderStore);
    setState(() => _guidedOrderId = createdId);
    await WidgetsBinding.instance.endOfFrame;
    return createdId;
  }

  Future<bool> _waitForFirstOrderArchive(String orderId) {
    if (!mounted) return Future<bool>.value(false);
    return waitForGuideOrderArchive(
      context: context,
      orderStore: _orderStore,
      orderId: orderId,
    );
  }

  Future<void> _finishGuideNavigation() async {
    await _closeGuidePreviewRoute();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _guidedOrderId = null;
      _desktopToolSelection = null;
    });
    final tabs = _tabs();
    final orderIndex = tabs.indexWhere((tab) => tab.id == 'orders');
    if (orderIndex >= 0) _selectTab(orderIndex);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _showNewsHistory() async {
    final build = await const AdventurerNewsStore().installedBuild();
    if (!mounted) return;
    await showAdventurerNewsDialog(
      context,
      history: true,
      notice: AdventurerNewsNotice(
        previousBuild: 0,
        currentBuild: build,
        entries: newsBetweenBuilds(0, build),
      ),
    );
  }

  void _showTutorial() {
    unawaited(
      showFirstRunGuide(
        context,
        detailed: true,
        targets: _quickStartGuideTargets,
        prepareQuickStart: _prepareQuickStartGuide,
        actions: _quickStartGuideActions,
      ),
    );
  }

  Widget _buildWebToolPage(String tool) {
    final common = buildWorkspaceCommonToolPage(
      tool: tool,
      accountId: _accountId,
      accountName: widget.accountStore.accountName ?? '',
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      pricingPresetStore: _pricingPresetStore,
      receiptStyleStore: _receiptStyleStore,
      featureStore: widget.featureStore,
      syncCoordinator: _syncUi,
      guideTargets: _quickStartGuideTargets,
      guideOrderId: _guidedOrderId,
    );
    if (common != null) return common;

    return switch (tool) {
      AppToolMenu.desktopPetTool => Scaffold(
          appBar: AppBar(
            title: const Text(
              '专注',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: FocusPanel(
            orderStore: _orderStore,
            focusStore: _focusStore,
            onOpenOrder: _openFocusOrder,
          ),
        ),
      AppToolMenu.syncTool => _WebDataPage(
          linkedAccountName: _accountState.accountName,
          busy: () => _busy,
          onExport: _exportBackup,
          onImport: _importBackup,
          peerSync: _peerSync,
          guideTargets: _quickStartGuideTargets,
        ),
      AppToolMenu.accountTool => _WebAccountPage(
          store: widget.accountStore,
          peerSync: _peerSync,
          guideTargets: _quickStartGuideTargets,
        ),
      AppToolMenu.settingsTool => _WebSettingsPage(
          themeStore: widget.themeStore,
          featureStore: widget.featureStore,
          busy: () => _busy,
          onExport: _exportBackup,
          onImport: _importBackup,
          onShowNews: _showNewsHistory,
          guideTargets: _quickStartGuideTargets,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Future<void> _exportBackup(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var backup = _captureLocalBackup(portable: true);
      backup = withFullBackupMetadata(
        backup,
        screenshotImportHistory:
            await _screenshotImportHistory.read(accountId: _accountId),
      );
      final archive = Archive();
      final manifest = utf8.encode(backup.encode());
      archive.addFile(
        ArchiveFile(_manifestName, manifest.length, manifest),
      );

      final referenceImages = <OrderReferenceImage>[
        for (final order in backup.orders) ...order.referenceImages,
        for (final product in backup.products) ...product.referenceImages,
      ];
      for (final image in referenceImages) {
        final bytes = await _referenceImageStore.readAssetBytes(
          accountId: _accountId,
          relativePath: image.relativePath,
        );
        if (bytes == null) {
          throw StateError('参考图“${image.fileName}”原文件缺失，无法生成完整备份。');
        }
        if (bytes.length != image.sizeBytes) {
          throw StateError('参考图“${image.fileName}”文件大小与记录不一致。');
        }
        archive.addFile(
          ArchiveFile(image.relativePath, bytes.length, bytes),
        );
      }

      for (final path
          in BackupAssetRules.desktopPetAssetPaths(backup.settings['desktopPetBackup'])) {
        final bytes = await _referenceImageStore.readAssetBytes(
          accountId: _accountId,
          relativePath: path,
        );
        if (bytes == null) {
          throw StateError('桌宠素材“$path”原文件缺失，无法生成完整备份。');
        }
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }

      final encoded = ZipEncoder().encode(archive);
      final bytes = Uint8List.fromList(encoded);
      _downloadBytes(
        fileName: _backupFileName(DateTime.now()),
        bytes: bytes,
        mimeType: 'application/zip',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '完整备份已导出，可在安卓或电脑端“设置 → 导入完整备份”中手动同步。',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    if (_busy) return;

    final imported = await _backupReader.pickAndRead();
    if (imported == null) return;

    setState(() => _busy = true);
    try {
      final backup = imported.backup;
      validateBackupForCurrentAccount(
        backup: backup,
        currentAccountId: _accountId,
      );
      final backupAccount = backup.accountSyncState;
      final accountName =
          backupAccount?.accountName ?? widget.accountStore.accountName;

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入并替换当前数据？'),
          content: Text(
            '排单 ${backup.orders.length} 条 · 成品 ${backup.products.length} 条 · '
            '节点预设 ${backup.nodePresets.length} 个\n'
            '账号：${accountName ?? '当前账号'}\n'
            '备份时间：${_formatDateTime(backup.exportedAt.toLocal())}\n\n'
            '导入后会用这份备份替换当前账号的数据。'
            '${imported.includesAssets ? '' : '\n这份文件不含参考图原文件，已有参考图可能显示为缺失。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final previousDesktopPaths = BackupAssetRules.desktopPetAssetPaths(
        _retainedSettings['desktopPetBackup'],
      );
      if (imported.includesAssets) {
        final importedPaths = <String>{};
        final importedImages = <OrderReferenceImage>[
          for (final order in backup.orders) ...order.referenceImages,
          for (final product in backup.products) ...product.referenceImages,
        ];
        for (final image in importedImages) {
          final bytes = imported.assets[image.relativePath];
          if (bytes == null) {
            throw FormatException('完整备份缺少参考图：${image.fileName}');
          }
          await _referenceImageStore.writeAssetBytes(
            accountId: _accountId,
            relativePath: image.relativePath,
            bytes: bytes,
          );
          importedPaths.add(image.relativePath);
        }
        await _referenceImageStore.deleteImages(
          accountId: _accountId,
          images: [
            for (final order in _orderStore.orders)
              for (final image in order.referenceImages)
                if (!importedPaths.contains(image.relativePath)) image,
            for (final product in _productStore.products)
              for (final image in product.referenceImages)
                if (!importedPaths.contains(image.relativePath)) image,
          ],
        );

        final importedDesktopPaths =
            BackupAssetRules.desktopPetAssetPaths(backup.settings['desktopPetBackup']);
        for (final path in importedDesktopPaths) {
          final bytes = imported.assets[path];
          if (bytes == null) {
            throw FormatException('桌宠备份缺少素材：$path');
          }
          await _referenceImageStore.writeAssetBytes(
            accountId: _accountId,
            relativePath: path,
            bytes: bytes,
          );
        }
        await _referenceImageStore.deleteAssetPaths(
          accountId: _accountId,
          relativePaths:
              previousDesktopPaths.difference(importedDesktopPaths),
        );
      } else if (BackupAssetRules.desktopPetAssetPaths(
        backup.settings['desktopPetBackup'],
      ).isNotEmpty) {
        throw const FormatException('这份备份包含桌宠素材记录，但没有随包素材文件。');
      }

      if (backupAccount != null) {
        await widget.accountStore.mergeCurrentAccountState(backupAccount);
      }
      _retainedSettings = Map<String, dynamic>.from(backup.settings);
      backup.restoreInto(
        orderStore: _orderStore,
        productStore: _productStore,
        nodePresetStore: _nodePresetStore,
        focusStore: _focusStore,
      );
      await _applySettings(backup.settings);
      await _syncUi.replacePortableRecordsForCurrentWorkspace(
        backup.syncRecords,
      );
      final screenshotHistory = parseScreenshotImportHistory(backup);
      if (screenshotHistory != null) {
        await _screenshotImportHistory.replaceAll(
          accountId: _accountId,
          fingerprints: screenshotHistory,
        );
      }
      _peerSync?.requestSync(immediate: true);
      await _persistWorkspace();

      if (!context.mounted) return;
      setState(() => _selectedTab = 'orders');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导入完成，当前账号的数据已经替换。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _downloadBytes({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    webDownloadBytes(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  String _backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '冒险者公会-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.zip';
  }

  String _formatDateTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _orderStore.removeListener(_scheduleSave);
    _productStore.removeListener(_scheduleSave);
    _nodePresetStore.removeListener(_scheduleSave);
    _pricingPresetStore.removeListener(_scheduleSave);
    _receiptStyleStore.removeListener(_scheduleSave);
    _pricingPresetStore.dispose();
    _receiptStyleStore.dispose();
    _focusStore.removeListener(_scheduleSave);
    _focusStore.dispose();
    widget.featureStore.removeListener(_onFeatureStoreChanged);
    widget.themeStore.removeListener(_scheduleSave);
    _syncUi.removeListener(_onSyncUiChanged);
    _peerSync?.dispose();
    _peerSync = null;
    _syncUi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    if (tabs.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (!tabs.any((tab) => tab.id == _selectedTab)) {
      _selectedTab = tabs.first.id;
    }
    final selectedIndex = tabs.indexWhere((tab) => tab.id == _selectedTab);
    final current = tabs[selectedIndex];
    final showFocus = widget.featureStore.enabled(AppFeature.focus);

    final title = _desktopToolSelection == null
        ? current.label
        : workspaceToolTitle(
            _desktopToolSelection!,
            fallback: current.label,
          );

    final tabBody = IndexedStack(
      index: selectedIndex,
      children: [
        for (final tab in tabs)
          KeyedSubtree(key: ValueKey(tab.id), child: tab.page),
      ],
    );

    final desktopBody = _desktopToolSelection == null
        ? tabBody
        : KeyedSubtree(
            key: ValueKey('desktop-tool-$_desktopToolSelection'),
            child: _buildWebToolPage(_desktopToolSelection!),
          );

    final drawer = AppDrawer(
      onSelectTool: _openMobileTool,
      onShowTutorial: _showTutorial,
      showFeatureToggle: true,
      showPetFocusEntry: showFocus,
      showDesktopPet: false,
      showFeedback: false,
      accountSubtitle: widget.accountStore.accountName ?? '当前账号',
    );

    final desktopMenu = AppToolMenu(
      onSelectTool: _selectDesktopTool,
      onShowTutorial: _showTutorial,
      showFeatureToggle: true,
      showPetFocusEntry: showFocus,
      showDesktopPet: false,
      showFeedback: false,
      accountSubtitle: widget.accountStore.accountName ?? '当前账号',
      selectedTool: _desktopToolSelection,
      showTrailing: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
    );

    final floatingAction = _busy || _desktopToolSelection != null
        ? null
        : switch (current.id) {
            'orders' => FloatingActionButton.extended(
                key: _quickStartGuideTargets.addOrderKey,
                onPressed: () => unawaited(
                    _chooseAddMethod(products: false),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增排单'),
              ),
            'products' => FloatingActionButton.extended(
                key: _quickStartGuideTargets.addProductKey,
                onPressed: () => unawaited(
                    _chooseAddMethod(products: true),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增成品'),
              ),
            _ => null,
          };

    final shell = GuildWorkspaceShell(
      tabs: tabs,
      selectedIndex: selectedIndex,
      onTabSelected: _selectTab,
      title: title,
      ready: _ready,
      contentAvailable: true,
      mobileBody: tabBody,
      desktopBody: desktopBody,
      drawer: drawer,
      desktopToolMenu: desktopMenu,
      desktopNavigationOpen: _desktopNavigationOpen,
      onDesktopNavigationChanged: (value) {
        setState(() => _desktopNavigationOpen = value);
        _scheduleSave();
      },
      toolSelected: _desktopToolSelection != null,
      floatingActionButton: floatingAction,
      showAppBar: _desktopToolSelection == null,
      guideTargets: _quickStartGuideTargets,
    );

    if (!_busy) return shell;

    return Stack(
      fit: StackFit.expand,
      children: [
        shell,
        ColoredBox(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.08),
          child: const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 14),
                    Text('正在处理备份…'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WebAccountPage extends StatelessWidget {
  const _WebAccountPage({
    required this.store,
    required this.peerSync,
    this.guideTargets,
  });

  final WebAccountStore store;
  final PublicPeerSyncService? peerSync;
  final QuickStartGuideTargets? guideTargets;

  Uint8List? _avatarBytes() {
    final raw = store.syncSnapshot?.avatarBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _renameAccount(String name) async {
    await store.renameAccount(name);
    peerSync?.requestSync(immediate: true);
  }

  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await store.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    peerSync?.requestSync(immediate: true);
  }

  Future<void> _renameDevice(AccountDevice device, String name) async {
    await store.renameDevice(device.id, name);
    peerSync?.requestSync(immediate: true);
  }

  Future<void> _revokeDevice(
    BuildContext context,
    AccountDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解绑这台设备？'),
        content: Text(
          '“${device.name}”会从使用中设备移除，并通过设备同步发送解绑状态。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.revokeDevice(device.id);
    peerSync?.requestSync(immediate: true);
  }

  Future<void> _signOut(BuildContext context) async {
    await store.lock();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => AccountManagementView(
        accountName: store.accountName ?? '',
        password: store.accountPassword,
        avatarBytes: _avatarBytes(),
        devices: store.activeDevices,
        currentDeviceId: store.currentDeviceId,
        onRenameAccount: _renameAccount,
        onChangePassword: _changePassword,
        onRenameDevice: _renameDevice,
        onRevokeDevice: (device) => _revokeDevice(context, device),
        onSignOut: () => _signOut(context),
        guideTargets: guideTargets,
      ),
    );
  }
}

class _WebSettingsPage extends StatelessWidget {
  const _WebSettingsPage({
    required this.themeStore,
    required this.featureStore,
    required this.busy,
    required this.onExport,
    required this.onImport,
    required this.onShowNews,
    this.guideTargets,
  });

  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final bool Function() busy;
  final Future<void> Function(BuildContext context) onExport;
  final Future<void> Function(BuildContext context) onImport;
  final VoidCallback onShowNews;
  final QuickStartGuideTargets? guideTargets;

  Future<void> _installPwa(BuildContext context) async {
    final state = await webPwaInstalledState();
    if (!context.mounted) return;

    if (state == 'standalone') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前已经在网页版应用模式中打开。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (state == 'installed') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('网页版应用已安装'),
          content: const Text(
            '浏览器已经确认冒险者公会安装完成。Android 是否自动把图标放到桌面，'
            '由手机的桌面启动器设置决定；网页不能直接申请系统的“创建桌面快捷方式”权限。\n\n'
            '如果桌面没有图标，可以到系统应用列表找到“冒险者公会”，'
            '长按后拖到桌面或选择“添加到桌面”。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    if (state == 'prompt') {
      final result = await webPromptPwaInstall();
      if (!context.mounted) return;
      if (result == 'accepted' ||
          result == 'installed' ||
          result == 'standalone') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '浏览器已接受网页版应用安装请求。安装完成后如果桌面没有自动出现图标，'
              '可以从系统应用列表找到“冒险者公会”并添加到桌面。',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (result == 'dismissed') return;
    }

    if (!context.mounted) return;
    final ios = webPwaInstallState() == 'ios';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安装网页版应用'),
        content: Text(
          ios
              ? '在浏览器底部或顶部点“分享”，再选择“添加到主屏幕”。之后就可以从桌面直接打开冒险者公会。'
              : '当前浏览器还没有提供可直接调用的一键安装提示。请打开浏览器菜单，选择“安装应用”或“添加到主屏幕”（名称会因浏览器不同略有差异）。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAbout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AppAboutPage(
          version: info.version,
          buildNumber: int.tryParse(info.buildNumber) ?? 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '设置',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        // Tutorial targets such as “安装网页版应用” sit below the first
        // viewport. Keep a few screens laid out so the shared spotlight guide
        // can resolve the real ListTile and scroll to it instead of showing an
        // unbound dimmed overlay.
        scrollCacheExtent: MediaQuery.sizeOf(context).height * 3,
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 16,
          top: 8,
          right: 16,
        ),
        children: [
          GuildSettingsAppearanceCard(
            themeStore: themeStore,
            featureStore: featureStore,
          ),
          const SizedBox(height: 14),
          GuildSettingsDataCard(
            exportBusy: busy(),
            onExport: () => unawaited(onExport(context)),
            onImport: () => unawaited(onImport(context)),
            guideTargets: guideTargets,
          ),
          const SizedBox(height: 14),
          SpotlightTarget(
            targetKey: guideTargets?.pwaInstallKey,
            child: GuildSettingsSectionCard(
              title: '网页版',
              icon: Icons.install_desktop_rounded,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.install_desktop_rounded),
                title: Text(
                  switch (webPwaInstallState()) {
                    'standalone' => '已作为网页版应用打开',
                    'installed' => '网页版应用已安装',
                    _ => '安装网页版应用',
                  },
                ),
                subtitle: Text(
                  switch (webPwaInstallState()) {
                    'standalone' => '当前正在独立应用模式中运行',
                    'installed' => '浏览器已安装；是否自动显示桌面图标由系统桌面决定',
                    _ => '调用浏览器安装提示，以独立应用方式打开',
                  },
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _installPwa(context),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GuildSettingsNewsCard(onOpen: onShowNews),
          const SizedBox(height: 14),
          GuildSettingsAboutCard(
            onOpen: () => unawaited(_openAbout(context)),
          ),
        ],
      ),
    );
  }
}

class _WebDataPage extends StatelessWidget {
  const _WebDataPage({
    required this.linkedAccountName,
    required this.busy,
    required this.onExport,
    required this.onImport,
    required this.peerSync,
    this.guideTargets,
  });

  final String? linkedAccountName;
  final bool Function() busy;
  final Future<void> Function(BuildContext context) onExport;
  final Future<void> Function(BuildContext context) onImport;
  final PublicPeerSyncService? peerSync;
  final QuickStartGuideTargets? guideTargets;

  @override
  Widget build(BuildContext context) {
    final sync = peerSync;
    if (sync == null) {
      return _buildPage(context);
    }
    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final linked = linkedAccountName != null;
    final connected = peerSync?.connected == true;
    final error = peerSync?.lastError;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '设备同步',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 16,
          top: 8,
          right: 16,
        ),
        children: [
          SpotlightTarget(
            targetKey: guideTargets?.syncKey,
            child: SyncSectionCard(
              title: '同步控制',
              icon: connected
                  ? Icons.sync_rounded
                  : Icons.sync_problem_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '网页版在已绑定设备同时打开时自动交换排单、成品、节点、设置和参考图。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SyncPrimaryAction(
                    label: connected ? '立即同步' : '重新连接并同步',
                    onPressed: peerSync == null
                        ? null
                        : () => peerSync!.requestSync(immediate: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SyncSectionCard(
            title: '同步状态',
            icon: Icons.sync_alt_rounded,
            child: Column(
              children: [
                SyncStatusRow(
                  label: '账号关联',
                  value: linked ? linkedAccountName! : '尚未关联',
                  good: linked,
                ),
                const SizedBox(height: 8),
                SyncStatusRow(
                  label: '在线连接',
                  value: connected ? '已连接' : '等待其他设备',
                  good: connected,
                ),
                if (error != null && error.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          GuildSettingsDataCard(
            exportBusy: busy(),
            onExport: () => unawaited(onExport(context)),
            onImport: () => unawaited(onImport(context)),
            guideTargets: guideTargets,
          ),
          const SizedBox(height: 14),
          Text(
            '在线同步只在设备打开时进行。若要更换浏览器、清理数据或迁移设备，建议先保留一份完整备份。',
            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
