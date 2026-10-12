import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/resilient_license_http.dart';

class ActivationApiException implements Exception {
  const ActivationApiException(
    this.message, {
    this.code = 'activation_error',
    this.statusCode,
  });

  final String message;
  final String code;
  final int? statusCode;

  bool get isAlreadyRedeemed => code == 'already_redeemed';

  @override
  String toString() => message;
}

class ActivationRedemption {
  const ActivationRedemption({
    required this.accountId,
    required this.serial,
    required this.redeemedAt,
    required this.idempotent,
  });

  final String accountId;
  final String serial;
  final DateTime redeemedAt;
  final bool idempotent;
}

class ActivationApiClient {
  const ActivationApiClient({
    this.baseUrl = const String.fromEnvironment(
      'ACTIVATION_API_BASE_URL',
      defaultValue: 'https://license.apixb.top',
    ),
  });

  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<ActivationRedemption> redeem({
    required String activationCode,
    required String claimId,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw const ActivationApiException(
        '激活服务尚未配置，请更新到已接入授权服务器的版本。',
        code: 'not_configured',
      );
    }

    final uri = Uri.tryParse('$root/v1/activate');
    final loopbackHttp = uri != null &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1');
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !loopbackHttp)) {
      throw const ActivationApiException(
        '激活服务地址必须使用 HTTPS。',
        code: 'not_configured',
      );
    }

    try {
      final response = await const LicenseHttpTransport().send(
        method: 'POST',
        uri: uri,
        headers: const <String, String>{
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'activationCode': activationCode.trim(),
          'claimId': claimId,
        }),
      );
      Map<String, dynamic>? json;
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          json = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = json?['message'];
        final code = json?['error'];
        throw ActivationApiException(
          message is String && message.isNotEmpty
              ? message
              : '激活服务器拒绝了这次注册。',
          code: code is String && code.isNotEmpty ? code : 'server_rejected',
          statusCode: response.statusCode,
        );
      }

      final accountId = json?['accountId'];
      final serial = json?['serial'];
      final redeemedAt = json?['redeemedAt'];
      final idempotent = json?['idempotent'];
      if (accountId is! String ||
          accountId.isEmpty ||
          serial is! String ||
          serial.isEmpty ||
          redeemedAt is! String ||
          idempotent is! bool) {
        throw const ActivationApiException(
          '激活服务器返回了无法识别的数据。',
          code: 'invalid_response',
        );
      }

      final parsedAt = DateTime.tryParse(redeemedAt);
      if (parsedAt == null) {
        throw const ActivationApiException(
          '激活服务器返回的核销时间无效。',
          code: 'invalid_response',
        );
      }

      return ActivationRedemption(
        accountId: accountId,
        serial: serial,
        redeemedAt: parsedAt,
        idempotent: idempotent,
      );
    } on ActivationApiException {
      rethrow;
    } on SocketException {
      throw const ActivationApiException(
        '暂时无法连接激活服务器，请检查网络后重试。',
        code: 'network_unavailable',
      );
    } on HandshakeException {
      throw const ActivationApiException(
        '激活服务器的安全连接失败，请稍后重试。',
        code: 'tls_error',
      );
    } on HttpException {
      throw const ActivationApiException(
        '激活服务器连接异常，请稍后重试。',
        code: 'network_error',
      );
    } on FormatException {
      throw const ActivationApiException(
        '激活服务器返回了无法识别的数据。',
        code: 'invalid_response',
      );
    } on TimeoutException {
      throw const ActivationApiException(
        '连接激活服务器超时，请检查网络后重试。',
        code: 'timeout',
      );
    }
  }
}
