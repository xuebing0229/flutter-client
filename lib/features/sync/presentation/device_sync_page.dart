import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_protocol.dart';

class DeviceSyncPage extends StatefulWidget {
  const DeviceSyncPage({
    required this.coordinator,
    super.key,
  });

  final SyncCoordinator coordinator;

  @override
  State<DeviceSyncPage> createState() => _DeviceSyncPageState();
}

class _DeviceSyncPageState extends State<DeviceSyncPage> {
  String? _activationError;

  @override
  void initState() {
    super.initState();
    _activateTransport();
  }

  Future<void> _activateTransport() async {
    try {
      await widget.coordinator.activateTransport();
    } catch (e) {
      if (mounted) {
        setState(() => _activationError = '同步启动失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = widget.coordinator;

    return AnimatedBuilder(
      animation: coordinator,
      builder: (context, _) {
        final status = coordinator.transportStatus;
        final colors = Theme.of(context).colorScheme;
        final versionNotices = syncDeviceVersionNotices(
          state: coordinator.accountStore.syncSnapshot,
          currentDeviceId: coordinator.accountStore.currentDeviceId,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              '设备同步',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: _activationError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: colors.error),
                        const SizedBox(height: 16),
                        Text(
                          _activationError!,
                          style: TextStyle(color: colors.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() => _activationError = null);
                            _activateTransport();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (versionNotices.isNotEmpty) ...[
                _Card(
                  title: versionNotices.any(
                    (item) => item.status == SyncVersionStatus.incompatible,
                  )
                      ? '版本兼容性警告'
                      : '设备版本不同',
                  icon: Icons.system_update_alt_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final notice in versionNotices) ...[
                        Text(
                          _versionNoticeText(notice),
                          style: TextStyle(
                            color:
                                notice.status == SyncVersionStatus.incompatible
                                ? colors.error
                                : colors.onSurfaceVariant,
                            fontWeight:
                                notice.status == SyncVersionStatus.incompatible
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                        if (notice != versionNotices.last)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _Card(
                title: '同步控制',
                icon: coordinator.syncPaused
                    ? Icons.pause_circle_outline_rounded
                    : Icons.sync_rounded,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    coordinator.syncPaused ? '同步已暂停' : '允许自动同步',
                  ),
                  subtitle: Text(
                    coordinator.syncPaused
                        ? '前台和后台都不会交换设备数据；本地编辑会保留。'
                        : '前台和后台都自动同步设备数据。',
                  ),
                  value: !coordinator.syncPaused,
                  onChanged: coordinator.syncBusy
                      ? null
                      : (enabled) async {
                          try {
                            if (enabled) {
                              await coordinator.resumeTransport();
                            } else {
                              await coordinator.pauseTransport();
                            }
                          } catch (error) {
                            if (context.mounted) {
                              _message(context, '切换同步状态失败：$error');
                            }
                          }
                        },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: coordinator.syncBusy || coordinator.syncPaused
                      ? null
                      : () async {
                          try {
                            await coordinator.refreshNow();
                            if (context.mounted) {
                              _message(context, '已发起同步');
                            }
                          } catch (error) {
                            if (context.mounted) {
                              _message(context, '同步失败：$error');
                            }
                          }
                        },
                  icon: coordinator.syncBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    coordinator.syncPaused
                        ? '同步已暂停'
                        : coordinator.syncBusy
                            ? '同步中…'
                            : '同步',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                title: '同步状态',
                icon: Icons.sync_alt_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusRow(
                      label: '内置同步核心',
                      value: coordinator.syncPaused
                          ? '已暂停'
                          : status.available
                              ? status.running
                                  ? '运行中'
                                  : '正在启动'
                              : '不可用',
                      good: !coordinator.syncPaused &&
                          status.available &&
                          status.running,
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      label: '传输状态',
                      value: coordinator.syncPaused
                          ? '已暂停'
                          : status.connectedDeviceIds.isNotEmpty
                              ? '已连接 ${status.connectedDeviceIds.length} 台设备'
                              : status.available
                                  ? '等待其他设备'
                                  : '尚未建立',
                      good: !coordinator.syncPaused &&
                          status.connectedDeviceIds.isNotEmpty,
                    ),
                    if (status.folderState != null) ...[
                      const SizedBox(height: 8),
                      _StatusRow(
                        label: '数据目录',
                        value: _folderStateLabel(status.folderState!),
                        good: status.folderState == 'idle',
                      ),
                    ],
                    const SizedBox(height: 8),
                    _StatusRow(
                      label: '数据冲突',
                      value: coordinator.conflictCount == 0
                          ? '无'
                          : '${coordinator.conflictCount} 项待确认',
                      good: coordinator.conflictCount == 0,
                    ),
                    if (coordinator.lastError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        coordinator.lastError!,
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                  ],
                ),
              ),
              if (coordinator.conflicts.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Card(
                  title: '同步冲突（${coordinator.conflictCount}）',
                  icon: Icons.rule_folder_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '下面这些字段在不同设备上被同时修改。请选择要保留的版本，确认后会继续同步。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final conflict in coordinator.conflicts)
                        _ConflictTile(
                          view: conflict,
                          onChoose: (index) async {
                            try {
                              await coordinator.resolveConflict(
                                conflict,
                                index,
                              );
                            } catch (error) {
                              if (context.mounted) {
                                _message(context, '处理冲突失败：$error');
                              }
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _versionNoticeText(SyncDeviceVersionNotice notice) {
    final device = notice.device;
    return switch (notice.status) {
      SyncVersionStatus.differentBuild =>
        '${device.name} 为 Beta ${device.appBuild}，本机为 Beta '
            '${notice.localBuild}。当前同步协议兼容，可以继续同步；'
            '建议更新到同一版本。',
      SyncVersionStatus.legacyUnknown =>
        '${device.name} 尚未上报同步协议版本，可能正在使用较旧版本。'
            '同步可以继续，但建议先更新该设备。',
      SyncVersionStatus.incompatible =>
        '${device.name} 的同步协议与本机不兼容。'
            '为避免数据异常，请先把两台设备更新到兼容版本。',
    };
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.good,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          good ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 18,
          color: good ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text('$label：'),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.view,
    required this.onChoose,
  });

  final SyncConflictView view;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final candidates = view.conflict.candidates;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${view.entityLabel} · ${view.fieldLabel}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                view.recordId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < candidates.length; index++) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onChoose(index),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_shortDeviceId(candidates[index].deviceId)}：'
                        '${_formatValue(candidates[index].value)}',
                      ),
                    ),
                  ),
                ),
                if (index != candidates.length - 1)
                  const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
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
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

String _shortDeviceId(String value) {
  if (value.isEmpty) return '未知设备';
  if (value.length <= 12) return value;
  return '${value.substring(0, 7)}…${value.substring(value.length - 4)}';
}

String _formatValue(Object? value) {
  if (value == null) return '未设置';
  if (value is bool) return value ? '开启 / 是' : '关闭 / 否';
  final text = value is String ? value : jsonEncode(value);
  if (text.length <= 120) return text;
  return '${text.substring(0, 117)}…';
}

String _folderStateLabel(String value) {
  return switch (value) {
    'idle' => '已同步',
    'syncing' => '正在同步',
    'scanning' => '正在检查改动',
    'error' => '同步异常',
    _ => value,
  };
}
