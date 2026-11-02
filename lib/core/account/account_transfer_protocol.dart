import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../sync/public_relay_client.dart';

class AccountTransferDescriptor {
  const AccountTransferDescriptor({
    required this.encryptionKey,
    required this.sourceDeviceId,
    required this.folderId,
  });

  final String encryptionKey;
  final String sourceDeviceId;
  final String folderId;

  String encode() {
    if (decodeAccountTransferKey(encryptionKey) == null) {
      throw StateError('设备加入二维码必须包含有效的加密密钥。');
    }
    if (sourceDeviceId.trim().length < 20) {
      throw StateError('设备加入二维码缺少有效的同步设备 ID。');
    }
    if (!_validBootstrapFolderId(folderId)) {
      throw StateError('设备加入二维码缺少有效的临时同步目录。');
    }

    return jsonEncode(<String, dynamic>{
      'kind': 'artist_queue_account_transfer_syncthing',
      'version': 1,
      'sourceDeviceId': sourceDeviceId,
      'folderId': folderId,
      'key': encryptionKey,
    });
  }

  factory AccountTransferDescriptor.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['kind'] != 'artist_queue_account_transfer_syncthing' ||
        decoded['version'] != 1) {
      throw const FormatException('这不是有效的设备加入二维码。');
    }

    final sourceDeviceId = decoded['sourceDeviceId'];
    final folderId = decoded['folderId'];
    final rawKey = decoded['key'];

    if (sourceDeviceId is! String || sourceDeviceId.trim().length < 20) {
      throw const FormatException('设备加入二维码缺少有效的同步设备 ID。');
    }
    if (folderId is! String || !_validBootstrapFolderId(folderId)) {
      throw const FormatException('设备加入二维码缺少有效的临时同步目录。');
    }
    if (rawKey is! String || decodeAccountTransferKey(rawKey) == null) {
      throw const FormatException('设备加入二维码缺少有效的加密密钥。');
    }

    return AccountTransferDescriptor(
      encryptionKey: rawKey,
      sourceDeviceId: sourceDeviceId.trim(),
      folderId: folderId,
    );
  }
}

class AccountTransferResponseCode {
  const AccountTransferResponseCode({
    required this.folderId,
    required this.sourceDeviceId,
    required this.receiverDeviceId,
    required this.receiverName,
    required this.proof,
    this.receiverAppDeviceId,
    this.receiverPlatform,
    this.bindingProof,
  });

  final String folderId;
  final String sourceDeviceId;
  final String receiverDeviceId;
  final String receiverName;
  final String proof;

  /// v175+: provisional app-device identity created before the permanent
  /// account folder is shared. Older response codes omit these fields.
  final String? receiverAppDeviceId;
  final String? receiverPlatform;
  final String? bindingProof;

  static Future<AccountTransferResponseCode> create({
    required AccountTransferDescriptor descriptor,
    required String receiverDeviceId,
    required String receiverName,
    required String receiverAppDeviceId,
    required String receiverPlatform,
  }) async {
    final normalizedReceiverId = receiverDeviceId.trim();
    if (normalizedReceiverId.length < 20) {
      throw const FormatException('无法读取新设备的同步身份。');
    }
    final keyBytes = decodeAccountTransferKey(descriptor.encryptionKey);
    if (keyBytes == null) {
      throw const FormatException('设备加入二维码的加密密钥无效。');
    }

    final name = receiverName.trim();
    if (name.isEmpty) {
      throw const FormatException('无法读取新设备名称。');
    }
    final appDeviceId = receiverAppDeviceId.trim();
    final platform = receiverPlatform.trim();
    if (appDeviceId.length < 16 || platform.isEmpty) {
      throw const FormatException('无法建立新设备的应用身份。');
    }
    final proofBytes = await _responseProof(
      keyBytes: keyBytes,
      folderId: descriptor.folderId,
      sourceDeviceId: descriptor.sourceDeviceId,
      receiverDeviceId: normalizedReceiverId,
      receiverName: name,
    );
    final bindingProofBytes = await _responseBindingProof(
      keyBytes: keyBytes,
      folderId: descriptor.folderId,
      sourceDeviceId: descriptor.sourceDeviceId,
      receiverDeviceId: normalizedReceiverId,
      receiverName: name,
      receiverAppDeviceId: appDeviceId,
      receiverPlatform: platform,
    );

    return AccountTransferResponseCode(
      folderId: descriptor.folderId,
      sourceDeviceId: descriptor.sourceDeviceId,
      receiverDeviceId: normalizedReceiverId,
      receiverName: name,
      proof: encodeAccountTransferBase64Url(proofBytes),
      receiverAppDeviceId: appDeviceId,
      receiverPlatform: platform,
      bindingProof: encodeAccountTransferBase64Url(bindingProofBytes),
    );
  }

