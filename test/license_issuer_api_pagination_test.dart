import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/license_issuer/license_issuer_api.dart';
import 'package:flutter_app/core/account/activation_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
  });

  Map<String, dynamic> record(int serial) => <String, dynamic>{
        'serial': serial.toString().padLeft(6, '0'),
        'accountId': 'account-$serial',
        'activationCode': 'AW2.test.$serial',
        'createdAt': '2026-10-10T10:00:00.000Z',
        'note': '',
        'generatedBy': 'tester',
      };

  test('all 1201 licenses load across stable keyset pages in order', () async {
    final requestedCursors = <int?>[];
    server.listen((request) async {
      final query = request.uri.queryParameters;
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-admin-token');
      expect(query['limit'], '500');
      final before = int.tryParse(query['beforeId'] ?? '');
      requestedCursors.add(before);
      final max = before == null ? 1201 : before - 1;
      final page = <Map<String, dynamic>>[
        for (var id = max; id > 0 && id > max - 500; id--) record(id),
      ];
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'licenses': page,
        'nextBeforeId': max > 500 ? max - 499 : null,
      }));
      await request.response.close();
    });
    final api =
        LicenseIssuerApi(baseUrl: 'http://127.0.0.1:${server.port}');
    final result = await api.listLicenses('test-admin-token');
    expect(result.length, 1201);
    expect(result.first.serial, '001201');
    expect(result.last.serial, '000001');
    expect(result.map((e) => e.serial).toSet().length, 1201);
    expect(requestedCursors, <int?>[null, 702, 202]);
  });

  test('legacy server single-page response remains readable', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'licenses': [record(1)],
      }));
      await request.response.close();
    });
    final api =
        LicenseIssuerApi(baseUrl: 'http://127.0.0.1:${server.port}');
    final result = await api.listLicenses('test-admin-token');
    expect(result.map((e) => e.serial), <String>['000001']);
  });

  test('old server returning 500 records without cursor fails safely', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'licenses': [for (var id = 500; id >= 1; id--) record(id)],
      }));
      await request.response.close();
    });
    final api = LicenseIssuerApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    await expectLater(
      api.listLicenses('test-admin-token'),
      throwsA(
        isA<IssuerApiException>().having(
          (e) => e.code,
          'code',
          'server_upgrade_required',
        ),
      ),
    );
  });

  test('server returning non-progressing cursor fails rather than looping', () async {
    server.listen((request) async {
      final before = request.uri.queryParameters['beforeId'];
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'licenses': [record(99)],
        'nextBeforeId': before == null ? 99 : 99,
      }));
      await request.response.close();
    });
    final api =
        LicenseIssuerApi(baseUrl: 'http://127.0.0.1:${server.port}');
    await expectLater(
      api.listLicenses('test-admin-token'),
      throwsA(
        isA<IssuerApiException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('NGINX plain-HTML 429 is user-friendly for both issuer and buyer', () async {
    server.listen((request) async {
      request.response.statusCode = 429;
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html><body>429 Too Many Requests</body></html>');
      await request.response.close();
    });
    final issuer = LicenseIssuerApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    await expectLater(
      issuer.listLicenses('test-admin-token'),
      throwsA(isA<IssuerApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.code, 'code', 'rate_limited')),
    );
    final buyer = ActivationApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    await expectLater(
      buyer.redeem(
        activationCode: 'AW2.example',
        claimId: 'test-claim',
      ),
      throwsA(isA<ActivationApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.code, 'code', 'rate_limited')),
    );
  });

  test('duplicate serial returned by a later page is rejected', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final before = request.uri.queryParameters['beforeId'];
      request.response.write(jsonEncode({
        'ok': true,
        'licenses': before == null
            ? [record(10)]
            : [record(10), record(9)],
        'nextBeforeId': before == null ? 10 : null,
      }));
      await request.response.close();
    });
    final api =
        LicenseIssuerApi(baseUrl: 'http://127.0.0.1:${server.port}');
    await expectLater(
      api.listLicenses('test-admin-token'),
      throwsA(isA<IssuerApiException>()),
    );
  });
}
