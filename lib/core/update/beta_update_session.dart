import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../build/build_channel.dart';
import 'android_beta_update_installer.dart';
import 'beta_update_coordinator.dart';
import 'update_manifest.dart';
import 'windows_beta_update_installer.dart';

/// App-lifetime Beta update state.
///
/// Navigation, theme rebuilds, account switches and SettingsPage disposal must
/// not own the update task. Windows partial downloads are kept on disk and can
/// resume after pause, transient network failure, or a later app launch.
class BetaUpdateSession extends ChangeNotifier {
  BetaUpdateSession._();

  static final BetaUpdateSession instance = BetaUpdateSession._();

  late final BetaUpdateCoordinator? _updater = !isBetaBuild
      ? null
      : Platform.isAndroid
      ? BetaUpdateCoordinator(installer: const AndroidBetaUpdateInstaller())
      : Platform.isWindows
      ? BetaUpdateCoordinator(installer: const WindowsBetaUpdateInstaller())
      : null;

  bool _versionLoaded = false;
  bool _busy = false;
  bool _downloading = false;
  bool _paused = false;
  bool _pauseRequested = false;
  int _receivedBytes = 0;
  int? _totalBytes;
  String _currentVersion = '…';
  int _currentBuild = 0;
  UpdateManifest? _latest;
  String _status = '尚未检查';

  bool get supported => _updater != null;
  bool get busy => _busy;
  bool get downloading => _downloading;
  bool get paused => _paused;
  bool get canPause =>
      Platform.isWindows && _downloading && !_pauseRequested;
  int get receivedBytes => _receivedBytes;
  int? get totalBytes => _totalBytes;
  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;
  UpdateManifest? get latest => _latest;
  String get status => _status;
  bool get hasUpdate => _latest != null && _latest!.build > _currentBuild;

  Future<void> ensureLoaded() async {
    if (_versionLoaded || !supported) return;
    final info = await PackageInfo.fromPlatform();
    _versionLoaded = true;
    _currentVersion = info.version;
    _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    notifyListeners();
  }

  Future<void> checkForUpdate() async {
    final updater = _updater;
    if (updater == null || _busy) return;

    await ensureLoaded();
    _busy = true;
    _status = '正在检查…';
    notifyListeners();

    try {
      final latest = await updater.fetchLatest();
      _latest = latest;
      _status = latest.build > _currentBuild ? '发现新的测试版' : '已经是最新测试版';
    } on SocketException {
      _status = '网络连接失败，请检查当前网络后重试';
    } catch (error) {
      _status = '检查失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void pauseDownload() {
    if (!canPause) return;
    _pauseRequested = true;
    _status = '正在暂停…';
    notifyListeners();
  }

  Future<void> downloadLatest() async {
    final updater = _updater;
    final latest = _latest;
    if (updater == null || latest == null || _busy) return;

    final resuming = Platform.isWindows && _paused;
    _busy = true;
    _downloading = Platform.isWindows;
    _paused = false;
    _pauseRequested = false;
    if (!resuming) {
      _receivedBytes = 0;
      _totalBytes = null;
    }
    if (Platform.isWindows) {
      _status = resuming ? '正在继续下载…' : '正在下载新版…';
    }
    notifyListeners();

    try {
      final result = await updater.downloadAndInstall(
        latest,
        onProgress: Platform.isWindows
            ? (receivedBytes, totalBytes) {
                _receivedBytes = receivedBytes;
                _totalBytes = totalBytes;
                if (totalBytes != null &&
                    totalBytes > 0 &&
                    receivedBytes >= totalBytes) {
                  _status = '下载完成，正在准备自动更新…';
                }
                notifyListeners();
              }
            : null,
        shouldPause: Platform.isWindows ? () => _pauseRequested : null,
      );

      if (result == 'paused') {
        _paused = true;
        _status = '已暂停，可继续下载';
        return;
      }
      if (result == 'permission_required') {
        _status = '请允许“安装未知应用”，返回后再次点击下载';
      } else if (Platform.isWindows) {
        _status = '下载完成，正在启动自动更新…';
      } else {
        _status = '已交给系统下载，完成后会自动打开安装页面';
      }
    } catch (error) {
      if (Platform.isWindows && _receivedBytes > 0) {
        _paused = true;
        _status = '下载中断，已保留断点，点击继续下载';
      } else {
        _status = '更新失败：$error';
      }
    } finally {
      _busy = false;
      _downloading = false;
      _pauseRequested = false;
      notifyListeners();
    }
  }
}