  String encode() {
    if (!_validBootstrapFolderId(folderId) ||
        sourceDeviceId.trim().length < 20 ||
        receiverDeviceId.trim().length < 20 ||
        receiverName.trim().isEmpty ||
        proof.trim().isEmpty) {
      throw StateError('设备回应码内容无效。');
    }

    return jsonEncode(<String, dynamic>{
      'kind': 'artist_queue_account_transfer_response',
      'version': 1,
      'folderId': folderId,
      'sourceDeviceId': sourceDeviceId,
      'receiverDeviceId': receiverDeviceId,
      'receiverName': receiverName,
      'proof': proof,
      if (receiverAppDeviceId?.trim().isNotEmpty == true)
        'receiverAppDeviceId': receiverAppDeviceId,
      if (receiverPlatform?.trim().isNotEmpty == true)
        'receiverPlatform': receiverPlatform,
      if (bindingProof?.trim().isNotEmpty == true)
        'bindingProof': bindingProof,
    });
  }

  factory AccountTransferResponseCode.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['kind'] != 'artist_queue_account_transfer_response' ||
        decoded['version'] != 1) {
      throw const FormatException('这不是有效的新设备回应码。');
    }

    final folderId = decoded['folderId'];
    final sourceDeviceId = decoded['sourceDeviceId'];
    final receiverDeviceId = decoded['receiverDeviceId'];
    final receiverName = decoded['receiverName'];
    final proof = decoded['proof'];
    final receiverAppDeviceId = decoded['receiverAppDeviceId'];
    final receiverPlatform = decoded['receiverPlatform'];
    final bindingProof = decoded['bindingProof'];

    if (folderId is! String || !_validBootstrapFolderId(folderId)) {
      throw const FormatException('回应码的临时会话无效。');
    }
    if (sourceDeviceId is! String || sourceDeviceId.trim().length < 20) {
      throw const FormatException('回应码缺少原设备身份。');
    }
    if (receiverDeviceId is! String || receiverDeviceId.trim().length < 20) {
      throw const FormatException('回应码缺少新设备身份。');
    }
    if (receiverName is! String || receiverName.trim().isEmpty) {
      throw const FormatException('回应码缺少新设备名称。');
    }
    if (proof is! String || proof.trim().isEmpty) {
      throw const FormatException('回应码缺少会话校验信息。');
    }

    final hasBindingFields =
        receiverAppDeviceId != null ||
        receiverPlatform != null ||
        bindingProof != null;
    if (hasBindingFields &&
        (receiverAppDeviceId is! String ||
            receiverAppDeviceId.trim().length < 16 ||
            receiverPlatform is! String ||
            receiverPlatform.trim().isEmpty ||
            bindingProof is! String ||
            bindingProof.trim().isEmpty)) {
      throw const FormatException('回应码的新设备绑定信息不完整。');
    }

    return AccountTransferResponseCode(
      folderId: folderId,
      sourceDeviceId: sourceDeviceId.trim(),
      receiverDeviceId: receiverDeviceId.trim(),
      receiverName: receiverName.trim(),
      proof: proof.trim(),
      receiverAppDeviceId: receiverAppDeviceId is String
          ? receiverAppDeviceId.trim()
          : null,
      receiverPlatform:
          receiverPlatform is String ? receiverPlatform.trim() : null,
      bindingProof: bindingProof is String ? bindingProof.trim() : null,
    );
  }

  Future<bool> verifies(AccountTransferDescriptor descriptor) async {
    if (folderId != descriptor.folderId ||
        sourceDeviceId != descriptor.sourceDeviceId) {
      return false;
    }
    final keyBytes = decodeAccountTransferKey(descriptor.encryptionKey);
    if (keyBytes == null) return false;

    final expected = await _responseProof(
      keyBytes: keyBytes,
      folderId: folderId,
      sourceDeviceId: sourceDeviceId,
      receiverDeviceId: receiverDeviceId,
      receiverName: receiverName,
    );
    try {
      if (!_secureBytesEqual(_decodeBase64UrlStrict(proof), expected)) {
        return false;
      }

      final appDeviceId = receiverAppDeviceId;
      final platform = receiverPlatform;
      final extraProof = bindingProof;
      if (appDeviceId == null && platform == null && extraProof == null) {
        return true;
      }
      if (appDeviceId == null || platform == null || extraProof == null) {
        return false;
      }

      final expectedBinding = await _responseBindingProof(
        keyBytes: keyBytes,
        folderId: folderId,
        sourceDeviceId: sourceDeviceId,
        receiverDeviceId: receiverDeviceId,
        receiverName: receiverName,
        receiverAppDeviceId: appDeviceId,
        receiverPlatform: platform,
      );
      return _secureBytesEqual(
        _decodeBase64UrlStrict(extraProof),
        expectedBinding,
      );
    } catch (_) {
      return false;
    }
  }
}

