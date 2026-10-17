import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/account/account_models.dart';
import '../core/account/account_store.dart';
import '../core/changelog/adventurer_news.dart';
import '../core/features/app_feature_store.dart';
import '../core/notifications/order_deadline_reminder_service.dart';
import '../core/portability/app_backup_data.dart';
import '../core/storage/app_data_persistence.dart';
import '../core/sync/account_sync_record_store.dart';
import '../core/sync/embedded_syncthing_bridge.dart';
import '../core/sync/portable_sync_workspace_validator.dart';
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

class _AppState extends State<App> {
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

  String? _sessionAccountId;
  bool _sessionInitialized = false;

  @override
  void initState() {
    super.initState();
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

    await _publishCurrentDeviceRemoval(
      accountId: accountId,
      syncBridge: syncBridge,
    );

    // Only remove the transport folder after the self-unbind tombstone has
    // been handed to another peer. Local file deletion after this point cannot
    // turn into a synced delete of the tombstone.
    try {
      await syncBridge.removeAccountFolder(accountId: accountId);
    } catch (_) {}

    await _accountStore.removeLocalAccountById(
      accountId: accountId,
      deleteAccountData: _persistence.deleteAccountData,
    );

    try {
      await _reminderService.clearAll(accountId: accountId);
    } catch (_) {}
  }

  Future<void> _publishCurrentDeviceRemoval({
    required String accountId,
    required EmbeddedSyncthingBridge syncBridge,
  }) async {
    final snapshot = _accountStore.localDeviceRemovalSnapshot(accountId);
    if (snapshot == null) return;

    final deviceId = snapshot.deviceId;
    final state = snapshot.state;
    if (state.isRevoked(deviceId)) {
      // A remote device already revoked this installation. Its tombstone is
      // authoritative, so local cleanup does not need to publish another one.
      return;
    }

    final peers = state.activeDevices
        .where((device) => device.id != deviceId)
        .where((device) => (device.syncTransportId?.trim().length ?? 0) >= 20)
        .toList(growable: false);
    final hasOtherActiveDevice =
        state.activeDevices.any((device) => device.id != deviceId);

    // A one-device account has nobody else to notify.
    if (!hasOtherActiveDevice) return;
    if (peers.isEmpty) {
      throw StateError(
        '其他设备还没有可用的同步身份，暂时不能安全解绑。'
        '请先让另一台设备完成一次正常同步后再试。',
      );
    }

    final syncRoot =
        await _accountSyncRecordStore.recordStore.rootPath(accountId);
    final prepared = await syncBridge.prepare(
      accountId: accountId,
      folderPath: syncRoot,
      force: true,
    );
    if (!prepared) {
      throw StateError('当前设备无法启动同步核心，解绑状态还不能发送到其他设备。');
    }

    for (final peer in peers) {
      try {
        await syncBridge.pairDevice(
          accountId: accountId,
          deviceId: peer.syncTransportId!.trim(),
          name: peer.name,
        );
      } catch (_) {
        // Try every known peer. One reachable peer is enough to preserve and
        // forward the self-unbind tombstone to the rest of the mesh.
      }
    }

    await syncBridge.requestScan(accountId: accountId);

    final peerTransportIds = <String>{
      for (final peer in peers) peer.syncTransportId!.trim(),
    };
    final readyPeer = await _waitForReadyRemovalPeer(
      accountId: accountId,
      peerTransportIds: peerTransportIds,
      syncBridge: syncBridge,
    );
    if (!readyPeer) {
      throw StateError(
        '解绑需要至少一台其他设备在线并完成同步连接。'
        '请在另一台设备打开冒险者公会并保持同步后重试。',
      );
    }

    final revokedAt = DateTime.now().toUtc();
    final revokedState = state.copyWith(
      revocations: <String, DeviceRevocation>{
        ...state.revocations,
        deviceId: DeviceRevocation(
          deviceId: deviceId,
          revokedAt: revokedAt,
        ),
      },
    );

    // This is the device's final authoritative account-state write. The
    // matching ack lets peers safely unshare its Syncthing identity after
    // they observe the tombstone.
    await _accountSyncRecordStore.writeSelfRevocation(
      accountId: accountId,
      deviceId: deviceId,
      state: revokedState,
    );
    await _accountSyncRecordStore.writeRevocationAck(
      accountId: accountId,
      deviceId: deviceId,
      revokedAt: revokedAt,
    );
    await syncBridge.requestScan(accountId: accountId);

    // Give Syncthing a bounded chance to finish sending the tiny tombstone.
    // Once it was written after a valid peer handshake it is safe to proceed
    // even if the final progress probe is briefly unavailable.
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final status = await syncBridge.status(accountId: accountId);
      final connected = status.connectedDeviceIds.any(peerTransportIds.contains);
      final completion =
          (status.syncProgress?['completion'] as num?)?.toDouble();
      if (connected && (completion == null || completion >= 99.99)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<bool> _waitForReadyRemovalPeer({
    required String accountId,
    required Set<String> peerTransportIds,
    required EmbeddedSyncthingBridge syncBridge,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final status = await syncBridge.status(accountId: accountId);
      for (final transportId in status.connectedDeviceIds) {
        if (!peerTransportIds.contains(transportId)) continue;
        final remoteState = status.remoteFolderStates[transportId];
        if (remoteState == null || remoteState == 'valid') {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
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
