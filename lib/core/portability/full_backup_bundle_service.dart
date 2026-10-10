import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../sync/sync_record_store.dart';
import '../../features/orders/domain/queue_order.dart';
import 'app_backup_data.dart';
import 'data_portability_file_bridge.dart';

class ImportedBackupBundle {
  ImportedBackupBundle({
    required this.backup,
    required this.includesBundledAssets,
    this.extractedDirectory,
  });

  final AppBackupData backup;
  final bool includesBundledAssets;
  final Directory? extractedDirectory;

  Directory? get assetDirectory {
    final root = extractedDirectory;
    if (root == null) return null;
    return Directory(
      '${root.path}${Platform.pathSeparator}assets',
    );
  }

  Future<void> dispose() async {
    final root = extractedDirectory;
    if (root == null) return;
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {
      // Temporary import files can be cleaned by the OS if a handle lingers.
    }
  }
}

class FullBackupBundleService {
  FullBackupBundleService({
    SyncRecordStore? syncRecordStore,
    DataPortabilityFileBridge fileBridge =
        const DataPortabilityFileBridge(),
  }) : _syncRecordStore = syncRecordStore ?? SyncRecordStore(),
       _fileBridge = fileBridge;

  static const String manifestFileName = 'backup.json';
  // The small JSON index may grow with order count, but large image bytes
  // must never be materialized in memory just to validate an archive.
  static const int _maxManifestBytes = 32 * 1024 * 1024;

  final SyncRecordStore _syncRecordStore;
  final DataPortabilityFileBridge _fileBridge;