class AddDeviceCode {
  const AddDeviceCode({
    required this.accountTransferPayload,
    this.syncPairingPayload,
  });

  final String accountTransferPayload;
  final String? syncPairingPayload;

  String encode() {
    return jsonEncode(<String, dynamic>{
      'kind': 'artist_queue_add_device',
      'version': 1,
      'accountTransfer': accountTransferPayload,
      if (syncPairingPayload?.trim().isNotEmpty == true)
        'syncPairing': syncPairingPayload,
    });
  }

  factory AddDeviceCode.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['kind'] != 'artist_queue_add_device' ||
        decoded['version'] != 1) {
      throw const FormatException('这不是有效的添加设备二维码。');
    }

    final transfer = decoded['accountTransfer'];
    if (transfer is! String || transfer.trim().isEmpty) {
      throw const FormatException('添加设备二维码缺少账号传输信息。');
    }

    final pairing = decoded['syncPairing'];
    return AddDeviceCode(
      accountTransferPayload: transfer,
      syncPairingPayload: pairing is String && pairing.trim().isNotEmpty
          ? pairing
          : null,
    );
  }

  static String accountTransferFrom(String source) {
    return AddDeviceCode.decode(source).accountTransferPayload;
  }

  static String syncPairingFrom(String source) {
    final pairing = AddDeviceCode.decode(source).syncPairingPayload;
    if (pairing == null || pairing.trim().isEmpty) {
      throw const FormatException('这个添加设备二维码里没有同步配对信息。');
    }
    return pairing;
  }
}

class AccountTransferRelayFrame {
  const AccountTransferRelayFrame({
    required this.type,
    required this.folderId,
    required this.receiverDeviceId,
    required this.body,
  });

  final String type;
  final String folderId;
  final String receiverDeviceId;
  final String body;

  String encode() => jsonEncode(<String, dynamic>{
        'kind': 'artist_queue_account_transfer_relay',
        'version': 1,
        'type': type,
        'folderId': folderId,
        'receiverDeviceId': receiverDeviceId,
        'body': body,
      });

