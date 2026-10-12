import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/network/resilient_license_http.dart';
import 'license_issuer_models.dart';

class IssuerApiException implements Exception {
  const IssuerApiException(
    this.message, {
    this.code = 'issuer_error',
    this.statusCode,
  });

  final String message;
  final String code;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || code == 'unauthorized';
  bool get isStaleRecord => code == 'stale_record';

  @override
  String toString() => message;
}

class IssuerAdminSession {
  const IssuerAdminSession({
    required this.id,
    required this.name,
    this.token,
  });

  final int id;
  final String name;
  final String? token;
}

class ReservedLicenseIdentity {
  const ReservedLicenseIdentity({
    required this.serial,
    required this.accountId,
  });

  final String serial;
  final String accountId;
}

class LicenseIssuerApi {
  const LicenseIssuerApi({
    this.baseUrl = const String.fromEnvironment(
      'ACTIVATION_API_BASE_URL',
      defaultValue: 'https://license.apixb.top',
    ),
  });

  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<IssuerAdminSession> registerAdmin({
    required String setupKey,
    required String name,
  }) async {
    final json = await _request(
      'POST',
      '/v1/admin/register',
      body: <String, dynamic>{
        'setupKey': setupKey,
        'name': name.trim(),
      },
    );
    final token = json['token'];
    final admin = _adminFrom(json['admin']);
    if (token is! String || token.isEmpty) {
      throw const IssuerApiException(
        '服务器没有返回管理员凭据。',
        code: 'invalid_response',
      );
    }
    return IssuerAdminSession(
      id: admin.id,
      name: admin.name,
      token: token,
    );
  }

  Future<IssuerAdminSession> me(String token) async {
    final json = await _request('GET', '/v1/admin/me', token: token);
    return _adminFrom(json['admin']);
  }

  Future<IssuerAdminSession> renameAdmin({
    required String token,
    required String name,
  }) async {
    final json = await _request(
      'PATCH',
      '/v1/admin/me',
      token: token,
      body: <String, dynamic>{'name': name.trim()},
    );
    return _adminFrom(json['admin']);
  }

  Future<List<IssuedLicenseRecord>> listLicenses(String token) async {
    const pageSize = 500;
    final records = <IssuedLicenseRecord>[];
    int? beforeId;

    while (true) {
      final path = beforeId == null
          ? '/v1/licenses?limit=$pageSize'
          : '/v1/licenses?limit=$pageSize&before_id=$beforeId';
      final json = await _request('GET', path, token: token);
      final raw = json['licenses'];
      if (raw is! List) {
        throw const IssuerApiException(
          '服务器返回的发码记录格式无效。',
          code: 'invalid_response',
        );
      }
      records.addAll(<IssuedLicenseRecord>[
        for (final item in raw) _licenseFrom(item),
      ]);

      final next = json['nextBeforeId'];
      if (next == null) break;
      if (next is! int ||
          next < 1 ||
          (beforeId != null && next >= beforeId)) {
        throw const IssuerApiException(
          '服务器返回的发码分页信息无效。',
          code: 'invalid_response',
        );
      }
      beforeId = next;
    }

    return records;
  }

