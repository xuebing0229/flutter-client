import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class LicenseHttpResponse {
  const LicenseHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

/// HTTPS transport for the small activation service.
///
/// Normal requests follow the device's current routing. On Android only, when
/// that route fails at the socket/TLS layer and the request targets the fixed
/// activation host, we make one TLS-verified retry on a validated non-VPN
/// network. This keeps activation/admin access working when a VPN route cannot
/// reach the license VPS without creating a general-purpose VPN bypass.
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
        // Preserve the original error so existing user-facing diagnostics stay
        // meaningful when the direct-network fallback is unavailable too.
        Error.throwWithStackTrace(error, stackTrace);
      }
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
          request =
              await client.getUrl(uri).timeout(const Duration(seconds: 10));
        case 'POST':
          request =
              await client.postUrl(uri).timeout(const Duration(seconds: 10));
        case 'PATCH':
          request =
              await client.patchUrl(uri).timeout(const Duration(seconds: 10));
        case 'DELETE':
          request =
              await client.deleteUrl(uri).timeout(const Duration(seconds: 10));
        default:
          throw ArgumentError.value(method, 'method');
      }

      headers.forEach(request.headers.set);
      if (body != null) request.write(body);

      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final responseBody = await utf8.decoder.bind(response).join();
      return LicenseHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
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

    return LicenseHttpResponse(
      statusCode: statusCode,
      body: responseBody,
    );
  }
}
