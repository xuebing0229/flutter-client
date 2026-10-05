import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'beta_update_installer.dart';
import 'windows_self_update_launcher.dart';

class WindowsBetaUpdateInstaller implements BetaUpdateInstaller {
  const WindowsBetaUpdateInstaller();

  static final Uri _staticManifestUri = Uri.parse(
    'https://github.com/xuebing0229/release-files/releases/latest/download/app-beta-latest.json',
  );
  static final Uri _releaseApiUri = Uri.parse(
    'https://api.github.com/repos/xuebing0229/release-files/releases/latest',
  );
  static const String _userAgent = 'artist-queue-windows-beta-updater';

  @override
  Future<Map<String, dynamic>> fetchLatestManifest() async {
    try {
      final json = await _fetchJson(_staticManifestUri);
      final normalized = _normalizeStaticManifest(json);
      if (normalized != null) return normalized;
    } catch (_) {
      // Fall back to the GitHub Releases API below.
    }

    return _fetchReleaseApiManifest();
  }

  Map<String, dynamic>? _normalizeStaticManifest(
    Map<String, dynamic> json,
  ) {
    final schema = json['schema'];
    final published = json['published'];
    final channel = json['channel'];
    final version = json['version'];
    final build = json['build'];
    final windowsDownload = json['windows_download_url'];
    final notes = json['notes'];

    if (schema != 1 ||
        published != true ||
        channel != 'beta' ||
        version is! String ||
        version.isEmpty ||
        build is! int ||
        build < 0 ||
        windowsDownload is! String ||
        windowsDownload.isEmpty) {
      return null;
    }

    return <String, dynamic>{
      'schema': 1,
      'channel': 'beta',
      'version': version,
      'build': build,
      'published': true,
      'download_url': windowsDownload,
      'notes': notes is String ? notes : '',
    };
  }

  Future<Map<String, dynamic>> _fetchReleaseApiManifest() async {
    final json = await _fetchJson(
      _releaseApiUri,
      accept: 'application/vnd.github+json',
    );

    if (json['draft'] == true) {
      throw const FormatException('最新 Beta Release 仍是草稿。');
    }

    final tag = json['tag_name'];
    if (tag is! String) {
      throw const FormatException('最新 Beta Release 标签无效。');
    }

    final match = RegExp(
      r'^beta-v(.+)\+(\d+)-run\d+$',
      caseSensitive: false,
    ).firstMatch(tag);
    if (match == null) {
      throw const FormatException('最新 Beta Release 标签格式无效。');
    }

    final version = match.group(1)!;
    final build = int.tryParse(match.group(2)!);
    if (build == null) {
      throw const FormatException('最新 Beta Release 构建号无效。');
    }

    String? downloadUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final rawAsset in assets) {
        if (rawAsset is! Map) continue;
        if (rawAsset['name'] != 'app-windows-beta.zip') continue;
        final rawUrl = rawAsset['browser_download_url'];
        if (rawUrl is String && rawUrl.isNotEmpty) {
          downloadUrl = rawUrl;
          break;
        }
      }
    }

    if (downloadUrl == null) {
      throw const FormatException(
        '最新 Beta Release 没有 app-windows-beta.zip。',
      );
    }

    return <String, dynamic>{
      'schema': 1,
      'channel': 'beta',
      'version': version,
      'build': build,
      'published': true,
      'download_url': downloadUrl,
      'notes': json['body'] is String ? json['body'] : '',
    };
  }

  Future<Map<String, dynamic>> _fetchJson(
    Uri uri, {
    String accept = 'application/json',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, accept)
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (uri.host == 'api.github.com') {
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      }

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '更新地址返回 HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('更新信息不是 JSON 对象。');
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> downloadAndInstall({
    required Uri uri,
    required String fileName,
  }) async {
    if (uri.scheme != 'https' || uri.host.toLowerCase() != 'github.com') {
      throw const FormatException('Windows Beta 只能从 GitHub Releases 下载。');
    }

    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw StateError('无法获取 Windows 下载目录。');
    }

    final updateDirectory = Directory(
      '${downloads.path}${Platform.pathSeparator}AdventurersGuild'
      '${Platform.pathSeparator}updates',
    );
    await updateDirectory.create(recursive: true);

    final safeBaseName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      '${safeBaseName.isEmpty ? 'app-windows-beta' : safeBaseName}.zip',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream');

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(
          '更新文件下载失败：HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final sink = target.openWrite();
      try {
        await response.pipe(sink);
      } catch (_) {
        await sink.close();
        if (await target.exists()) {
          await target.delete();
        }
        rethrow;
      }
    } finally {
      client.close(force: true);
    }

    return const WindowsSelfUpdateLauncher().launch(archive: target);
  }
}
