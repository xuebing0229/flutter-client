import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/update/beta_update_session.dart';

class BetaUpdatePage extends StatefulWidget {
  const BetaUpdatePage({super.key});

  @override
  State<BetaUpdatePage> createState() => _BetaUpdatePageState();
}

class _BetaUpdatePageState extends State<BetaUpdatePage> {
  final BetaUpdateSession _updater = BetaUpdateSession.instance;

  @override
  void initState() {
    super.initState();
    _updater.addListener(_onChanged);
    unawaited(_updater.checkForUpdate());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updater.removeListener(_onChanged);
    super.dispose();
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    if (!_updater.supported) {
      return const Scaffold(
        appBar: AppBar(title: Text('拉取更新')),
        body: Center(child: Text('当前版本不提供测试版拉取更新')),
      );
    }

    final latest = _updater.latest;
    final total = _updater.totalBytes;
    final received = _updater.receivedBytes;
    final managed = Platform.isWindows || Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('拉取更新', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本：${_updater.currentVersion} (${_updater.currentBuild})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    latest == null
                        ? '最新版本：尚未获取'
                        : '最新版本：${latest.version} (${latest.build})',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _updater.status,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((_updater.downloading || _updater.paused) && managed) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: total != null && total > 0
                          ? (received / total).clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      total != null && total > 0
                          ? '${((received / total) * 100).clamp(0, 100).toStringAsFixed(0)}% · '
                              '${_formatBytes(received)} / ${_formatBytes(total)}'
                          : '${_formatBytes(received)} 已下载',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: _updater.hasUpdate
                        ? _updater.downloading
                            ? FilledButton.tonalIcon(
                                onPressed:
                                    _updater.canPause ? _updater.pauseDownload : null,
                                icon: const Icon(Icons.pause_rounded),
                                label: Text(
                                  _updater.canPause ? '暂停下载' : '正在暂停…',
                                ),
                              )
                            : FilledButton.icon(
                                onPressed:
                                    _updater.busy ? null : _updater.downloadLatest,
                                icon: Icon(
                                  _updater.installReady
                                      ? Icons.install_desktop_rounded
                                      : _updater.paused
                                          ? Icons.play_arrow_rounded
                                          : Icons.download_rounded,
                                ),
                                label: Text(
                                  _updater.installReady
                                      ? '安装已下载版本'
                                      : _updater.paused
                                          ? '继续下载'
                                          : Platform.isWindows
                                              ? '下载并自动更新'
                                              : '下载并更新',
                                ),
                              )
                        : OutlinedButton.icon(
                            onPressed:
                                _updater.busy ? null : _updater.checkForUpdate,
                            icon: _updater.busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(_updater.busy ? '检查中…' : '检查更新'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
