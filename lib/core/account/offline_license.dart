import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'account_models.dart';

class ActivationLicense {
  const ActivationLicense({
    required this.accountId,
    required this.serial,
  });

  final String accountId;
  final String serial;
}

const String offlineLicensePublicKeyBase64Url =
    'y4fObOqoJ0gXSs8oyp9av0JiKpYj5HIA-0_PxTZ30eQ';

class OfflineLicenseVerifier {
  const OfflineLicenseVerifier();

  Future<ActivationLicense> verify(String source) async {
    final normalized = source.trim();
    final parts = normalized.split('.');
    if (parts.length != 3) {
      throw const FormatException('激活码格式不正确。');
    }

    final expectedPayloadVersion = switch (parts.first) {
      'AW1' => 1,
      'AW2' => 2,
      _ => null,
    };
    if (expectedPayloadVersion == null) {
      throw const FormatException('激活码格式不正确。');
    }

    final payloadBytes = _decodeBase64Url(parts[1]);
    final signatureBytes = _decodeBase64Url(parts[2]);
    final publicKeyBytes = _decodeBase64Url(offlineLicensePublicKeyBase64Url);

    final algorithm = DartEd25519();
    final verified = await algorithm.verify(
      payloadBytes,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );

    if (!verified) {
      throw const FormatException('激活码无效或已被修改。');
    }

    final decoded = jsonDecode(utf8.decode(payloadBytes));
    if (decoded is! Map) {
      throw const FormatException('激活码内容无效。');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    if (payload['v'] != expectedPayloadVersion) {
      throw const FormatException('激活码版本不匹配。');
    }

    final accountId = payload['a'];
    final serial = payload['s'];
    if (accountId is! String) {
      throw const FormatException('激活码缺少账号身份。');
    }
    if (serial is! String || serial.isEmpty) {
      throw const FormatException('激活码缺少编号。');
    }
    requireValidAccountId(accountId);

    return ActivationLicense(
      accountId: accountId,
      serial: serial,
    );
  }
}

List<int> _decodeBase64Url(String source) {
  final normalized = base64Url.normalize(source);
  return base64Url.decode(normalized);
}
