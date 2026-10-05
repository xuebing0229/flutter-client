import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class PickedBackupFile {
  const PickedBackupFile({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class PickedLocalImage {
  const PickedLocalImage({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class DataPortabilityFileBridge {
  const DataPortabilityFileBridge();

  static const MethodChannel _channel =
      MethodChannel('app.data_portability');

  bool get isSupported => Platform.isAndroid || Platform.isWindows;

  Future<bool> exportBackup({
    required String fileName,
    required String content,
  }) async {
    if (Platform.isAndroid) {
      final saved = await _channel.invokeMethod<bool>(
        'exportBackup',
        <String, dynamic>{
          'fileName': fileName,
          'content': content,
        },
      );
      if (saved == null) {
        throw StateError('备份导出没有返回结果。');
      }
      return saved;
    }

    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(
        label: 'JSON backup',
        extensions: <String>['json'],
      );
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (location == null) return false;

      await File(location.path).writeAsString(content, flush: true);
      return true;
    }

    throw UnsupportedError('当前平台暂未接入系统文件导出。');
  }

  Future<String?> importBackup() async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('importBackup');
    }

    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(
        label: 'JSON backup',
        extensions: <String>['json'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (file == null) return null;
      return file.readAsString();
    }

    throw UnsupportedError('当前平台暂未接入系统文件导入。');
  }

  Future<PickedBackupFile?> pickBackupFile() async {
    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(
        label: '完整备份',
        extensions: <String>['zip', 'json'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (file == null) return null;
      return PickedBackupFile(path: file.path, name: file.name);
    }

    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂未接入系统备份文件选择器。');
    }

    final raw = await _channel.invokeMethod<Object?>('pickBackupFile');
    if (raw == null) return null;
    if (raw is! Map || raw['path'] is! String || raw['name'] is! String) {
      throw const FormatException('系统返回的备份文件信息无效。');
    }
    return PickedBackupFile(
      path: raw['path'] as String,
      name: raw['name'] as String,
    );
  }

  Future<String?> pickImage() async {
    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(
        label: '图片',
        extensions: <String>['png', 'jpg', 'jpeg', 'webp'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      return file?.path;
    }
    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂未接入系统图片选择器。');
    }
    return _channel.invokeMethod<String>('pickQrImage');
  }

  Future<List<PickedLocalImage>> pickImages() async {
    if (Platform.isWindows) {
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
      return <PickedLocalImage>[
        for (final file in files)
          PickedLocalImage(
            path: file.path,
            name: file.name,
          ),
      ];
    }

    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂未接入系统图片选择器。');
    }

    final raw = await _channel.invokeListMethod<Object?>(
      'pickReferenceImages',
    );
    if (raw == null) return const <PickedLocalImage>[];

    return <PickedLocalImage>[
      for (final item in raw)
        if (item is Map &&
            item['path'] is String &&
            item['name'] is String)
          PickedLocalImage(
            path: item['path'] as String,
            name: item['name'] as String,
          ),
    ];
  }

  Future<bool> exportLocalFile({
    required String sourcePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    if (Platform.isAndroid) {
      final saved = await _channel.invokeMethod<bool>(
        'exportLocalFile',
        <String, dynamic>{
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      if (saved == null) {
        throw StateError('文件保存没有返回结果。');
      }
      return saved;
    }

    if (Platform.isWindows) {
      final extension = _extensionOf(fileName);
      final location = extension == null
          ? await getSaveLocation(suggestedName: fileName)
          : await getSaveLocation(
              suggestedName: fileName,
              acceptedTypeGroups: <XTypeGroup>[
                XTypeGroup(
                  label: '图片',
                  extensions: <String>[extension],
                ),
              ],
            );
      if (location == null) return false;

      await File(sourcePath).copy(location.path);
      return true;
    }

    throw UnsupportedError('当前平台暂未接入系统文件导出。');
  }

  String? _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  Future<String?> pickQrImage() async {
    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(
        label: '二维码图片',
        extensions: <String>['png', 'jpg', 'jpeg'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      return file?.path;
    }
    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂未接入系统图片选择器。');
    }
    return _channel.invokeMethod<String>('pickQrImage');
  }
}
