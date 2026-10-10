import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
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
    final windowsSize = json['windows_size_bytes'];
    final windowsSha256 = json['windows_sha256'];
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
      if (windowsSize is int && windowsSize > 0) 'size_bytes': windowsSize,
      if (windowsSha256 is String && windowsSha256.isNotEmpty)
        'sha256': windowsSha256,
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
    int? sizeBytes;
    String? sha256;
    final assets = json['assets'];
    if (assets is List) {
      for (final rawAsset in assets) {
        if (rawAsset is! Map) continue;
        if (rawAsset['name'] != 'app-windows-beta.zip') continue;
        final rawUrl = rawAsset['browser_download_url'];
        if (rawUrl is String && rawUrl.isNotEmpty) {
          downloadUrl = rawUrl;
          final rawSize = rawAsset['size'];
          if (rawSize is int && rawSize > 0) sizeBytes = rawSize;
          final rawDigest = rawAsset['digest'];
          if (rawDigest is String &&
              rawDigest.toLowerCase().startsWith('sha256:')) {
            sha256 = rawDigest.substring('sha256:'.length);
          }
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
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
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

  Future<void> _cleanupStaleUpdateFiles(
    Directory directory, {
    required String keepBaseName,
  }) async {
    if (!await directory.exists()) return;

    final keepZip = '${keepBaseName.toLowerCase()}.zip';
    final keepPart = '$keepZip.part';

    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();

      try {
        if (entity is File &&
            name.startsWith('app-beta-') &&
            (name.endsWith('.zip') || name.endsWith('.zip.part')) &&
            name != keepZip &&
            name != keepPart) {
          await entity.delete();
        } else if (entity is Directory &&
            (name.startsWith('stage-') || name.startsWith('backup-'))) {
          await entity.delete(recursive: true);
        }
      } catch (_) {
        // Cleanup is best-effort. A stale file must not block a new update.
      }
    }
  }

  int? _contentRangeTotal(HttpHeaders headers) {
    final value = headers.value(HttpHeaders.contentRangeHeader);
    if (value == null) return null;
    final match = RegExp(r'/([0-9]+)$').firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<File?> _partialFileFor(String fileName) async {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) return null;

    final updateDirectory = Directory(
      '${downloads.path}${Platform.pathSeparator}AdventurersGuild'
      '${Platform.pathSeparator}updates',
    );
    final safeBaseName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
    final baseName = safeBaseName.isEmpty ? 'app-windows-beta' : safeBaseName;
    return File(
      '${updateDirectory.path}${Platform.pathSeparator}$baseName.zip.part',
    );
  }

  @override
  Future<int?> resumableBytes({required String fileName}) async {
    final partial = await _partialFileFor(fileName);
    if (partial == null || !await partial.exists()) return null;
    final length = await partial.length();
    return length > 0 ? length : null;
  }

  Future<bool> _matchesExpected(
    File file, {
    int? expectedSizeBytes,
    String? expectedSha256,
  }) async {
    if (!await file.exists()) return false;

    if (expectedSizeBytes != null) {
      final actualSize = await file.length();
      if (actualSize != expectedSizeBytes) return false;
    }

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final sink = Sha256().newHashSink();
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      final hash = await sink.hash();
      final actual = hash.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) return false;
    }

    return true;
  }

  @override
  Future<String> downloadAndInstall({
    required Uri uri,
    required String fileName,
    UpdateDownloadProgressCallback? onProgress,
    UpdateDownloadPauseCallback? shouldPause,
    int? expectedSizeBytes,
    String? expectedSha256,
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
    final baseName = safeBaseName.isEmpty ? 'app-windows-beta' : safeBaseName;
    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}$baseName.zip',
    );
    final partial = File('${target.path}.part');

    await _cleanupStaleUpdateFiles(
      updateDirectory,
      keepBaseName: baseName,
    );

    if (await target.exists()) {
      if (await _matchesExpected(
        target,
        expectedSizeBytes: expectedSizeBytes,
        expectedSha256: expectedSha256,
      )) {
        final length = await target.length();
        onProgress?.call(length, expectedSizeBytes ?? length);
        return const WindowsSelfUpdateLauncher().launch(archive: target);
      }
      await target.delete();
    }

    var existingBytes = await partial.exists() ? await partial.length() : 0;
    final client = HttpClient();

    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream');
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          existingBytes > 0) {
        final totalBytes = _contentRangeTotal(response.headers);
        await response.drain<void>();
        if (totalBytes != null && totalBytes == existingBytes) {
          if (!await _matchesExpected(
            partial,
            expectedSizeBytes: expectedSizeBytes,
            expectedSha256: expectedSha256,
          )) {
            if (await partial.exists()) await partial.delete();
            throw const FormatException('更新包完整性校验失败，请重新下载。');
          }
          if (await target.exists()) await target.delete();
          await partial.rename(target.path);
          onProgress?.call(existingBytes, expectedSizeBytes ?? totalBytes);
          return const WindowsSelfUpdateLauncher().launch(archive: target);
        }

        if (await partial.exists()) await partial.delete();
        throw HttpException(
          '服务器拒绝继续当前断点，请重新点击下载。',
          uri: uri,
        );
      }

      final acceptedRange =
          existingBytes > 0 && response.statusCode == HttpStatus.partialContent;
      final acceptedFresh = response.statusCode == HttpStatus.ok;
      if (!acceptedRange && !acceptedFresh) {
        await response.drain<void>();
        throw HttpException(
          '更新文件下载失败：HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      // A redirect target may ignore Range. Restart this build cleanly instead
      // of appending a full response to the partial archive.
      if (!acceptedRange) {
        existingBytes = 0;
      }

      final contentRangeTotal = _contentRangeTotal(response.headers);
      final totalBytes = expectedSizeBytes ??
          contentRangeTotal ??
          (response.contentLength > 0
              ? existingBytes + response.contentLength
              : null);
      var receivedBytes = existingBytes;
      var lastReportedAt = DateTime.fromMillisecondsSinceEpoch(0);

      final sink = partial.openWrite(
        mode: acceptedRange ? FileMode.append : FileMode.write,
      );

      try {
        onProgress?.call(receivedBytes, totalBytes);

        await for (final chunk in response) {
          if (shouldPause?.call() == true) {
            await sink.flush();
            await sink.close();
            onProgress?.call(receivedBytes, totalBytes);
            return 'paused';
          }

          sink.add(chunk);
          receivedBytes += chunk.length;

          final now = DateTime.now();
          final shouldReport =
              totalBytes != null && receivedBytes >= totalBytes ||
              now.difference(lastReportedAt) >=
                  const Duration(milliseconds: 120);
          if (shouldReport) {
            lastReportedAt = now;
            onProgress?.call(receivedBytes, totalBytes);
          }
        }

        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        // Keep the partial archive so retry/relaunch can continue from it.
        rethrow;
      }

      onProgress?.call(receivedBytes, totalBytes);
      if (totalBytes != null && receivedBytes < totalBytes) {
        throw HttpException(
          '更新下载提前结束，已保留断点，可继续下载。',
          uri: uri,
        );
      }

      if (!await _matchesExpected(
        partial,
        expectedSizeBytes: expectedSizeBytes,
        expectedSha256: expectedSha256,
      )) {
        if (await partial.exists()) await partial.delete();
        throw const FormatException('更新包完整性校验失败，请重新下载。');
      }

      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } finally {
      client.close(force: true);
    }

    return const WindowsSelfUpdateLauncher().launch(archive: target);
  }
}
