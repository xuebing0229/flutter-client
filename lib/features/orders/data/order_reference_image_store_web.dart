import 'dart:convert';
import 'dart:html' as html;
import 'dart:indexed_db';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../domain/queue_order.dart';

class OrderReferenceImageStore {
  static const String _databaseName = 'adventurers-guild-web-assets-v1';
  static const String _storeName = 'referenceImages';

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
    final db = await _openDatabase();
    try {
      final transaction = db.transaction(_storeName, 'readonly');
      final store = transaction.objectStore(_storeName);
      final value = await store.getObject(_assetKey(accountId, relativePath));
      await transaction.completed;
      if (value == null) return null;
      if (value is ByteBuffer) return Uint8List.view(value);
      if (value is Uint8List) return value;
      if (value is List<int>) return Uint8List.fromList(value);
      if (value is List) {
        return Uint8List.fromList(value.whereType<num>().map((e) => e.toInt()).toList());
      }
      throw const FormatException('浏览器里的参考图数据格式无效。');
    } finally {
      db.close();
    }
  }

  Future<void> writeAssetBytes({
    required String accountId,
    required String relativePath,
    required Uint8List bytes,
  }) async {
    _validateRelativePath(relativePath);
    final db = await _openDatabase();
    try {
      final transaction = db.transaction(_storeName, 'readwrite');
      final store = transaction.objectStore(_storeName);
      await store.put(bytes, _assetKey(accountId, relativePath));
      await transaction.completed;
    } finally {
      db.close();
    }
  }

  Future<void> deleteImages({
    required String accountId,
    required Iterable<OrderReferenceImage> images,
    bool requestScan = true,
  }) async {
    final paths = <String>[
      for (final image in images) image.relativePath,
    ];
    if (paths.isEmpty) return;

    final db = await _openDatabase();
    try {
      final transaction = db.transaction(_storeName, 'readwrite');
      final store = transaction.objectStore(_storeName);
      for (final path in paths) {
        try {
          _validateRelativePath(path);
          await store.delete(_assetKey(accountId, path));
        } catch (_) {
          // Stale metadata should not block normal editing.
        }
      }
      await transaction.completed;
    } finally {
      db.close();
    }
  }

  Future<void> clearAccountAssets(String accountId) async {
    // Imports overwrite every referenced asset for this account. Do not call
    // ObjectStore.clear(): the IndexedDB store is shared by all local accounts,
    // so clearing it would delete another account's reference images too.
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
    _downloadBytes(
      fileName: image.fileName,
      bytes: bytes,
      mimeType: _mimeType(image.fileName),
    );
    return true;
  }

  void _downloadBytes({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    final blob = html.Blob(<Object>[bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<Database> _openDatabase() async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw StateError('当前浏览器不支持本地参考图存储。');
    }

    return factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final request = event.target as Request;
        final db = request.result as Database;
        if (db.objectStoreNames?.contains(_storeName) != true) {
          db.createObjectStore(_storeName);
        }
      },
    );
  }

  String _assetKey(String accountId, String relativePath) =>
      '$accountId\u0000$relativePath';

  void _validateRelativePath(String value) {
    if (value.contains('\\') || value.startsWith('/')) {
      throw const FormatException('参考图路径无效。');
    }
    final segments = value.split('/');
    final valid = segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images' &&
        segments.skip(2).every(
              (segment) =>
                  segment.isNotEmpty &&
                  segment != '.' &&
                  segment != '..' &&
                  RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment),
            );
    if (!valid) throw const FormatException('参考图路径无效。');
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
