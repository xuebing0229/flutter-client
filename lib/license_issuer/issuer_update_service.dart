import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class IssuerReleaseInfo {
  const IssuerReleaseInfo({
    required this.version,
    required this.build,
    required this.downloadUri,
    this.sizeBytes,
    this.sha256,
  });

  final String version;
  final int build;
  final Uri downloadUri;
  final int? sizeBytes;
  final String? sha256;
}

typedef IssuerUpdateProgress = void Function(int received, int? total);

class IssuerUpdateService {
  const IssuerUpdateService();

  static final Uri _releasesUri = Uri.parse(
    'https://api.github.com/repos/xuebing0229/release-files/releases?per_page=50',
  );
  static const MethodChannel _installChannel =
      MethodChannel('app.issuer_update');
  static const String _userAgent = 'adventurers-guild-license-issuer';

  Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<IssuerReleaseInfo?> fetchLatest() async {
    final json = await _fetchJsonList(_releasesUri);
    IssuerReleaseInfo? best;

    for (final raw in json) {
      if (raw is! Map) continue;
      final release =
          raw.map((key, value) => MapEntry(key.toString(), value));
      if (release['draft'] == true) continue;

      final tag = release['tag_name'];
      if (tag is! String) continue;
      final match = RegExp(
        r'^issuer-v(.+)\+(\d+)-run\d+$',
        caseSensitive: false,
      ).firstMatch(tag);
      if (match == null) continue;

      final version = match.group(1)!;
      final build = int.tryParse(match.group(2)!);
      if (build == null) continue;

      Uri? downloadUri;
      int? sizeBytes;
      String? sha256;
      final assets = release['assets'];
      if (assets is List) {
        for (final rawAsset in assets) {
          if (rawAsset is! Map || rawAsset['name'] != 'app-license-issuer.apk') {
            continue;
          }
          final url = rawAsset['browser_download_url'];
          if (url is String && url.isNotEmpty) {
            downloadUri = Uri.tryParse(url);
          }
          final size = rawAsset['size'];
          if (size is int && size > 0) sizeBytes = size;
          final digest = rawAsset['digest'];
          if (digest is String &&
              digest.toLowerCase().startsWith('sha256:')) {
            sha256 = digest.substring('sha256:'.length).toLowerCase();
          }
          break;
        }
      }

      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host.toLowerCase() != 'github.com') {
        continue;
      }

      final candidate = IssuerReleaseInfo(
        version: version,
        build: build,
        downloadUri: downloadUri,
        sizeBytes: sizeBytes,
        sha256: sha256,
      );
      if (best == null || candidate.build > best.build) {
        best = candidate;
      }
    }

    return best;
  }

  Future<String> downloadAndInstall(
    IssuerReleaseInfo release, {
    IssuerUpdateProgress? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}issuer-updates',
    );
    await directory.create(recursive: true);

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name != 'issuer-${release.build}.apk' &&
          name != 'issuer-${release.build}.apk.part') {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }

    final target = File(
      '${directory.path}${Platform.pathSeparator}issuer-${release.build}.apk',
    );
    final partial = File('${target.path}.part');

    if (await _matchesExpected(target, release)) {
      final length = await target.length();
      onProgress?.call(length, release.sizeBytes ?? length);
      return _install(target);
    }
    if (await target.exists()) await target.delete();
    if (await partial.exists()) await partial.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(release.downloadUri);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream');

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          '发码器更新下载失败：HTTP ${response.statusCode}',
          uri: release.downloadUri,
        );
      }

      final total = release.sizeBytes ??
          (response.contentLength > 0 ? response.contentLength : null);
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }

      if (!await _matchesExpected(partial, release)) {
        if (await partial.exists()) await partial.delete();
        throw const FormatException('发码器更新包完整性校验失败，请重新下载。');
      }
      await partial.rename(target.path);
    } finally {
      client.close(force: true);
    }

    return _install(target);
  }

  Future<String> _install(File apk) async {
    final result = await _installChannel.invokeMethod<String>(
      'installDownloadedUpdate',
      <String, Object?>{'path': apk.path},
    );
    if (result == null) {
      throw StateError('系统没有返回安装状态。');
    }
    return result;
  }

  Future<bool> _matchesExpected(
    File file,
    IssuerReleaseInfo release,
  ) async {
    if (!await file.exists()) return false;
    if (release.sizeBytes != null &&
        await file.length() != release.sizeBytes) {
      return false;
    }

    final expected = release.sha256;
    if (expected != null && expected.isNotEmpty) {
      final sink = Sha256().newHashSink();
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      final hash = await sink.hash();
      final actual = hash.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual.toLowerCase() != expected.toLowerCase()) return false;
    }
    return true;
  }

  Future<List<dynamic>> _fetchJsonList(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '检查发码器更新失败：HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('发码器更新信息格式无效。');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
