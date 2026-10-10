import 'dart:io';

import 'package:flutter/services.dart';

class IssuerSecretBridge {
  const IssuerSecretBridge();

  static const MethodChannel _channel =
      MethodChannel('app.license_issuer_secret');

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasPrivateKey() async {
    if (!isSupported) return false;
    final result = await _channel.invokeMethod<bool>('hasPrivateKey');
    if (result == null) {
      throw StateError('私钥存储没有返回状态。');
    }
    return result;
  }

  Future<String?> readPrivateKey() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入私钥安全存储。');
    }
    return _channel.invokeMethod<String>('readPrivateKey');
  }

  Future<String?> importPrivateKey() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入私钥文件导入。');
    }
    return _channel.invokeMethod<String>('importPrivateKey');
  }

  Future<void> storePrivateKey(String privateKey) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入私钥安全存储。');
    }
    await _channel.invokeMethod<void>(
      'storePrivateKey',
      <String, dynamic>{'privateKey': privateKey},
    );
  }

  Future<void> clearPrivateKey() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入私钥安全存储。');
    }
    await _channel.invokeMethod<void>('clearPrivateKey');
  }

  Future<bool> hasAdminToken() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasAdminToken') ?? false;
  }

  Future<String?> readAdminToken() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入管理员凭据安全存储。');
    }
    return _channel.invokeMethod<String>('readAdminToken');
  }

  Future<void> storeAdminToken(String token) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入管理员凭据安全存储。');
    }
    await _channel.invokeMethod<void>(
      'storeAdminToken',
      <String, dynamic>{'token': token},
    );
  }

  Future<void> clearAdminToken() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入管理员凭据安全存储。');
    }
    await _channel.invokeMethod<void>('clearAdminToken');
  }

  Future<bool> exportText({
    required String fileName,
    required String content,
    String mimeType = 'text/plain',
  }) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂未接入文件导出。');
    }

    final result = await _channel.invokeMethod<bool>(
      'exportText',
      <String, dynamic>{
        'fileName': fileName,
        'content': content,
        'mimeType': mimeType,
      },
    );
    if (result == null) {
      throw StateError('文件导出没有返回结果。');
    }
    return result;
  }
}
