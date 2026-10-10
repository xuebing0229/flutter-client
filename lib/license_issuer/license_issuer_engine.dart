import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import '../core/account/offline_license.dart';
import 'license_issuer_models.dart';

class LicenseIssuerEngine {
  const LicenseIssuerEngine({
    this.expectedPublicKeyBase64Url = offlineLicensePublicKeyBase64Url,
  });

  final String expectedPublicKeyBase64Url;

  Future<void> validatePrivateKey(String source) async {
    final seed = _decodePrivateSeed(source);
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final challenge = utf8.encode('artist-workbench-license-key-check-v1');
    final signature = await algorithm.sign(
      challenge,
      keyPair: keyPair,
    );

    final verified = await _verifyWithExpectedPublicKey(
      algorithm: algorithm,
      message: challenge,
      signatureBytes: signature.bytes,
    );

    if (!verified) {
      throw const FormatException(
        '这把私钥与冒险者公会内置公钥不匹配，不能用于正式发码。',
      );
    }
  }

  Future<IssuedLicenseRecord> issue({
    required String privateKeySource,
    required String serial,
    String? accountId,
    String note = '',
  }) async {
    final seed = _decodePrivateSeed(privateKeySource);
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);

    final resolvedAccountId = accountId ?? _randomHex(10);
    final payload = utf8.encode(
      jsonEncode(<String, dynamic>{
        'v': 2,
        'a': resolvedAccountId,
        's': serial,
      }),
    );

    final signature = await algorithm.sign(
      payload,
      keyPair: keyPair,
    );

    final verified = await _verifyWithExpectedPublicKey(
      algorithm: algorithm,
      message: payload,
      signatureBytes: signature.bytes,
    );

    if (!verified) {
      throw const FormatException(
        '这把私钥与冒险者公会内置公钥不匹配，不能用于正式发码。',
      );
    }

    return IssuedLicenseRecord(
      accountId: resolvedAccountId,
      serial: serial,
      activationCode:
          'AW2.${_encodeBase64Url(payload)}.${_encodeBase64Url(signature.bytes)}',
      createdAt: DateTime.now().toUtc(),
      note: note.trim(),
    );
  }

  Future<bool> _verifyWithExpectedPublicKey({
    required DartEd25519 algorithm,
    required List<int> message,
    required List<int> signatureBytes,
  }) {
    final publicKeyBytes =
        base64Url.decode(base64Url.normalize(expectedPublicKeyBase64Url));

    return algorithm.verify(
      message,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }
}

List<int> _decodePrivateSeed(String source) {
  final candidates = source
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();

  if (candidates.isEmpty) {
    throw const FormatException('私钥文件为空。');
  }

  try {
    final normalized = base64Url.normalize(candidates.last);
    final bytes = base64Url.decode(normalized);
    if (bytes.length != 32) {
      throw const FormatException('私钥长度不正确。');
    }
    return bytes;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('私钥格式不正确。');
  }
}

String _encodeBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

String _randomHex(int byteLength) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}
