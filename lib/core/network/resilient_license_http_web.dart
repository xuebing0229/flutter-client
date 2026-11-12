// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'license_http_models.dart';

class LicenseHttpTransport {
  const LicenseHttpTransport();

  Future<LicenseHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    try {
      final request = await html.HttpRequest.request(
        uri.toString(),
        method: method,
        requestHeaders: headers,
        sendData: body,
      ).timeout(const Duration(seconds: 12));
      return LicenseHttpResponse(
        statusCode: request.status ?? 0,
        body: request.responseText ?? '',
      );
    } on TimeoutException {
      throw const LicenseHttpTransportException(
        '连接激活服务器超时，请检查网络后重试。',
        code: 'timeout',
      );
    } catch (_) {
      throw const LicenseHttpTransportException(
        '暂时无法连接激活服务器，请检查网络后重试。',
        code: 'network_unavailable',
      );
    }
  }
}