  Future<bool> exportFullBackup({
    required String accountId,
    required AppBackupData backup,
    required String fileName,
  }) async {
    final syncRoot = await _syncRecordStore.rootDirectory(accountId);
    final assets = await _validatedReferencedAssets(
      backup: backup,
      syncRoot: syncRoot,
    );

    final temporary = await Directory.systemTemp.createTemp(
      'adventurers-guild-backup-',
    );
    final manifest = File(
      '${temporary.path}${Platform.pathSeparator}$manifestFileName',
    );
    final archiveFile = File(
      '${temporary.path}${Platform.pathSeparator}bundle.zip',
    );

    try {
      await manifest.writeAsString(backup.encode(), flush: true);

      final encoder = ZipFileEncoder();
      encoder.create(archiveFile.path);
      try {
        await encoder.addFile(manifest, manifestFileName);
        for (final entry in assets.entries) {
          // Images are already compressed in their source formats. Storing
          // them avoids wasting CPU while still streaming them to the archive.
          await encoder.addFile(
            entry.value,
            entry.key,
            ZipFileEncoder.store,
          );
        }
      } finally {
        await encoder.close();
      }

      return await _fileBridge.exportLocalFile(
        sourcePath: archiveFile.path,
        fileName: fileName,
        mimeType: 'application/zip',
      );
    } finally {
      try {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<ImportedBackupBundle?> pickAndReadBackup() async {
    final picked = await _fileBridge.pickBackupFile();
    if (picked == null) return null;
    return readBackupFile(
      File(picked.path),
      displayName: picked.name,
    );
  }

  Future<ImportedBackupBundle> readBackupFile(
    File file, {
    String? displayName,
  }) async {
    if (!await file.exists()) {
      throw const FormatException('备份文件已经不可用，请重新选择。');
    }

    final name = (displayName ?? file.path).toLowerCase();
    if (name.endsWith('.json')) {
      return ImportedBackupBundle(
        backup: AppBackupData.decode(await file.readAsString()),
        includesBundledAssets: false,
      );
    }

    if (!name.endsWith('.zip')) {
      throw const FormatException('请选择 .zip 完整备份或旧版 .json 备份。');
    }

    final temporary = await Directory.systemTemp.createTemp(
      'adventurers-guild-restore-',
    );
    InputFileStream? input;
    Archive? archive;

    try {
      input = InputFileStream(file.path);
      archive = ZipDecoder().decodeStream(input);

      var hasManifest = false;
      for (final entry in archive) {
        if (entry.isSymbolicLink) {
          throw const FormatException('备份中包含不允许的符号链接。');
        }

        final name = entry.name;
        if (!_isSafeArchivePath(name)) {
          throw const FormatException('备份中包含不安全的文件路径。');
        }

        if (entry.isFile) {
          if (name == manifestFileName) {
            if (hasManifest) {
              throw const FormatException('备份中存在重复的数据清单。');
            }
            hasManifest = true;
            continue;
          }
          if (!_isReferenceAssetPath(name)) {
            throw FormatException('备份中包含未知文件：$name');
          }
        } else if (name != 'assets' &&
            name != 'assets/' &&
            !name.startsWith('assets/order-reference-images')) {
          throw FormatException('备份中包含未知目录：$name');
        }
      }

      if (!hasManifest) {
        throw const FormatException('完整备份缺少 backup.json 数据清单。');
      }

      // Read the small manifest *before* unpacking any large user assets.
      // ZIP metadata alone must not be trusted to authorize unbounded
      // extraction. The user's actual image sizes are declared in the
      // validated manifest; there is deliberately no arbitrary image cap.
      final manifestEntry = archive.findFile(manifestFileName)!;
      if (manifestEntry.size < 0 ||
          manifestEntry.size > _maxManifestBytes) {
        throw const FormatException('备份数据清单体积异常，已拒绝解压。');
      }
      final manifestBytes = manifestEntry.readBytes();
      if (manifestBytes == null ||
          manifestBytes.length > _maxManifestBytes) {
        throw const FormatException('备份数据清单无法安全读取。');
      }
      final backup = AppBackupData.decode(utf8.decode(manifestBytes));
      _validateArchiveAssetInventory(archive, backup);

      await extractArchiveToDisk(archive, temporary.path);

      await _validateExtractedAssets(
        backup: backup,
        extractedRoot: temporary,
      );

      await input.close();
      input = null;
      await archive.clear();
      archive = null;

      return ImportedBackupBundle(
        backup: backup,
        includesBundledAssets: true,
        extractedDirectory: temporary,
      );
    } catch (_) {
      try {
        if (input != null) await input.close();
      } catch (_) {}
      try {
        if (archive != null) await archive.clear();
      } catch (_) {}
      try {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }

  void _validateArchiveAssetInventory(Archive archive, AppBackupData backup) {
    final expectedSizes = <String, int>{};
    for (final referenced in _referencedImages(backup)) {
      final image = referenced.image;
      final path = image.relativePath;
      if (!_isReferenceAssetPath(path) || image.sizeBytes < 0) {
        throw FormatException(
          '${referenced.owner}包含无效参考图记录：${image.fileName}',
        );
      }
      final prior = expectedSizes[path];
      if (prior != null && prior != image.sizeBytes) {
        throw FormatException('参考图路径重复且声明尺寸不一致：$path');
      }
      expectedSizes[path] = image.sizeBytes;
    }

    final found = <String>{};
    for (final entry in archive) {
      if (!entry.isFile || entry.name == manifestFileName) continue;
      final declared = expectedSizes[entry.name];
      if (declared == null) {
        throw FormatException(
          '备份包含未被任何排单或成品引用的资源：${entry.name}',
        );
      }
      // Exporter writes image bytes with ZIP STORE, never deflate. Enforcing
      // that contract also rules out highly compressible archive bombs while
      // preserving legitimate 1GB+ pictures at their original size.
      if (entry.compression != CompressionType.none) {
        throw FormatException('参考图不允许二次 ZIP 压缩：${entry.name}');
      }
      if (entry.size != declared) {
        throw FormatException(
          '备份参考图声明的文件大小与记录不一致：${entry.name}',
        );
      }
      found.add(entry.name);
    }
    final missing = expectedSizes.keys.toSet().difference(found);
    if (missing.isNotEmpty) {
      throw FormatException(
        '完整备份缺少参考图原文件：${missing.first}',
      );
    }
  }

  Future<Map<String, File>> _validatedReferencedAssets({
    required AppBackupData backup,
    required Directory syncRoot,
  }) async {
    final result = <String, File>{};
    final missing = <String>[];

    for (final referenced in _referencedImages(backup)) {
      final image = referenced.image;
      final relativePath = image.relativePath;
      if (!_isReferenceAssetPath(relativePath)) {
        throw FormatException(
          '${referenced.owner}包含无效参考图路径：$relativePath',
        );
      }

      final file = File(_joinRelative(syncRoot.path, relativePath));
      if (!await file.exists()) {
        missing.add(image.fileName);
        continue;
      }

      final actualSize = await file.length();
      if (actualSize != image.sizeBytes) {
        throw StateError(
          '参考图“${image.fileName}”文件大小与记录不一致，'
          '请等待设备同步稳定后再导出。',
        );
      }

      final previous = result[relativePath];
      if (previous != null && previous.path != file.path) {
        throw FormatException('参考图路径重复：$relativePath');
      }
      result[relativePath] = file;
    }

    if (missing.isNotEmpty) {
      final preview = missing.take(3).join('、');
      throw StateError(
        '还有 ${missing.length} 张参考图尚未同步到本机'
        '（$preview${missing.length > 3 ? ' 等' : ''}），'
        '完整备份已取消。请等图片同步完成后再试。',
      );
    }

    return result;
  }

  Future<void> _validateExtractedAssets({
    required AppBackupData backup,
    required Directory extractedRoot,
  }) async {
    final paths = <String>{};

    for (final referenced in _referencedImages(backup)) {
      final image = referenced.image;
      final relativePath = image.relativePath;
      if (!_isReferenceAssetPath(relativePath)) {
        throw FormatException(
          '${referenced.owner}包含无效参考图路径：$relativePath',
        );
      }
      if (!paths.add(relativePath)) {
        continue;
      }

      final file = File(_joinRelative(extractedRoot.path, relativePath));
      if (!await file.exists()) {
        throw FormatException(
          '完整备份缺少参考图原文件：${image.fileName}',
        );
      }
      if (await file.length() != image.sizeBytes) {
        throw FormatException(
          '完整备份中的参考图文件损坏：${image.fileName}',
        );
      }
    }
  }

  // Both order and finished-product reference images live in the same
  // asset directory. All owners must participate in export and import
  // validation or a seemingly successful "full" backup can lose art.
  Iterable<({String owner, OrderReferenceImage image})> _referencedImages(
    AppBackupData backup,
  ) sync* {
    for (final order in backup.orders) {
      for (final image in order.referenceImages) {
        yield (owner: '排单“${order.title}”', image: image);
      }
    }
    for (final product in backup.products) {
      for (final image in product.referenceImages) {
        yield (owner: '成品“${product.title}”', image: image);
      }
    }
  }

  static bool _isSafeArchivePath(String value) {
    if (value.isEmpty || value.contains('\\')) return false;
    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }

    final segments = value
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return false;
    return !segments.any((segment) => segment == '.' || segment == '..');
  }

  static bool _isReferenceAssetPath(String value) {
    if (!_isSafeArchivePath(value)) return false;
    final segments = value.split('/');
    return segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images' &&
        segments.skip(2).every(
          (segment) =>
              segment.isNotEmpty &&
              RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment),
        );
  }

  static String _joinRelative(String root, String relativePath) {
    return <String>[
      root,
      ...relativePath.split('/'),
    ].join(Platform.pathSeparator);
  }
}
