import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_models.dart';

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
                    if (_hasVisibleSyncProgress(status.syncProgress)) ...[
                      const SizedBox(height: 14),
                      _SyncTransferProgress(progress: status.syncProgress!),
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
                        '请选择最终要保留的版本。每个选项都会标明来自哪台设备，并用容易看懂的方式说明差异。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final conflict in coordinator.conflicts)
                        _ConflictTile(
                          view: conflict,
                          coordinator: coordinator,
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

class _SyncTransferProgress extends StatelessWidget {
  const _SyncTransferProgress({required this.progress});

  final Map<String, dynamic> progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completion = ((progress['completion'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100)
        .toDouble();
    final globalBytes = (progress['globalBytes'] as num?)?.toInt() ?? 0;
    final needBytes = (progress['needBytes'] as num?)?.toInt() ?? 0;
    final completedBytes = globalBytes > needBytes
        ? globalBytes - needBytes
        : 0;
    final deviceName = progress['deviceName']?.toString().trim() ?? '';
    final direction = progress['direction']?.toString();
    final completed = completion >= 99.95 && needBytes <= 0;
    final title = completed
        ? '数据已同步'
        : direction == 'sending'
        ? '正在同步到${deviceName.isEmpty ? '另一台设备' : '「$deviceName」'}'
        : '本机正在接收数据';
    final percentText = completion >= 99.95
        ? '100%'
        : '${completion.toStringAsFixed(1)}%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                percentText,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: completion / 100),
          if (globalBytes > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(completedBytes)} / ${_formatBytes(globalBytes)}'
              '${needBytes > 0 ? ' · 剩余 ${_formatBytes(needBytes)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

bool _hasVisibleSyncProgress(Map<String, dynamic>? progress) {
  if (progress == null) return false;
  final completion = ((progress['completion'] as num?)?.toDouble() ?? 100)
      .clamp(0, 100)
      .toDouble();
  final globalBytes = (progress['globalBytes'] as num?)?.toInt() ?? 0;
  final needBytes = (progress['needBytes'] as num?)?.toInt() ?? 0;
  final globalItems = (progress['globalItems'] as num?)?.toInt() ?? 0;
  final needItems = (progress['needItems'] as num?)?.toInt() ?? 0;
  final hasData = globalBytes > 0 || globalItems > 0;
  final unfinished = completion < 99.95 || needBytes > 0 || needItems > 0;
  return hasData && unfinished;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.view,
    required this.coordinator,
    required this.onChoose,
  });

  final SyncConflictView view;
  final SyncCoordinator coordinator;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final candidates = view.conflict.candidates;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _conflictSubject(coordinator, view),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '这项内容在两台设备上不一样，点选你最终想保留的版本。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < candidates.length; index++) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onChoose(index),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _deviceLabel(
                              coordinator,
                              candidates[index].deviceId,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatConflictValue(
                              view.conflict.field,
                              candidates[index].value,
                            ),
                            style: TextStyle(color: colors.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (index != candidates.length - 1)
                  const SizedBox(height: 8),
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

String _deviceLabel(SyncCoordinator coordinator, String deviceId) {
  final device = coordinator.accountStore.syncSnapshot?.devices[deviceId];
  if (device == null) {
    return '未知设备（${_shortDeviceId(deviceId)}）';
  }

  final platform = switch (device.platform.toLowerCase()) {
    'windows' => '电脑',
    'android' || 'ios' => '手机',
    'macos' || 'linux' => '电脑',
    _ => device.platform,
  };
  final local = deviceId == coordinator.deviceId ? ' · 本机' : '';
  return '${device.name} · $platform$local';
}

String _conflictSubject(
  SyncCoordinator coordinator,
  SyncConflictView view,
) {
  switch (view.kind) {
    case SyncEntityKind.settings:
      return '界面设置 · ${view.fieldLabel}';
    case SyncEntityKind.nodePreset:
      for (final preset in coordinator.nodePresetStore.presets) {
        if (preset.id == view.recordId) {
          return '节点预设「${preset.name}」 · ${view.fieldLabel}';
        }
      }
      return '节点预设 · ${view.fieldLabel}';
    case SyncEntityKind.order:
      for (final order in coordinator.orderStore.orders) {
        if (order.id == view.recordId) {
          return '排单「${order.title}」 · ${view.fieldLabel}';
        }
      }
      return '排单 · ${view.fieldLabel}';
    case SyncEntityKind.product:
      for (final product in coordinator.productStore.products) {
        if (product.id == view.recordId) {
          return '成品「${product.title}」 · ${view.fieldLabel}';
        }
      }
      return '成品 · ${view.fieldLabel}';
  }
}

String _formatConflictValue(String field, Object? value) {
  if (value == null) return '未设置';

  if (value is bool) {
    return switch (field) {
      'orderCardView' || 'productCardView' =>
        value ? '使用卡片视图' : '使用列表视图',
      'desktopNavigationOpen' => value ? '导航栏展开' : '导航栏收起',
      'isPinned' => value ? '已置顶' : '未置顶',
      'isArchived' => value ? '已归档' : '未归档',
      SyncRecord.deletedField => value ? '删除这条数据' : '保留这条数据',
      _ => value ? '开启' : '关闭',
    };
  }

  if (field == 'themeMode' && value is String) {
    return switch (value) {
      'light' => '浅色模式',
      'dark' => '深色模式',
      'system' => '跟随系统',
      _ => value,
    };
  }

  if ((field == 'orderSortMode' || field == 'productSortMode') &&
      value is String) {
    return switch (value) {
      'defaultOrder' => '默认排序',
      'income' => '按收入金额',
      'deadline' => '按截稿时间',
      'soldCount' => '按售出数量',
      _ => value,
    };
  }

  if (field == 'nodes' && value is List) {
    return _formatNodeList(value);
  }

  if (field == 'nodePresetSnapshot' && value is Map) {
    final name = value['name']?.toString().trim();
    final nodes = value['nodes'];
    final nodeText = nodes is List ? _formatNodeList(nodes) : '节点内容已修改';
    return name == null || name.isEmpty ? nodeText : '$name：$nodeText';
  }

  if (field == 'tags' && value is List) {
    return value.isEmpty ? '无标签' : value.join('、');
  }
  if (field == 'referenceImages' && value is List) {
    return '${value.length} 张参考图';
  }
  if (field == 'saleRecords' && value is List) {
    return '${value.length} 条售出记录';
  }

  if (value is String) {
    if (value.isEmpty) return '空';
    if (<String>{
      'deadline',
      'completedAt',
      'settledAt',
      'archivedAt',
    }.contains(field)) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        final local = parsed.toLocal();
        String two(int number) => number.toString().padLeft(2, '0');
        return '${local.year}-${two(local.month)}-${two(local.day)} '
            '${two(local.hour)}:${two(local.minute)}';
      }
    }
    return value;
  }

  if (value is num) {
    return switch (field) {
      'price' ||
      'supplementAmount' ||
      'deductionAmount' ||
      'settledIncome' ||
      'customRefundAmount' => '¥$value',
      'onlinePercent' || 'currentNodeProgress' => '$value%',
      _ => value.toString(),
    };
  }

  if (value is List) return '${value.length} 项内容';
  if (value is Map) return '一组设置（${value.length} 项）';

  final text = jsonEncode(value);
  return text.length <= 120 ? text : '${text.substring(0, 117)}…';
}

String _formatNodeList(List<dynamic> nodes) {
  final parts = <String>[];
  for (final item in nodes) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim();
    final progress = item['progressPercent'];
    if (name == null || name.isEmpty) continue;
    parts.add(progress is num ? '$name ${progress.toInt()}%' : name);
  }
  return parts.isEmpty ? '节点列表为空' : parts.join(' → ');
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