  factory AccountTransferRelayFrame.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['kind'] != 'artist_queue_account_transfer_relay' ||
        decoded['version'] != 1) {
      throw const FormatException('设备加入中继消息格式无效。');
    }
    final type = decoded['type'];
    final folderId = decoded['folderId'];
    final receiverDeviceId = decoded['receiverDeviceId'];
    final body = decoded['body'];
    if (type is! String ||
        !<String>{'payload', 'done', 'ack'}.contains(type) ||
        folderId is! String ||
        !_validBootstrapFolderId(folderId) ||
        receiverDeviceId is! String ||
        receiverDeviceId.trim().length < 20 ||
        body is! String ||
        body.isEmpty) {
      throw const FormatException('设备加入中继消息内容无效。');
    }
    return AccountTransferRelayFrame(
      type: type,
      folderId: folderId,
      receiverDeviceId: receiverDeviceId.trim(),
      body: body,
    );
  }
}

class AccountTransferRelaySession {
  AccountTransferRelaySession._({
    required this.descriptor,
    required this.localDeviceId,
    required this.roomHash,
    required this.ownTopic,
    required PublicRelayClient relay,
    required StreamSubscription<PublicRelayMessage> subscription,
  })  : _relay = relay,
        _subscription = subscription;

  final AccountTransferDescriptor descriptor;
  final String localDeviceId;
  final String roomHash;
  final String ownTopic;
  final PublicRelayClient _relay;
  final StreamSubscription<PublicRelayMessage> _subscription;

  bool get connected => _relay.connected;

  static Future<AccountTransferRelaySession> connect({
    required AccountTransferDescriptor descriptor,
    required String localDeviceId,
    required Future<void> Function(AccountTransferRelayFrame frame) onFrame,
  }) async {
    final normalizedLocalId = localDeviceId.trim();
    if (normalizedLocalId.length < 20) {
      throw const FormatException('设备加入中继缺少有效的本机同步身份。');
    }
    final roomHash = await _accountTransferRelayRoomHash(descriptor);
    final ownTopic = _accountTransferRelayTopic(roomHash, normalizedLocalId);
    final relay = PublicRelayClient(
      clientId: 'ag-join-${randomAccountTransferToken().substring(0, 12)}',
    );
    late final StreamSubscription<PublicRelayMessage> subscription;
    subscription = relay.messages.listen((message) {
      if (message.topic != ownTopic) return;
      try {
        final frame = AccountTransferRelayFrame.decode(message.payload);
        if (frame.folderId != descriptor.folderId) return;
        unawaited(onFrame(frame));
      } catch (_) {
        // Relay frames are authenticated again by the bootstrap AES-GCM key.
      }
    });
    try {
      await relay.connect(<String>[ownTopic]);
      return AccountTransferRelaySession._(
        descriptor: descriptor,
        localDeviceId: normalizedLocalId,
        roomHash: roomHash,
        ownTopic: ownTopic,
        relay: relay,
        subscription: subscription,
      );
    } catch (_) {
      await subscription.cancel();
      await relay.dispose();
      rethrow;
    }
  }

