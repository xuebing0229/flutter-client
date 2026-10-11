import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/sync/embedded_syncthing_bridge.dart';
import '../../../core/sync/sync_record_store.dart';
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
  // This store instance may physically discard only images it imported into
  // its own unsaved editing session. Existing synced assets are never owned.
  final Set<String> _draftPaths = <String>{};

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
    } catch (_) {
      await discardUnsavedImages(
        accountId: accountId,
        images: imported,
        requestScan: false,
      );
      rethrow;
    }

    await _requestScan(accountId);
    return imported;
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
    final orderKey = base64Url
        .encode(utf8.encode(orderId))
        .replaceAll('=', '');
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
        _safeExtension(picked.name) ?? _safeExtension(source.path);
    if (detectedExtension != null &&
        !_supportedImageExtensions.contains(detectedExtension)) {
      throw const FormatException('参考图只支持图片文件。');
    }
    final extension = detectedExtension ?? '.img';
    final storedName = '$id$extension';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$storedName',
    );

    await source.copy(destination.path);
    final sizeBytes = await destination.length();

    final relativePath = 'assets/order-reference-images/$orderKey/$storedName';
    _draftPaths.add(relativePath);
    return OrderReferenceImage(
      id: id,
      fileName: _displayName(picked.name, extension),
      relativePath: relativePath,
      addedAt: DateTime.now(),
      sizeBytes: sizeBytes,
    );
  }

  Future<File> localFile({
    required String accountId,
    required OrderReferenceImage image,
  }) async {
    final segments = image.relativePath.split('/');
    final valid = segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images' &&
        segments.every(_safeSegment);
    if (!valid || image.relativePath.contains('\\')) {
      throw const FormatException('参考图路径无效。');
    }

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

  /// Permanently delete **only files imported in an unsaved draft**.
  ///
  /// Never call this for images that were already committed to an order or
  /// finished product. An offline bound device can still reference that asset
  /// and Syncthing would propagate the deletion before the reference merge.
  /// Committed images are unlinked in metadata and retained until the
  /// separate SyncAssetGcStore requires unanimous current-protocol device
  /// acknowledgements, matching sync history, and no live references.
  /// After storing the corresponding order/product, these assets become
  /// durable shared data. Discarding them from this store is then forbidden.
  void markCommitted(Iterable<OrderReferenceImage> images) {
    for (final image in images) {
      _draftPaths.remove(image.relativePath);
    }
  }

  Future<void> discardUnsavedImages({
    required String accountId,
    required Iterable<OrderReferenceImage> images,
    bool requestScan = true,
  }) async {
    for (final image in images) {
      // No physical deletion of committed/synced references, even if a
      // caller mistakenly passes one to the discard-only API.
      if (!_draftPaths.remove(image.relativePath)) continue;
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
      mimeType: _mimeType(image.fileName),
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

  bool _safeSegment(String value) {
    if (value.isEmpty || value == '.' || value == '..') return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
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

  String _displayName(String value, String extension) {
    final name = value.split(RegExp(r'[\\/]')).last.trim();
    if (name.isNotEmpty) return name;
    return '参考图$extension';
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
