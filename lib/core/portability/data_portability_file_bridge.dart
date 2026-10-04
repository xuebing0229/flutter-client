import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

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