  Future<ReservedLicenseIdentity> reserve({
    required String token,
    String note = '',
  }) async {
    final json = await _request(
      'POST',
      '/v1/licenses/reserve',
      token: token,
      body: <String, dynamic>{'note': note.trim()},
    );
    final raw = json['license'];
    if (raw is! Map) {
      throw const IssuerApiException(
        '服务器没有返回预留编号。',
        code: 'invalid_response',
      );
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final serial = map['serial'];
    final accountId = map['accountId'];
    if (serial is! String ||
        serial.isEmpty ||
        accountId is! String ||
        accountId.isEmpty) {
      throw const IssuerApiException(
        '服务器返回的预留编号格式无效。',
        code: 'invalid_response',
      );
    }
    return ReservedLicenseIdentity(serial: serial, accountId: accountId);
  }

  Future<IssuedLicenseRecord> commit({
    required String token,
    required String accountId,
    required String activationCode,
  }) async {
    final json = await _request(
      'POST',
      '/v1/licenses/$accountId/commit',
      token: token,
      body: <String, dynamic>{'activationCode': activationCode},
    );
    return _licenseFrom(json['license']);
  }

  Future<IssuedLicenseRecord> setSold({
    required String token,
    required String accountId,
    required bool sold,
    int? expectedRevision,
  }) async {
    final json = await _request(
      'POST',
      '/v1/licenses/$accountId/sold',
      token: token,
      body: <String, dynamic>{'sold': sold},
      extraHeaders: _revisionHeader(expectedRevision),
    );
    return _licenseFrom(json['license']);
  }

  Future<IssuedLicenseRecord> updateNote({
    required String token,
    required String accountId,
    required String note,
    int? expectedRevision,
  }) async {
    final json = await _request(
      'PATCH',
      '/v1/licenses/$accountId/note',
      token: token,
      body: <String, dynamic>{'note': note.trim()},
      extraHeaders: _revisionHeader(expectedRevision),
    );
    return _licenseFrom(json['license']);
  }

  Future<void> deleteLicense({
    required String token,
    required String accountId,
    int? expectedRevision,
  }) async {
    await _request(
      'DELETE',
      '/v1/licenses/$accountId',
      token: token,
      extraHeaders: _revisionHeader(expectedRevision),
    );
  }

  Future<IssuedLicenseRecord> importLegacy({
    required String token,
    required IssuedLicenseRecord record,
  }) async {
    final json = await _request(
      'POST',
      '/v1/licenses/import',
      token: token,
      body: <String, dynamic>{
        'activationCode': record.activationCode,
        'note': record.note,
        'generatedBy': record.generatedBy,
        'createdAt': record.createdAt.toUtc().toIso8601String(),
        'soldBy': record.soldBy,
        'soldAt': record.soldAt?.toUtc().toIso8601String(),
      },
    );
    return _licenseFrom(json['license']);
  }

  IssuerAdminSession _adminFrom(Object? raw) {
    if (raw is! Map) {
      throw const IssuerApiException(
        '服务器返回的管理员身份格式无效。',
        code: 'invalid_response',
      );
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = map['id'];
    final name = map['name'];
    if (id is! int || name is! String || name.isEmpty) {
      throw const IssuerApiException(
        '服务器返回的管理员身份格式无效。',
        code: 'invalid_response',
      );
    }
    return IssuerAdminSession(id: id, name: name);
  }

  IssuedLicenseRecord _licenseFrom(Object? raw) {
    if (raw is! Map) {
      throw const IssuerApiException(
        '服务器返回的激活码记录格式无效。',
        code: 'invalid_response',
      );
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final normalized = <String, dynamic>{
      'accountId': map['accountId'],
      'serial': map['serial'],
      'activationCode': map['activationCode'],
      'createdAt': map['createdAt'],
      'revision': map['revision'] ?? 0,
      'note': map['note'] ?? '',
      'generatedBy': map['generatedBy'] ?? '',
      'soldAt': map['soldAt'],
      'soldBy': map['soldBy'],
      'redeemedAt': map['redeemedAt'],
    };
    try {
      return IssuedLicenseRecord.fromJson(normalized);
    } on FormatException catch (error) {
      throw IssuerApiException(
        error.message,
        code: 'invalid_response',
      );
    }
  }

  Map<String, String> _revisionHeader(int? revision) {
    if (revision == null || revision < 1) return const <String, String>{};
    return <String, String>{'X-License-Revision': revision.toString()};
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw const IssuerApiException(
        '激活服务器尚未配置。',
        code: 'not_configured',
      );
    }

    final uri = Uri.tryParse('$root$path');
    final loopbackHttp = uri != null &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1');
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !loopbackHttp)) {
      throw const IssuerApiException(
        '激活服务器地址必须使用 HTTPS。',
        code: 'not_configured',
      );
    }

    try {
      final headers = <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        if (token != null && token.trim().isNotEmpty)
          HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
        if (body != null) HttpHeaders.contentTypeHeader: 'application/json',
        ...extraHeaders,
      };
      final response = await const LicenseHttpTransport().send(
        method: method,
        uri: uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );

      Map<String, dynamic> json = <String, dynamic>{};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          json = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = json['message'];
        final code = json['error'];
        throw IssuerApiException(
          message is String && message.isNotEmpty
              ? message
              : '激活服务器拒绝了这次操作。',
          code: code is String && code.isNotEmpty ? code : 'server_rejected',
          statusCode: response.statusCode,
        );
      }
      return json;
    } on IssuerApiException {
      rethrow;
    } on SocketException {
      throw const IssuerApiException(
        '暂时无法连接激活服务器，请检查网络后重试。',
        code: 'network_unavailable',
      );
    } on HandshakeException {
      throw const IssuerApiException(
        '激活服务器的安全连接失败。',
        code: 'tls_error',
      );
    } on HttpException {
      throw const IssuerApiException(
        '激活服务器连接异常。',
        code: 'network_error',
      );
    } on TimeoutException {
      throw const IssuerApiException(
        '连接激活服务器超时。',
        code: 'timeout',
      );
    } on FormatException {
      throw const IssuerApiException(
        '激活服务器返回了无法识别的数据。',
        code: 'invalid_response',
      );
    }
  }
}
