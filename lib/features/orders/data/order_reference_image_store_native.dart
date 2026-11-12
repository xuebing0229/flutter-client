import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/sync/embedded_syncthing_bridge.dart';
import '../../../core/sync/sync_record_store.dart';
import '../domain/queue_order.dart';
import 'reference_image_store_common.dart';

class OrderReferenceImageStore {
  OrderReferenceImageStore({
    SyncRecordStore? syncRecordStore,
    DataPortabilityFileBridge fileBridge =
        const DataPortabilityFileBridge(),
    EmbeddedSyncthingBridge syncBridge = const EmbeddedSyncthingBridge(),
  }) : _syncRecordStore = syncRecordStore ?? SyncRecordStore(),
       _fileBridge = fileBridge,
       _syncBridge = syncBridge;

  final SyncRecordStore _syncRecordStore;
  final DataPortabilityFileBridge _fileBridge;
  final EmbeddedSyncthingBridge _syncBridge;
  final Random _random = Random.secure();

  Future<List<OrderReferenceImage>> pickAndImport({
    required String accountId,
    required String orderId,
  }) async {
    final picked = await _fileBridge.pickImages();
    if (picked.isEmpty) return const <OrderReferenceImage>[];

    final imported = <OrderReferenceImage>[];
    try {
      for (final image in picked) {
        imported.add(
          await _importOne(
            accountId: accountId,
            orderId: orderId,
            picked: image,
          ),
        );
      }

      await _requestScan(accountId);
      return imported;
    } catch (_) {
      await deleteImages(
        accountId: accountId,
        images: imported,
        requestScan: false,
      );
      rethrow;
    } finally {
      for (final image in picked) {
        if (!image.temporary) continue;
        try {
          final source = File(image.path);
          if (await source.exists()) await source.delete();
        } catch (_) {
          // Android picker copies are cache files. A lingering handle can be
          // left for normal cache cleanup without affecting the imported copy.
        }
      }
    }
  }

  Future<OrderReferenceImage> _importOne({
    required String accountId,
    required String orderId,
    required PickedLocalImage picked,
  }) async {
    final source = File(picked.path);
    if (!await source.exists()) {
      throw StateError('所选参考图已经不可用，请重新选择。');
    }

    final root = await _syncRecordStore.rootDirectory(accountId);
    final orderKey = ReferenceImageRules.orderKey(orderId);
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}order-reference-images'
      '${Platform.pathSeparator}$orderKey',
    );
    await directory.create(recursive: true);

    final id =
        'ref-${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(0x7fffffff).toRadixString(36)}';
    final detectedExtension =
        ReferenceImageRules.safeExtension(picked.name) ??
        ReferenceImageRules.safeExtension(source.path);
    if (detectedExtension != null &&
        !ReferenceImageRules.supportedImageExtensions.contains(detectedExtension)) {
      throw const FormatException('参考图只支持图片文件。');
    }
    final extension = detectedExtension ?? '.img';
    final storedName = '$id$extension';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$storedName',
    );

    await source.copy(destination.path);
    final sizeBytes = await destination.length();

    return OrderReferenceImage(
      id: id,
      fileName: ReferenceImageRules.displayName(picked.name, extension),
      relativePath:
          'assets/order-reference-images/$orderKey/$storedName',
      addedAt: DateTime.now(),
      sizeBytes: sizeBytes,
    );
  }

  Future<File> localFile({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    final segments =
        ReferenceImageRules.validateReferencePath(image.relativePath);

    final root = await _syncRecordStore.rootDirectory(accountId);
    return File(
      <String>[root.path, ...segments].join(Platform.pathSeparator),
    );
  }

  Future<bool> exists({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    try {
      return await (await localFile(
        accountId: accountId,
        image: image,
      ))
          .exists();
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> readAssetBytes({
    required String accountId,
    required String relativePath,
  }) async {
    final file = await _localAssetFile(
      accountId: accountId,
      relativePath: relativePath,
    );
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> writeAssetBytes({
    required String accountId,
    required String relativePath,
    required Uint8List bytes,
  }) async {
    final file = await _localAssetFile(
      accountId: accountId,
      relativePath: relativePath,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await _requestScan(accountId);
  }

  Future<File> _localAssetFile({
    required String accountId,
    required String relativePath,
  }) async {
    final segments =
        ReferenceImageRules.validateReferencePath(relativePath);
    final root = await _syncRecordStore.rootDirectory(accountId);
    return File(
      <String>[root.path, ...segments].join(Platform.pathSeparator),
    );
  }

  Future<void> deleteImages({
    required String accountId,
    required Iterable<OrderReferenceImage> images,
    bool requestScan = true,
  }) async {
    for (final image in images) {
      try {
        final file = await localFile(accountId: accountId, image: image);
        if (await file.exists()) {
          await file.delete();
        }
        final parent = file.parent;
        if (await parent.exists()) {
          final remaining = await parent.list(followLinks: false).isEmpty;
          if (remaining) {
            await parent.delete();
          }
        }
      } catch (_) {
        // Missing or malformed stale files should not block order editing.
      }
    }

    if (requestScan) {
      await _requestScan(accountId);
    }
  }

  Future<void> deleteAssetPaths({
    required String accountId,
    required Iterable<String> relativePaths,
  }) async {
    for (final relativePath in relativePaths.toSet()) {
      try {
        final segments = ReferenceImageRules.validateAssetPath(relativePath);
        final root = await _syncRecordStore.rootDirectory(accountId);
        final file = File(
          <String>[root.path, ...segments].join(Platform.pathSeparator),
        );
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A stale optional bundle asset must not block the rest of restore.
      }
    }
    await _requestScan(accountId);
  }

  Future<bool> exportImage({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    final file = await localFile(accountId: accountId, image: image);
    if (!await file.exists()) {
      throw StateError('参考图文件还没有同步到本机。');
    }

    return _fileBridge.exportLocalFile(
      sourcePath: file.path,
      fileName: image.fileName,
      mimeType: ReferenceImageRules.mimeType(image.fileName),
    );
  }

  Future<void> _requestScan(String accountId) async {
    try {
      await _syncBridge.requestScan(accountId: accountId);
    } catch (_) {
      // The file remains inside the shared folder and will be found on the
      // next normal Syncthing scan even if an explicit scan is unavailable.
    }
  }

}