  void publish({
    required String targetDeviceId,
    required AccountTransferRelayFrame frame,
  }) {
    final target = targetDeviceId.trim();
    if (target.length < 20) {
      throw const FormatException('设备加入中继缺少有效的目标设备身份。');
    }
    _relay.publish(
      _accountTransferRelayTopic(roomHash, target),
      frame.encode(),
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _relay.dispose();
  }
}

Future<String> _accountTransferRelayRoomHash(
  AccountTransferDescriptor descriptor,
) async {
  final keyBytes = decodeAccountTransferKey(descriptor.encryptionKey);
  if (keyBytes == null) {
    throw const FormatException('设备加入二维码的加密密钥无效。');
  }
  final seed = <int>[
    ...utf8.encode('guild-account-bootstrap-relay-v1\u0000'),
    ...utf8.encode(descriptor.folderId),
    0,
    ...keyBytes,
  ];
  final digest = await Sha256().hash(seed);
  return digest.bytes
      .take(16)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _accountTransferRelayTopic(String roomHash, String deviceId) {
  final inbox = base64Url.encode(utf8.encode(deviceId)).replaceAll('=', '');
  return 'adventurers-guild-peer/v1/$roomHash/inbox/$inbox';
}

String accountTransferRelayControlMessage({
  required String type,
  required String folderId,
  required String receiverDeviceId,
}) {
  return 'account-transfer-relay-$type-v1\n$folderId\n$receiverDeviceId';
}

bool _validBootstrapFolderId(String value) {
  return RegExp(
    r'^artist-workbench-bootstrap-[A-Za-z0-9_-]{20,}$',
  ).hasMatch(value);
}

String randomAccountTransferToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Future<List<int>> _responseProof({
  required List<int> keyBytes,
  required String folderId,
  required String sourceDeviceId,
  required String receiverDeviceId,
  required String receiverName,
}) async {
  final message = utf8.encode(
    '$folderId\n$sourceDeviceId\n$receiverDeviceId\n$receiverName',
  );
  final mac = await Hmac.sha256().calculateMac(
    message,
    secretKey: SecretKey(keyBytes),
  );
  return mac.bytes;
}

Future<List<int>> _responseBindingProof({
  required List<int> keyBytes,
  required String folderId,
  required String sourceDeviceId,
  required String receiverDeviceId,
  required String receiverName,
  required String receiverAppDeviceId,
  required String receiverPlatform,
}) async {
  final message = utf8.encode(
    'app-device-binding-v1\n'
    '$folderId\n'
    '$sourceDeviceId\n'
    '$receiverDeviceId\n'
    '$receiverName\n'
    '$receiverAppDeviceId\n'
    '$receiverPlatform',
  );
  final mac = await Hmac.sha256().calculateMac(
    message,
    secretKey: SecretKey(keyBytes),
  );
  return mac.bytes;
}

Future<String> encryptAccountTransferPayload(
  String payload,
  List<int> keyBytes,
) async {
  final algorithm = AesGcm.with256bits();
  final secretBox = await algorithm.encrypt(
    utf8.encode(payload),
    secretKey: SecretKey(keyBytes),
  );
  return jsonEncode(<String, dynamic>{
    'kind': 'artist_queue_account_transfer_payload',
    'version': 1,
    'nonce': encodeAccountTransferBase64Url(secretBox.nonce),
    'cipherText': encodeAccountTransferBase64Url(secretBox.cipherText),
    'mac': encodeAccountTransferBase64Url(secretBox.mac.bytes),
  });
}

Future<String> decryptAccountTransferPayload(String source, String encodedKey) async {
  final keyBytes = decodeAccountTransferKey(encodedKey);
  if (keyBytes == null) {
    throw const FormatException('设备加入二维码的加密密钥无效。');
  }

  final decoded = jsonDecode(source);
  if (decoded is! Map ||
      decoded['kind'] != 'artist_queue_account_transfer_payload' ||
      decoded['version'] != 1) {
    throw const FormatException('设备传输的加密数据格式无效。');
  }

  try {
    final nonce = _decodeBase64UrlStrict(decoded['nonce']);
    final cipherText = _decodeBase64UrlStrict(decoded['cipherText']);
    final mac = _decodeBase64UrlStrict(decoded['mac']);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final clear = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clear);
  } catch (_) {
    throw const FormatException('设备加入数据解密失败，二维码可能已失效。');
  }
}

List<int>? decodeAccountTransferKey(String source) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(source));
    return bytes.length == 32 ? bytes : null;
  } catch (_) {
    return null;
  }
}

List<int> _decodeBase64UrlStrict(Object? source) {
  if (source is! String || source.isEmpty) {
    throw const FormatException('加密数据字段无效。');
  }
  return base64Url.decode(base64Url.normalize(source));
}

bool _secureBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

String encodeAccountTransferBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

List<int> randomAccountTransferBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

