import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/account/account_store.dart';
import '../core/changelog/adventurer_news.dart';
import '../core/features/app_feature_store.dart';
import '../core/notifications/order_deadline_reminder_service.dart';
import '../core/portability/app_backup_data.dart';
import '../core/storage/app_data_persistence.dart';
import '../core/sync/account_sync_record_store.dart';
import '../core/sync/embedded_syncthing_bridge.dart';
import '../core/sync/portable_sync_workspace_validator.dart';
import '../core/sync/pending_device_revocation_service.dart';
import '../core/theme/app_theme_store.dart';
import '../core/theme/guild_visual_theme.dart';
import '../features/account/presentation/account_gate.dart';
import '../features/home/presentation/home_page.dart';
import '../features/orders/data/node_presets.dart';
import '../features/orders/state/order_store.dart';
import '../features/products/state/product_store.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final AppThemeStore _themeStore = AppThemeStore();
  final AppFeatureStore _featureStore = AppFeatureStore();
  final AccountStore _accountStore = AccountStore();
  final AdventurerNewsStore _newsStore = const AdventurerNewsStore();
  final AppDataPersistence _persistence = const AppDataPersistence();
  final AccountSyncRecordStore _accountSyncRecordStore =
      AccountSyncRecordStore();
  final OrderDeadlineReminderService _reminderService =
      const OrderDeadlineReminderService();
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  late final PendingDeviceRevocationService _pendingDeviceRevocations;
  Timer? _pendingDeviceRevocationTimer;
  String? _sessionAccountId;
  bool _sessionInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingDeviceRevocations = PendingDeviceRevocationService(
      accountSyncStore: _accountSyncRecordStore,
      persistence: _persistence,
    );
    _accountStore.addListener(_onAccountSessionChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait<void>([
      _themeStore.load(),
      _featureStore.load(),
    ]);

    await _accountStore.load(
      recoveryLoader: _persistence.discoverRecoverableAccounts,
    );

    // Determine whether this is a new installation before any account can
    // be created. The read marker is device-local, never synced with accounts.
    try {
      await _newsStore.initialize(
        hasExistingAccounts: _accountStore.localAccounts.isNotEmpty,
      );
    } catch (_) {
      // A local changelog write failure must not prevent account sign-in.
    }

    // Revoked accounts intentionally keep their transport folder until the
    // remote revocation acknowledgement has had a chance to sync. The user can
    // still remove the local account explicitly from the pre-login UI.

    _startPendingDeviceRevocationDelivery();
  }

  void _startPendingDeviceRevocationDelivery() {
    unawaited(_flushPendingDeviceRevocations());
    _pendingDeviceRevocationTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_flushPendingDeviceRevocations()),
    );
  }

  Future<void> _flushPendingDeviceRevocations() {
    return _pendingDeviceRevocations.flushPending(
      hasLocalAccount: _accountStore.hasActiveLocalAccount,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_flushPendingDeviceRevocations());
    }
  }

  void _onAccountSessionChanged() {
    final nextAccountId =
        _accountStore.isUnlocked ? _accountStore.accountId : null;
    final previousAccountId = _sessionAccountId;
    final firstUpdate = !_sessionInitialized;

    _sessionInitialized = true;
    _sessionAccountId = nextAccountId;

    if (firstUpdate) {
      if (nextAccountId == null) {
        unawaited(_clearActiveReminderAccount());
      } else {
        unawaited(_activateReminderAccount(nextAccountId));
      }
      return;
    }

    if (previousAccountId == nextAccountId) return;

    if (previousAccountId != null) {
      unawaited(_clearReminderAccount(previousAccountId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    }

    if (nextAccountId != null) {
      unawaited(_activateReminderAccount(nextAccountId));
    }
  }

  Future<void> _clearActiveReminderAccount() async {
    try {
      await _reminderService.clearActiveAccount();
    } catch (_) {}
  }

  Future<void> _clearReminderAccount(String accountId) async {
    try {
      await _reminderService.clearAll(accountId: accountId);
    } catch (_) {}
  }

  Future<void> _activateReminderAccount(String accountId) async {
    try {
      await _reminderService.activateAccount(accountId: accountId);
    } catch (_) {}
  }

  Future<void> _removeLocalAccount(String accountId) async {
    const syncBridge = EmbeddedSyncthingBridge();
    final snapshot = _accountStore.localDeviceRemovalSnapshot(accountId);

    var pendingDelivery = false;
    if (snapshot != null) {
      pendingDelivery =
          await _pendingDeviceRevocations.stageLocalRemoval(snapshot);
    }

    // When another device still needs the tombstone, remove the visible local
    // account immediately but retain its hidden sync workspace as an outbox.
    // Otherwise the transport folder can be discarded right away.
    if (!pendingDelivery) {
      try {
        await syncBridge.removeAccountFolder(accountId: accountId);
      } catch (_) {}
    }

    await _accountStore.removeLocalAccountById(
      accountId: accountId,
      deleteAccountData: pendingDelivery
          ? _persistence.deleteAccountDataPreservingSyncWorkspace
          : _persistence.deleteAccountData,
    );

    try {
      await _reminderService.clearAll(accountId: accountId);
    } catch (_) {}

    if (pendingDelivery) {
      // Never block or notify the user about delivery. The app-level outbox
      // keeps retrying on the login page, inside another account, and on every
      // later foreground session until every known peer has received it.
      unawaited(_flushPendingDeviceRevocations());
    }
  }

  Future<void> _acknowledgeCurrentRevocation() async {
    final accountId = _accountStore.accountId;
    final deviceId = _accountStore.currentDeviceId;
    final state = _accountStore.syncSnapshot;
    if (accountId == null || deviceId == null || state == null) {
      throw StateError('当前设备的账号撤销信息不可用。');
    }
    final revocation = state.revocations[deviceId];
    if (revocation == null) {
      throw StateError('当前设备没有待确认的撤销记录。');
    }
    await _accountSyncRecordStore.writeRevocationAck(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: revocation.revokedAt,
    );
  }

  Future<void> _adoptBackup(AppBackupData backup) async {
    final account = backup.accountSyncState;
    if (account == null || !account.hasCredentials) {
      throw const FormatException('这份数据包没有可用的账号登录信息。');
    }

    final bootstrapOnly = backup.settings['bootstrapOnly'] == true;
    if (_accountStore.hasActiveLocalAccount(account.accountId)) {
      var hasReadableWorkspace = false;
      try {
        hasReadableWorkspace =
            await _persistence.load(accountId: account.accountId) != null;
      } catch (_) {
        // A damaged local workspace is exactly when re-importing the account
        // package is needed for recovery.
      }
      if (hasReadableWorkspace) {
        throw const FormatException(
          '这个账号已经安全保存在本机，不需要再次加入。'
          '请返回账号选择直接登录；如果要恢复备份，请登录后从设置中导入。',
        );
      }
    }

    if (bootstrapOnly) {
      // First-device handoff intentionally carries only account identity.
      // Write placeholder data so user knows data is being synced in background.
      await _accountStore.adoptSyncedAccount(account);
      await _persistence.save(
        AppBackupData.capture(
          orderStore: OrderStore(),
          productStore: ProductStore(),
          nodePresetStore: NodePresetStore(),
          accountSyncState: account,
          settings: {'bootstrapOnly': true},
        ),
        accountId: account.accountId,
      );
      return;
    }

    if (backup.syncRecords == null) {
      throw const FormatException(
        '这份数据包不包含双端同步历史，不能用于设备加入。'
        '请从原设备重新生成添加设备二维码或完整备份。',
      );
    }

    PortableSyncWorkspaceValidator.validateBackup(
      backup: backup,
      accountId: account.accountId,
    );

    await _persistence.save(
      backup,
      accountId: account.accountId,
    );

    await _accountStore.adoptSyncedAccount(account);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingDeviceRevocationTimer?.cancel();
    _accountStore.removeListener(_onAccountSessionChanged);
    _accountStore.dispose();
    _themeStore.dispose();
    _featureStore.dispose();
    super.dispose();
  }

  Color _onColor(Color color) {
    return color.computeLuminance() > 0.48 ? Colors.black : Colors.white;
  }

  ColorScheme _paletteScheme(Brightness brightness) {
    final palette = _themeStore.palette;
    final colors = palette.previewColors;
    final primary = colors.first;
    final secondary = colors.length > 1 ? colors[1] : primary;
    final tertiary = colors.length > 2 ? colors[2] : secondary;
    final primaryContainer =
        colors.length > 3 ? colors[3] : primary;
    final secondaryContainer =
        colors.length > 4 ? colors[4] : secondary;
    final tertiaryContainer =
        colors.length > 2 ? colors.last : primary;

    final dark = brightness == Brightness.dark;
    final semantic = palette.semanticColorsFor(brightness);

    final base = ColorScheme.fromSeed(
      seedColor: dark ? palette.effectiveDarkSeed : palette.lightSeed,
      brightness: brightness,
    );

    if (semantic != null) {
      final tertiary = Color.lerp(
            semantic.primary,
            semantic.accent,
            0.55,
          ) ??
          semantic.accent;
      return base.copyWith(
        primary: semantic.primary,
        onPrimary: _onColor(semantic.primary),
        primaryContainer: semantic.surfaceAlt,
        onPrimaryContainer: semantic.foreground,
        secondary: semantic.accent,
        onSecondary: _onColor(semantic.accent),
        secondaryContainer: semantic.surfaceAlt,
        onSecondaryContainer: semantic.foreground,
        tertiary: tertiary,
        onTertiary: _onColor(tertiary),
        tertiaryContainer: semantic.surfaceAlt,
        onTertiaryContainer: semantic.foreground,
        surface: semantic.surface,
        onSurface: semantic.foreground,
        surfaceContainerLowest: semantic.background,
        surfaceContainerLow: semantic.surface,
        surfaceContainer: semantic.surfaceAlt,
        surfaceContainerHigh: semantic.surfaceAlt,
        surfaceContainerHighest: semantic.surfaceAlt,
        onSurfaceVariant: semantic.mutedForeground,
        outline: semantic.border,
        outlineVariant: semantic.border,
        inversePrimary: semantic.primary,
        surfaceTint: Colors.transparent,
      );
    }

    return base.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: _onColor(primaryContainer),
      secondary: secondary,
      onSecondary: _onColor(secondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _onColor(secondaryContainer),
      tertiary: tertiary,
      onTertiary: _onColor(tertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _onColor(tertiaryContainer),
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

  ThemeData _lightTheme() {
    final palette = _themeStore.palette;
    return GuildVisualTheme.build(
      _paletteScheme(Brightness.light),
      style: _themeStore.style,
      semanticColors: palette.semanticColorsFor(Brightness.light),
    );
  }

  ThemeData _darkTheme() {
    final palette = _themeStore.palette;
    return GuildVisualTheme.build(
      _paletteScheme(Brightness.dark),
      style: _themeStore.style,
      semanticColors: palette.semanticColorsFor(Brightness.dark),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeStore,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: '冒险者公会',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: _themeStore.mode,
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          home: AccountGate(
            store: _accountStore,
            onAdoptBackup: _adoptBackup,
            onRemoveLocalAccount: _removeLocalAccount,
            onAcknowledgeRevocation: _acknowledgeCurrentRevocation,
            unlockedBuilder: (accountId) => HomePage(
              key: ValueKey(accountId),
              accountId: accountId,
              newsStore: _newsStore,
              themeStore: _themeStore,
              featureStore: _featureStore,
              accountStore: _accountStore,
            ),
          ),
        );
      },
    );
  }
}
