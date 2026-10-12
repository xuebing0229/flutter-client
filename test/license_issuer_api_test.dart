import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/license_issuer/license_issuer_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('issuer client follows every ledger page returned by the server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;

      Map<String, dynamic> record({
        required String serial,
        required String accountId,
      }) =>
          <String, dynamic>{
            'serial': serial,
            'accountId': accountId,
            'activationCode': 'AW2.payload.signature',
            'note': '',
            'generatedBy': '测试管理员',
            'createdAt': '2026-10-12T00:00:00.000Z',
            'soldBy': null,
            'soldAt': null,
            'redeemedAt': null,
            'status': 'unused',
          };

      final before = request.uri.queryParameters['before_id'];
      final body = before == null
          ? <String, dynamic>{
              'ok': true,
              'licenses': <Map<String, dynamic>>[
                record(serial: '000101', accountId: 'account-101'),
              ],
              'nextBeforeId': 101,
            }
          : <String, dynamic>{
              'ok': true,
              'licenses': <Map<String, dynamic>>[
                record(serial: '000099', accountId: 'account-099'),
              ],
              'nextBeforeId': null,
            };
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final api = LicenseIssuerApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final records = await api.listLicenses('test-token');

    expect(records.map((item) => item.serial).toList(), <String>[
      '000101',
      '000099',
    ]);
    expect(requests, hasLength(2));
    expect(requests.first.queryParameters['limit'], '500');
    expect(requests.first.queryParameters.containsKey('before_id'), isFalse);
    expect(requests.last.queryParameters['before_id'], '101');
  });

  test('issuer refuses plaintext remote activation endpoints', () async {
    const api = LicenseIssuerApi(baseUrl: 'http://example.com');

    await expectLater(
      api.listLicenses('test-token'),
      throwsA(
        isA<IssuerApiException>()
            .having((error) => error.code, 'code', 'not_configured'),
      ),
    );
  });
}
