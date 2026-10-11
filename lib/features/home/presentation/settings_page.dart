import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/account/account_store.dart';
import '../../../core/changelog/adventurer_news.dart';
import '../../../core/features/app_feature_store.dart';
import '../../../core/notifications/order_deadline_reminder_service.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../../core/update/beta_update_session.dart';
import '../../../core/update/update_manifest.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/portability/full_backup_bundle_service.dart';
import '../../focus/state/focus_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/state/order_store.dart';
import '../../products/state/product_store.dart';
import 'adventurer_news_dialog.dart';
import 'reminder_background_guide.dart';
import 'theme_color_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    this.focusStore,
    required this.themeStore,
    required this.featureStore,
    required this.accountStore,
    required this.syncCoordinator,
    required this.onApplyWorkspaceSettings,
    this.onOpenThemeColor,
    super.key,
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final FocusStore? focusStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;
  final AccountStore accountStore;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function(Map<String, dynamic> settings)
  onApplyWorkspaceSettings;
  final VoidCallback? onOpenThemeColor;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final BetaUpdateSession _betaUpdater = BetaUpdateSession.instance;
  final DataPortabilityFileBridge _fileBridge =
      const DataPortabilityFileBridge();
  final OrderDeadlineReminderService _reminderService =
      const OrderDeadlineReminderService();

  bool _reminderBusy = false;
  Map<String, dynamic> _reminderDiagnostics = const <String, dynamic>{};
  bool _backupBusy = false;

  bool get _checking => _betaUpdater.busy;
  bool get _downloadingUpdate => _betaUpdater.downloading;
  bool get _pausedUpdate => _betaUpdater.paused;
  bool get _managedUpdateDownload =>
      Platform.isWindows || Platform.isAndroid;
  int get _downloadReceivedBytes => _betaUpdater.receivedBytes;
  int? get _downloadTotalBytes => _betaUpdater.totalBytes;
  String get _currentVersion => _betaUpdater.currentVersion;
  int get _currentBuild => _betaUpdater.currentBuild;
  UpdateManifest? get _latest => _betaUpdater.latest;
  String get _status => _betaUpdater.status;
  bool get _hasUpdate => _betaUpdater.hasUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _betaUpdater.addListener(_onBetaUpdateChanged);
    unawaited(_betaUpdater.ensureLoaded());
    _refreshReminderDiagnostics();
  }

  void _onBetaUpdateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshReminderDiagnostics();
    }
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

  @override
  void dispose() {
    _betaUpdater.removeListener(_onBetaUpdateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshReminderDiagnostics() async {
    if (!Platform.isAndroid) return;

    try {
      final diagnostics = await _reminderService.getDiagnostics();
      if (!mounted) return;
      setState(() => _reminderDiagnostics = diagnostics);
    } catch (_) {
      // Diagnostics are best-effort and should never block settings.
    }
  }

  Future<void> _runReminderDiagnosticTest() async {
    if (_reminderBusy) return;

    setState(() => _reminderBusy = true);
    try {
      final notificationGranted = await _reminderService.ensurePermission();
      if (!notificationGranted) {
        if (mounted) _showMessage('请先允许通知权限');
        return;
      }

      final diagnostics = await _reminderService.scheduleDiagnosticTest();
      if (!mounted) return;

      setState(() => _reminderDiagnostics = diagnostics);
      _showMessage('已安排 1 分钟测试提醒。离开 App 后等待即可，不用清后台。');
    } catch (error) {
      if (!mounted) return;
      _showMessage('测试提醒安排失败：$error');
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    try {
      await _reminderService.openBatteryOptimizationSettings();
    } catch (error) {
      if (!mounted) return;
      _showMessage('无法打开电池优化设置：$error');
    }
  }

  Future<void> _openExactAlarmSettings() async {
    try {
      await _reminderService.openExactAlarmSettings();
    } catch (error) {
      if (!mounted) return;
      _showMessage('无法打开精确闹钟设置：$error');
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _reminderService.openNotificationSettings();
    } catch (error) {
      if (!mounted) return;
      _showMessage('无法打开提醒通知设置：$error');
    }
  }

  bool _diagnosticBool(String key) => _reminderDiagnostics[key] == true;

  int _diagnosticMillis(String key) {
    final value = _reminderDiagnostics[key];
    return value is num ? value.toInt() : 0;
  }

  String _diagnosticTime(String key) {
    final millis = _diagnosticMillis(key);
    if (millis <= 0) return '—';
    return _formatClockTime(
      DateTime.fromMillisecondsSinceEpoch(millis).toLocal(),
    );
  }

  Widget _buildReminderDiagnosticsCard() {
    final colors = Theme.of(context).colorScheme;
    final loaded = _reminderDiagnostics.isNotEmpty;
    final notificationsEnabled = _diagnosticBool('notificationsEnabled');
    final notificationChannelEnabled = _diagnosticBool(
      'notificationChannelEnabled',
    );
    final exactAlarmGranted = _diagnosticBool('exactAlarmGranted');
    final batteryOptimizationIgnored = _diagnosticBool(
      'batteryOptimizationIgnored',
    );
    final lastFailure =
        (_reminderDiagnostics['lastFailure'] as String?)?.trim() ?? '';
    final savedCount =
        (_reminderDiagnostics['savedReminderCount'] as num?)?.toInt() ?? 0;

    Widget statusLine(String label, bool ok, String good, String bad) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 18,
              color: ok ? colors.primary : colors.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('$label：${ok ? good : bad}')),
          ],
        ),
      );
    }

    final coreReady =
        notificationsEnabled && notificationChannelEnabled && exactAlarmGranted;
    final guidanceText = !loaded
        ? '正在检查系统提醒状态…'
        : !coreReady
        ? '有系统权限尚未准备好，建议先按下面的状态逐项处理。'
        : isAggressiveReminderVendor(_reminderDiagnostics)
        ? '提醒链路本身正常。你的系统在手动划掉 App 后仍可能停止本地提醒，建议锁定最近任务并不要主动划掉。'
        : batteryOptimizationIgnored
        ? '本地提醒配置正常。'
        : '提醒链路正常，但系统仍在对 App 做电池优化，可能导致后台提醒延迟。';

    return _SettingsCard(
      title: '截稿提醒',
      icon: Icons.notifications_active_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: coreReady
                ? colors.primaryContainer.withValues(alpha: 0.55)
                : colors.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    coreReady
                        ? Icons.notifications_active_rounded
                        : Icons.notification_important_outlined,
                    size: 20,
                    color: coreReady
                        ? colors.onPrimaryContainer
                        : colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      guidanceText,
                      style: TextStyle(
                        color: coreReady
                            ? colors.onPrimaryContainer
                            : colors.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (loaded) ...[
            statusLine('通知权限', notificationsEnabled, '正常', '未开启'),
            statusLine('提醒频道', notificationChannelEnabled, '正常', '被系统关闭'),
            statusLine('精确闹钟', exactAlarmGranted, '可用', '不可用'),
            statusLine('电池优化', batteryOptimizationIgnored, '已忽略限制', '仍受系统限制'),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showReminderBackgroundGuide(
                  context: context,
                  reminderService: _reminderService,
                  force: true,
                ),
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text('后台使用说明'),
              ),
              if (!batteryOptimizationIgnored)
                OutlinedButton.icon(
                  onPressed: _openBatteryOptimizationSettings,
                  icon: const Icon(Icons.battery_saver_outlined),
                  label: const Text('电池优化设置'),
                ),
              if (!notificationChannelEnabled && loaded)
                OutlinedButton.icon(
                  onPressed: _openNotificationSettings,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('提醒通知设置'),
                ),
              if (!exactAlarmGranted && loaded)
                OutlinedButton.icon(
                  onPressed: _openExactAlarmSettings,
                  icon: const Icon(Icons.alarm_on_outlined),
                  label: const Text('精确闹钟设置'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('高级诊断'),
            subtitle: const Text('只有提醒异常时才需要看这里'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前已保存 $savedCount 个截稿提醒。',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '最近链路：注册 ${_diagnosticTime('lastScheduledAtMillis')}'
                  ' → Receiver ${_diagnosticTime('lastReceiverAtMillis')}'
                  ' → 通知 ${_diagnosticTime('lastNotifiedAtMillis')}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              if (lastFailure.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最近异常：$lastFailure',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _reminderBusy ? null : _runReminderDiagnosticTest,
                  icon: _reminderBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.timer_outlined),
                  label: Text(_reminderBusy ? '正在安排…' : '1 分钟测试提醒'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _refreshReminderDiagnostics,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新诊断状态'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    if (_backupBusy) return;

    setState(() => _backupBusy = true);

    try {
      final accountId = widget.accountStore.accountId;
      if (accountId == null) {
        throw StateError('当前账号未登录，不能导出完整备份。');
      }

      final snapshot = await widget.syncCoordinator.exportPortableWorkspace();
      final backup = AppBackupData(
        exportedAt: snapshot.exportedAt,
        orders: snapshot.orders,
        products: snapshot.products,
        nodePresets: snapshot.nodePresets,
        focusSessions: snapshot.focusSessions,
        accountSyncState: snapshot.accountSyncState,
        syncRecords: snapshot.syncRecords,
        settings: snapshot.settings,
      );

      final saved = await FullBackupBundleService(
        fileBridge: _fileBridge,
      ).exportFullBackup(
        accountId: accountId,
        backup: backup,
        fileName: _backupFileName(DateTime.now()),
      );

      if (!mounted) return;
      if (saved) {
        _showMessage('完整备份已导出，参考图原文件也已包含');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_backupBusy) return;

    setState(() => _backupBusy = true);
    ImportedBackupBundle? importedBundle;

    try {
      final service = FullBackupBundleService(fileBridge: _fileBridge);
      importedBundle = await service.pickAndReadBackup();
      if (importedBundle == null) return;

      final backup = importedBundle.backup;
      if (backup.syncRecords == null) {
        throw const FormatException(
          '这份备份不包含双端同步历史，不能作为完整备份恢复。'
          '请重新导出完整备份后再恢复。',
        );
      }

      final incomingAccount = backup.accountSyncState;
      final localAccountId = widget.accountStore.accountId;
      if (localAccountId != null && incomingAccount == null) {
        throw const FormatException('这份备份没有账号归属信息，不能覆盖当前账号。');
      }
      if (incomingAccount != null &&
          localAccountId != null &&
          incomingAccount.accountId != localAccountId) {
        throw const FormatException('这份备份属于另一个激活账号，不能导入到当前账号。');
      }
      if (!mounted) return;

      final referenceImageCount = backup.orders.fold<int>(
        0,
        (count, order) => count + order.referenceImages.length,
      );
      final legacyAssetWarning =
          !importedBundle.includesBundledAssets && referenceImageCount > 0
          ? '\n\n注意：这是旧版 JSON 备份，里面只有参考图记录，没有图片原文件。'
                '如果本机和已配对设备也没有这些图片，图片将无法恢复。'
          : '';

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final exported = backup.exportedAt.toLocal();
          return AlertDialog(
            title: const Text('导入完整备份？'),
            content: Text(
              '备份时间：${_formatDateTime(exported)}\n'
              '排单：${backup.orders.length} 条\n'
              '成品：${backup.products.length} 条\n'
              '节点预设：${backup.nodePresets.length} 套\n'
              '专注记录：${backup.focusSessions.length} 条\n'
              '参考图：$referenceImageCount 张\n\n'
              '导入会用备份内容覆盖当前本地数据。'
              '$legacyAssetWarning',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认导入'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) return;

      await widget.syncCoordinator.restorePortableBackupForCurrentWorkspace(
        backup: backup,
        assetSourceDirectory: importedBundle.assetDirectory,
        // This directory was extracted solely for this restore and will be
        // disposed immediately afterwards. Transfer on the same filesystem
        // instead of duplicating potentially gigabytes of reference art.
        transferImportedAssets: importedBundle.includesBundledAssets,
        applyWorkspace: () async {
          backup.restoreInto(
            orderStore: widget.orderStore,
            productStore: widget.productStore,
            nodePresetStore: widget.nodePresetStore,
            focusStore: widget.focusStore ?? widget.syncCoordinator.focusStore,
          );
          // Apply settings inside the coordinator's restore transaction. This
          // makes the post-restore baseline describe the imported workspace,
          // rather than briefly seeding the pre-import UI state.
          await widget.onApplyWorkspaceSettings(backup.settings);
        },
      );

      if (backup.accountSyncState != null) {
        await widget.accountStore.mergeSyncedState(backup.accountSyncState!);
      }

      _showMessage(
        importedBundle.includesBundledAssets
            ? '完整备份已恢复，参考图原文件也已恢复'
            : '旧版数据备份已恢复',
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      _showMessage('备份文件无效：${error.message}');
    } catch (error) {
      if (!mounted) return;
      _showMessage('导入失败：$error');
    } finally {
      await importedBundle?.dispose();
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _checkForBetaUpdate() => _betaUpdater.checkForUpdate();

  Future<void> _downloadLatest() => _betaUpdater.downloadLatest();

  void _pauseDownload() => _betaUpdater.pauseDownload();

  String _formatDownloadBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    const kb = 1024;
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final updater = _betaUpdater.supported ? _betaUpdater : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 16,
          top: 8,
          right: 16,
        ),
        children: [
          _SettingsCard(
            title: '外观',
            icon: Icons.brightness_6_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('夜间模式'),
                const SizedBox(height: 6),
                Text(
                  '可以固定浅色、固定深色，或跟随手机系统切换。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _ThemeModeSelector(store: widget.themeStore),
                const SizedBox(height: 8),
                const Divider(height: 24),
                AnimatedBuilder(
                  animation: widget.themeStore,
                  builder: (context, _) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('UI主题色'),
                      subtitle: Text('当前：${widget.themeStore.palette.name}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ThemePalettePreview(
                            palette: widget.themeStore.palette,
                            width: 58,
                            height: 32,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap:
                          widget.onOpenThemeColor ??
                          () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ThemeColorPage(store: widget.themeStore),
                              ),
                            );
                          },
                    );
                  },
                ),
                const Divider(height: 24),
                AnimatedBuilder(
                  animation: widget.featureStore,
                  builder: (context, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('抽象版'),
                      subtitle: const Text('切换普通版与抽象版；首次进入抽象版会自动打开一次教程。'),
                      value: widget.featureStore.abstractMode,
                      onChanged: (value) {
                        widget.featureStore.setEnabled(
                          AppFeature.abstractMode,
                          value,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: '数据与备份',
            icon: Icons.inventory_2_outlined,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file_rounded),
                  title: const Text('导出完整备份'),
                  subtitle: const Text(
                    '包含工作数据、UI 设置、账号设备记录、完整同步历史和参考图原文件',
                  ),
                  trailing: _backupBusy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _backupBusy ? null : _exportBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('导入完整备份'),
                  subtitle: const Text(
                    '选择完整备份并覆盖当前本地数据；同时恢复参考图原文件',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _backupBusy ? null : _importBackup,
                ),
              ],
            ),
          ),

          if (Platform.isAndroid) ...[
            const SizedBox(height: 14),
            _buildReminderDiagnosticsCard(),
          ],
          const SizedBox(height: 14),
          _SettingsCard(
            title: '冒险者新见闻',
            icon: Icons.auto_stories_rounded,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('查看更新日志'),
              subtitle: const Text('回顾已经加入公会的新功能'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showNewsHistory(),
            ),
          ),
          if (updater != null) ...[
            const SizedBox(height: 14),
            _SettingsCard(
              title: '应用更新',
              icon: Icons.system_update_alt_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前：$_currentVersion ($_currentBuild)'),
                  const SizedBox(height: 6),
                  Text(
                    _latest == null
                        ? '最新：尚未获取'
                        : '最新：${_latest!.version} (${_latest!.build})',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((_downloadingUpdate || _pausedUpdate) &&
                      _managedUpdateDownload) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value:
                          _downloadTotalBytes != null &&
                              _downloadTotalBytes! > 0
                          ? (_downloadReceivedBytes / _downloadTotalBytes!)
                                .clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _downloadTotalBytes != null && _downloadTotalBytes! > 0
                          ? '${((_downloadReceivedBytes / _downloadTotalBytes!) * 100).clamp(0, 100).toStringAsFixed(0)}% · '
                                '${_formatDownloadBytes(_downloadReceivedBytes)} / '
                                '${_formatDownloadBytes(_downloadTotalBytes!)}'
                          : '${_formatDownloadBytes(_downloadReceivedBytes)} 已下载',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _hasUpdate
                        ? _managedUpdateDownload && _downloadingUpdate
                            ? FilledButton.tonalIcon(
                                onPressed: _betaUpdater.canPause
                                    ? _pauseDownload
                                    : null,
                                icon: const Icon(Icons.pause_rounded),
                                label: Text(
                                  _betaUpdater.canPause ? '暂停下载' : '正在暂停…',
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: _checking ? null : _downloadLatest,
                                icon: Icon(
                                  _managedUpdateDownload && _pausedUpdate
                                      ? Icons.play_arrow_rounded
                                      : Icons.download_rounded,
                                ),
                                label: Text(
                                  _managedUpdateDownload && _pausedUpdate
                                      ? '继续下载'
                                      : Platform.isWindows
                                      ? '下载并自动更新'
                                      : '下载并更新',
                                ),
                              )
                        : OutlinedButton.icon(
                            onPressed: _checking ? null : _checkForBetaUpdate,
                            icon: _checking
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(_checking ? '检查中…' : '检查更新'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.store});

  final AppThemeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Row(
          children: [
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.system,
                icon: Icons.settings_brightness_rounded,
                label: '跟随',
                onPressed: () => store.setMode(ThemeMode.system),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: '浅色',
                onPressed: () => store.setMode(ThemeMode.light),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeButton(
                selected: store.mode == ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: '深色',
                onPressed: () => store.setMode(ThemeMode.dark),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? colors.primary : colors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

String _backupFileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'artist-queue-backup-'
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}.zip';
}

String _formatClockTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
