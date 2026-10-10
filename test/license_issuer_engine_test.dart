import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/license_issuer/license_issuer_engine.dart';
import 'package:flutter_app/license_issuer/license_issuer_models.dart';

void main() {
  const privateSeed =
      'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A';
  const publicKey =
      '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo';

  const engine = LicenseIssuerEngine(
    expectedPublicKeyBase64Url: publicKey,
  );

  test('issuer accepts the matching private seed', () async {
    await engine.validatePrivateKey(privateSeed);
  });

  test('issuer rejects a different private seed', () async {
    await expectLater(
      engine.validatePrivateKey(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('issuer history rejects incomplete current-schema records', () {
    expect(
      () => IssuedLicenseRecord.fromJson(<String, dynamic>{
        'accountId': 'account',
        'serial': '000001',
        'activationCode': 'AW1.payload.signature',
        'createdAt': DateTime.utc(2026, 10, 2).toIso8601String(),
        'soldAt': null,
      }),
      throwsFormatException,
    );
  });

  test('issuer can sign a server-assigned account identity', () async {
    const accountId = '00112233445566778899';
    final record = await engine.issue(
      privateKeySource: privateSeed,
      serial: '000123',
      accountId: accountId,
    );

    expect(record.accountId, accountId);
    expect(record.serial, '000123');

    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(record.activationCode.split('.')[1]),
        ),
      ),
    ) as Map<String, dynamic>;
    expect(payload['a'], accountId);
    expect(payload['s'], '000123');
  });

  test('issued code contains a valid Ed25519 signature', () async {
    final record = await engine.issue(
      privateKeySource: privateSeed,
      serial: '000001',
      note: 'test',
    );

    final parts = record.activationCode.split('.');
    expect(parts.length, 3);
    expect(parts.first, 'AW2');
    expect(record.serial, '000001');
    expect(record.activationCode.length, greaterThan(120));

    List<int> decode(String value) =>
        base64Url.decode(base64Url.normalize(value));

    final payload = decode(parts[1]);
    final signature = decode(parts[2]);
    final verified = await DartEd25519().verify(
      payload,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );

    expect(verified, isTrue);
    final decoded = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    expect(decoded['v'], 2);
    expect(decoded['a'], record.accountId);
    expect(decoded['s'], '000001');
  });
}
