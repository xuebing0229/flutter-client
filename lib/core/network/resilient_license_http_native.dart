import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'license_http_models.dart';

class LicenseHttpTransport {
  const LicenseHttpTransport();

  static const MethodChannel _directChannel =
      MethodChannel('app.license_direct_https');
  static const String _activationHost = 'license.apixb.top';

  Future<LicenseHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    try {
      try {
        return await _sendNormal(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
        );
      } catch (error, stackTrace) {
        if (!_canRetryDirect(uri, error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        try {
          return await _sendAndroidDirect(
            method: method,
            uri: uri,
            headers: headers,
            body: body,
          );
        } catch (_) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    } on TimeoutException {
      throw const LicenseHttpTransportException(
        '连接激活服务器超时，请检查网络后重试。',
        code: 'timeout',
      );
    } on SocketException {
      throw const LicenseHttpTransportException(
        '暂时无法连接激活服务器，请检查网络后重试。',
        code: 'network_unavailable',
      );
    } on HandshakeException {
      throw const LicenseHttpTransportException(
        '激活服务器的安全连接失败，请稍后重试。',
        code: 'tls_error',
      );
    } on HttpException {
      throw const LicenseHttpTransportException(
        '激活服务器连接异常，请稍后重试。',
        code: 'network_error',
      );
    }
  }

  bool _canRetryDirect(Uri uri, Object error) {
    if (!Platform.isAndroid ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != _activationHost) {
      return false;
    }
    return error is SocketException ||
        error is HandshakeException ||
        error is HttpException ||
        error is TimeoutException;
  }

  Future<LicenseHttpResponse> _sendNormal({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest request;
      switch (method) {
        case 'GET':
          request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
        case 'POST':
          request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
        case 'PATCH':
          request = await client.patchUrl(uri).timeout(const Duration(seconds: 10));
        case 'DELETE':
          request = await client.deleteUrl(uri).timeout(const Duration(seconds: 10));
        default:
          throw ArgumentError.value(method, 'method');
      }
      headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      return LicenseHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<LicenseHttpResponse> _sendAndroidDirect({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    final raw = await _directChannel.invokeMapMethod<String, Object?>(
      'request',
      <String, Object?>{
        'method': method,
        'url': uri.toString(),
        'headers': headers,
        'body': body,
      },
    );
    if (raw == null) {
      throw const HttpException('Direct Android HTTPS returned no response.');
    }
    final statusCode = raw['statusCode'];
    final responseBody = raw['body'];
    if (statusCode is! int || responseBody is! String) {
      throw const HttpException('Direct Android HTTPS response is invalid.');
    }
    return LicenseHttpResponse(statusCode: statusCode, body: responseBody);
  }
}
