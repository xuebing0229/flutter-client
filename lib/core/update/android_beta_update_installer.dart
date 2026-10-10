import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'beta_update_installer.dart';

class AndroidBetaUpdateInstaller implements BetaUpdateInstaller {
  const AndroidBetaUpdateInstaller();

  static const MethodChannel _channel = MethodChannel('app.beta_update');
  static const String _userAgent = 'artist-queue-android-beta-updater';

  @override
  Future<Map<String, dynamic>> fetchLatestManifest() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'fetchLatestManifest',
    );

    if (raw == null) {
      throw StateError('Native update check returned no manifest.');
    }

    return raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Future<Directory> _updateDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}updates',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _safeBaseName(String fileName) {
    final safe = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceFirst(RegExp(r'\.apk$', caseSensitive: false), '');
    return safe.isEmpty ? 'app-android-beta' : safe;
  }

  Future<File> _targetFile(String fileName) async {
    final directory = await _updateDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '${_safeBaseName(fileName)}.apk',
    );
  }

  Future<File> _partialFile(String fileName) async {
    final target = await _targetFile(fileName);
    return File('${target.path}.part');
  }

  Future<void> _cleanupStaleFiles({
    required String keepBaseName,
  }) async {
    final directory = await _updateDirectory();
    final keepApk = '${keepBaseName.toLowerCase()}.apk';
    final keepPart = '$keepApk.part';

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
      if (!name.startsWith('app-beta-')) continue;
      if (!(name.endsWith('.apk') || name.endsWith('.apk.part'))) continue;
      if (name == keepApk || name == keepPart) continue;
      try {
        await entity.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  int? _contentRangeTotal(HttpHeaders headers) {
    final value = headers.value(HttpHeaders.contentRangeHeader);
    if (value == null) return null;
    final match = RegExp(r'/([0-9]+)$').firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
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
      final hash = await Sha256().hashStream(file.openRead());
      final actual = hash.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) return false;
    }

    return true;
  }

  @override
  Future<int?> resumableBytes({required String fileName}) async {
    final partial = await _partialFile(fileName);
    if (await partial.exists()) {
      final length = await partial.length();
      if (length > 0) return length;
    }

    final target = await _targetFile(fileName);
    if (await target.exists()) {
      final length = await target.length();
      if (length > 0) return length;
    }

    return null;
  }

  Future<String> _install(File apk) async {
    final result = await _channel.invokeMethod<String>(
      'installDownloadedUpdate',
      <String, Object?>{'path': apk.path},
    );
    if (result == null) {
      throw StateError('Native update installer returned no status.');
    }
    return result;
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
      throw const FormatException('Android Beta 只能从 GitHub Releases 下载。');
    }

    final baseName = _safeBaseName(fileName);
    final target = await _targetFile(fileName);
    final partial = File('${target.path}.part');
    await _cleanupStaleFiles(keepBaseName: baseName);

    if (await target.exists()) {
      if (await _matchesExpected(
        target,
        expectedSizeBytes: expectedSizeBytes,
        expectedSha256: expectedSha256,
      )) {
        final length = await target.length();
        onProgress?.call(length, expectedSizeBytes ?? length);
        return _install(target);
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
          return _install(target);
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
        // Keep the partial APK so retry/relaunch can resume.
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

    return _install(target);
  }
}
