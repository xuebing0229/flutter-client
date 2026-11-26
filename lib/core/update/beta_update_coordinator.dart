import '../build/build_channel.dart';
import 'beta_update_installer.dart';
import 'update_manifest.dart';

class BetaUpdateCoordinator {
  BetaUpdateCoordinator({
    required BetaUpdateInstaller installer,
  }) : _installer = installer;

  final BetaUpdateInstaller _installer;

  bool get _enabled => isBetaBuild || isInternalBuild;
  String get _expectedChannel => isInternalBuild ? 'internal' : 'beta';
  String get _channelLabel => isInternalBuild ? '内测版' : '测试版';
  String get _filePrefix => isInternalBuild ? 'app-internal' : 'app-beta';

  Future<UpdateManifest> fetchLatest() async {
    if (!_enabled) {
      throw StateError('App updater is disabled in stable builds.');
    }

    final json = await _installer.fetchLatestManifest();
    final manifest = UpdateManifest.fromJson(json);

    if (manifest.channel != _expectedChannel) {
      throw FormatException('返回的更新信息不是$_channelLabel渠道。');
    }
    if (manifest.downloadUri == null) {
      throw FormatException('最新$_channelLabel没有找到可下载的安装包。');
    }

    return manifest;
  }

  Future<int?> resumableBytes(UpdateManifest manifest) {
    return _installer.resumableBytes(
      fileName: '$_filePrefix-${manifest.build}',
    );
  }

  Future<String> downloadAndInstall(
    UpdateManifest manifest, {
    UpdateDownloadProgressCallback? onProgress,
    UpdateDownloadPauseCallback? shouldPause,
  }) async {
    if (!_enabled) {
      throw StateError('App updater is disabled in stable builds.');
    }

    final uri = manifest.downloadUri;
    if (uri == null) {
      throw StateError('App update has no download URL.');
    }

    return _installer.downloadAndInstall(
      uri: uri,
      fileName: '$_filePrefix-${manifest.build}',
      onProgress: onProgress,
      shouldPause: shouldPause,
      expectedSizeBytes: manifest.sizeBytes,
      expectedSha256: manifest.sha256,
    );
  }
}
