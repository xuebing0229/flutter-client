import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/account/activation_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activation client accepts loopback HTTP only for local tests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    final subscription = server.listen((request) async {
      requestBody = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .map((key, value) => MapEntry(key.toString(), value));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, dynamic>{
        'ok': true,
        'accountId': 'account-test',
        'serial': '000001',
        'redeemedAt': '2026-10-12T00:00:00.000Z',
        'idempotent': true,
      }));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final client = ActivationApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final result = await client.redeem(
      activationCode: 'AW2.payload.signature',
      claimId: 'claim-1234567890',
    );

    expect(result.accountId, 'account-test');
    expect(result.serial, '000001');
    expect(result.idempotent, isTrue);
    expect(requestBody?['activationCode'], 'AW2.payload.signature');
    expect(requestBody?['claimId'], 'claim-1234567890');
  });

  test('activation client refuses plaintext remote endpoints', () async {
    const client = ActivationApiClient(baseUrl: 'http://example.com');

    await expectLater(
      client.redeem(
        activationCode: 'AW2.payload.signature',
        claimId: 'claim-1234567890',
      ),
      throwsA(
        isA<ActivationApiException>()
            .having((error) => error.code, 'code', 'not_configured'),
      ),
    );
  });
}
