import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../../core/web/web_platform_bridge.dart';

import '../domain/queue_order.dart';
import 'reference_image_store_common.dart';

class OrderReferenceImageStore {
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

    final orderKey = ReferenceImageRules.orderKey(orderId);
    final imported = <OrderReferenceImage>[];

    try {
      for (final file in files) {
        final extension = ReferenceImageRules.safeExtension(file.name);
        if (extension == null ||
            !ReferenceImageRules.supportedImageExtensions.contains(extension)) {
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
            fileName: ReferenceImageRules.displayName(file.name, extension),
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
    ReferenceImageRules.validateAssetPath(relativePath);
    return webAssetRead(_assetKey(accountId, relativePath));
  }

  Future<void> writeAssetBytes({
    required String accountId,
    required String relativePath,
    required Uint8List bytes,
  }) async {
    ReferenceImageRules.validateAssetPath(relativePath);
    await webAssetWrite(_assetKey(accountId, relativePath), bytes);
  }

  Future<void> deleteImages({
    required String accountId,
    required Iterable<OrderReferenceImage> images,
    bool requestScan = true,
  }) async {
    for (final image in images) {
      try {
        ReferenceImageRules.validateAssetPath(image.relativePath);
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
        ReferenceImageRules.validateAssetPath(path);
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
      mimeType: ReferenceImageRules.mimeType(image.fileName),
    );
    return true;
  }

  String _assetKey(String accountId, String relativePath) =>
      '$accountId\u0000$relativePath';

}
