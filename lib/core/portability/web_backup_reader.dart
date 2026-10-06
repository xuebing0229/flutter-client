import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

import 'app_backup_data.dart';

class WebImportedBackup {
  const WebImportedBackup({
    required this.backup,
    required this.includesAssets,
    required this.assets,
  });

  final AppBackupData backup;
  final bool includesAssets;
  final Map<String, Uint8List> assets;
}

class WebBackupReader {
  const WebBackupReader();

  Future<WebImportedBackup?> pickAndRead() async {
    const typeGroup = XTypeGroup(
      label: '冒险者公会备份',
      extensions: <String>['zip', 'json'],
    );
    final picked = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (picked == null) return null;
    return read(picked);
  }

  Future<WebImportedBackup> read(XFile picked) async {
    final lowerName = picked.name.toLowerCase();
    if (lowerName.endsWith('.json')) {
      return WebImportedBackup(
        backup: AppBackupData.decode(await picked.readAsString()),
        includesAssets: false,
        assets: const <String, Uint8List>{},
      );
    }
    if (!lowerName.endsWith('.zip')) {
      throw const FormatException('请选择 .zip 完整备份或 .json 旧版备份。');
    }

    final bytes = await picked.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    ArchiveFile? manifest;
    final files = <String, ArchiveFile>{};

    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name == 'backup.json') {
        if (manifest != null) {
          throw const FormatException('备份中存在重复的 backup.json。');
        }
        manifest = file;
        continue;
      }
      if (!_safeAssetPath(name)) {
        throw FormatException('备份中包含未知文件：$name');
      }
      files[name] = file;
    }

    if (manifest == null) {
      throw const FormatException('完整备份缺少 backup.json。');
    }

    final backup = AppBackupData.decode(
      utf8.decode(_archiveFileBytes(manifest)),
    );
    final assets = <String, Uint8List>{};
    for (final order in backup.orders) {
      for (final image in order.referenceImages) {
        final file = files[image.relativePath];
        if (file == null) {
          throw FormatException('完整备份缺少参考图：${image.fileName}');
        }
        final assetBytes = _archiveFileBytes(file);
        if (assetBytes.length != image.sizeBytes) {
          throw FormatException('参考图大小校验失败：${image.fileName}');
        }
        assets[image.relativePath] = assetBytes;
      }
    }

    return WebImportedBackup(
      backup: backup,
      includesAssets: true,
      assets: assets,
    );
  }

  Uint8List _archiveFileBytes(ArchiveFile file) => file.content;

  bool _safeAssetPath(String value) {
    if (value.contains('\\') || value.startsWith('/')) return false;
    final segments = value.split('/');
    return segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'order-reference-images' &&
        segments.skip(2).every(
              (segment) =>
                  segment.isNotEmpty &&
                  segment != '.' &&
                  segment != '..' &&
                  RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment),
            );
  }
}
