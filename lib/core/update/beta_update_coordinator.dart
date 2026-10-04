import '../build/build_channel.dart';
import 'beta_update_installer.dart';
import 'update_manifest.dart';

class BetaUpdateCoordinator {
  BetaUpdateCoordinator({
    required BetaUpdateInstaller installer,
  }) : _installer = installer;

  final BetaUpdateInstaller _installer;

  Future<UpdateManifest> fetchLatest() async {
    if (!isBetaBuild) {
      throw StateError('Beta updater is disabled in stable builds.');
    }

    final json = await _installer.fetchLatestManifest();
    final manifest = UpdateManifest.fromJson(json);

    if (manifest.channel != 'beta') {
      throw const FormatException('返回的更新信息不是 Beta 渠道。');
    }
    if (manifest.downloadUri == null) {
      throw const FormatException('最新测试版没有找到可下载的安装包。');
    }

    return manifest;
  }

  Future<String> downloadAndInstall(UpdateManifest manifest) async {
    if (!isBetaBuild) {
      throw StateError('Beta updater is disabled in stable builds.');
    }

    final uri = manifest.downloadUri;
    if (uri == null) {
      throw StateError('Beta update has no download URL.');
    }

    return _installer.downloadAndInstall(
      uri: uri,
      fileName: 'app-beta-${manifest.build}',
    );
  }

}
