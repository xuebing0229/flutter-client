import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../../core/web/web_platform_bridge.dart';

import '../domain/queue_order.dart';

class OrderReferenceImageStore {
  static const Set<String> _supportedImageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
  };

  final Random _random = Random.secure();

  Future<List<OrderReferenceImage>> pickAndImport({
    required String accountId,
    required String orderId,
  }) async {
    const typeGroup = XTypeGroup(
      label: '图片',
      extensions: <String>[
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'bmp',
        'heic',
        'heif',
      ],
    );
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (files.isEmpty) return const <OrderReferenceImage>[];

    final orderKey = base64Url
        .encode(utf8.encode(orderId))
        .replaceAll('=', '');
    final imported = <OrderReferenceImage>[];

    try {
      for (final file in files) {
        final extension = _safeExtension(file.name);
        if (extension == null ||
            !_supportedImageExtensions.contains(extension)) {
          throw const FormatException('参考图只支持图片文件。');
        }

        final bytes = await file.readAsBytes();
        final id =
            'ref-${DateTime.now().microsecondsSinceEpoch}-'
            '${_random.nextInt(0x7fffffff).toRadixString(36)}';
        final storedName = '$id$extension';
        final relativePath =
            'assets/order-reference-images/$orderKey/$storedName';
        await writeAssetBytes(
          accountId: accountId,
          relativePath: relativePath,
          bytes: bytes,
        );

        imported.add(
          OrderReferenceImage(
            id: id,
            fileName: file.name.trim().isEmpty
                ? '参考图$extension'
                : file.name,
            relativePath: relativePath,
            addedAt: DateTime.now(),
            sizeBytes: bytes.length,
          ),
        );
      }
    } catch (_) {
      await deleteImages(accountId: accountId, images: imported);
      rethrow;
    }

    return List<OrderReferenceImage>.unmodifiable(imported);
  }

  Future<bool> exists({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    return (await readAssetBytes(
          accountId: accountId,
          relativePath: image.relativePath,
        )) !=
        null;
  }

  Future<Uint8List?> readAssetBytes({
    required String accountId,
    required String relativePath,
  }) async {
    _validateRelativePath(relativePath);
    return webAssetRead(_assetKey(accountId, relativePath));
  }

  Future<void> writeAssetBytes({
    required String accountId,
    required String relativePath,
    required Uint8List bytes,
  }) async {
    _validateRelativePath(relativePath);
    await webAssetWrite(_assetKey(accountId, relativePath), bytes);
  }

  Future<void> deleteImages({
    required String accountId,
    required Iterable<OrderReferenceImage> images,
    bool requestScan = true,
  }) async {
    for (final image in images) {
      try {
        _validateRelativePath(image.relativePath);
        await webAssetDelete(_assetKey(accountId, image.relativePath));
      } catch (_) {
        // Stale metadata should not block normal editing.
      }
    }
  }

  Future<void> deleteAssetPaths({
    required String accountId,
    required Iterable<String> relativePaths,
  }) async {
    for (final path in relativePaths.toSet()) {
      try {
        _validateRelativePath(path);
        await webAssetDelete(_assetKey(accountId, path));
      } catch (_) {
        // A stale optional bundle asset must not block the rest of import.
      }
    }
  }

  Future<void> clearAccountAssets(String accountId) async {
    // The store is shared by every browser-local account. Account-wide cleanup
    // stays explicit so one account can never clear another account's assets.
  }

  Future<bool> exportImage({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    final bytes = await readAssetBytes(
      accountId: accountId,
      relativePath: image.relativePath,
    );
    if (bytes == null) {
      throw StateError('参考图文件还没有导入到当前网页。');
    }
    webDownloadBytes(
      fileName: image.fileName,
      bytes: bytes,
      mimeType: _mimeType(image.fileName),
    );
    return true;
  }

  String _assetKey(String accountId, String relativePath) =>
      '$accountId\u0000$relativePath';

  void _validateRelativePath(String value) {
    if (value.contains('\\') || value.startsWith('/')) {
      throw const FormatException('本地素材路径无效。');
    }
    final segments = value.split('/');
    final safeSegments = segments.length == 4 &&
        segments.skip(2).every(
              (segment) =>
                  segment.isNotEmpty &&
                  segment != '.' &&
                  segment != '..' &&
                  RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment),
            );
    final referenceImage = safeSegments &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images';
    final desktopPetAsset = safeSegments &&
        segments[0] == 'desktop-pet' &&
        segments[1] == 'presets';
    if (!referenceImage && !desktopPetAsset) {
      throw const FormatException('本地素材路径无效。');
    }
  }

  String? _safeExtension(String value) {
    final name = value.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final extension = name.substring(dot + 1).toLowerCase();
    if (extension.length > 8 ||
        !RegExp(r'^[a-z0-9]+$').hasMatch(extension)) {
      return null;
    }
    return '.$extension';
  }

  String _mimeType(String fileName) {
    final extension = _safeExtension(fileName)?.toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      _ => 'application/octet-stream',
    };
  }
}
