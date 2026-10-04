import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../sync/embedded_syncthing_bridge.dart';
import 'device_descriptor.dart';

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
    if (_decodeTransferKey(encryptionKey) == null) {
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
    if (rawKey is! String || _decodeTransferKey(rawKey) == null) {
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
  });

  final String folderId;
  final String sourceDeviceId;
  final String receiverDeviceId;
  final String receiverName;
  final String proof;

  static Future<AccountTransferResponseCode> create({
    required AccountTransferDescriptor descriptor,
    required String receiverDeviceId,
    required String receiverName,
  }) async {
    final normalizedReceiverId = receiverDeviceId.trim();
    if (normalizedReceiverId.length < 20) {
      throw const FormatException('无法读取新设备的同步身份。');
    }
    final keyBytes = _decodeTransferKey(descriptor.encryptionKey);
    if (keyBytes == null) {
      throw const FormatException('设备加入二维码的加密密钥无效。');
    }

    final name = receiverName.trim();
    if (name.isEmpty) {
      throw const FormatException('无法读取新设备名称。');
    }
    final proofBytes = await _responseProof(
      keyBytes: keyBytes,
      folderId: descriptor.folderId,
      sourceDeviceId: descriptor.sourceDeviceId,
      receiverDeviceId: normalizedReceiverId,
      receiverName: name,
    );

    return AccountTransferResponseCode(
      folderId: descriptor.folderId,
      sourceDeviceId: descriptor.sourceDeviceId,
      receiverDeviceId: normalizedReceiverId,
      receiverName: name,
      proof: _encodeBase64Url(proofBytes),
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

    return AccountTransferResponseCode(
      folderId: folderId,
      sourceDeviceId: sourceDeviceId.trim(),
      receiverDeviceId: receiverDeviceId.trim(),
      receiverName: receiverName.trim(),
      proof: proof.trim(),
    );
  }

  Future<bool> verifies(AccountTransferDescriptor descriptor) async {
    if (folderId != descriptor.folderId ||
        sourceDeviceId != descriptor.sourceDeviceId) {
      return false;
    }
    final keyBytes = _decodeTransferKey(descriptor.encryptionKey);
    if (keyBytes == null) return false;

    final expected = await _responseProof(
      keyBytes: keyBytes,
      folderId: folderId,
      sourceDeviceId: sourceDeviceId,
      receiverDeviceId: receiverDeviceId,
      receiverName: receiverName,
    );
    try {
      return _secureBytesEqual(_decodeBase64UrlStrict(proof), expected);
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

class SyncthingAccountTransferServer {
  SyncthingAccountTransferServer._({
    required this.descriptor,
    required EmbeddedSyncthingBridge bridge,
    required Directory folder,
    required File payloadFile,
    required File doneFile,
    void Function()? onTransferred,
  }) : _bridge = bridge,
       _folder = folder,
       _payloadFile = payloadFile,
       _doneFile = doneFile,
       _onTransferred = onTransferred;

  final EmbeddedSyncthingBridge _bridge;
  final Directory _folder;
  final File _payloadFile;
  final File _doneFile;
  final void Function()? _onTransferred;

  final AccountTransferDescriptor descriptor;

  bool _closed = false;
  bool _transferred = false;
  String? _acceptedReceiverDeviceId;

  bool get transferred => _transferred;

  static Future<SyncthingAccountTransferServer> start({
    required String payload,
    void Function()? onTransferred,
  }) async {
    const bridge = EmbeddedSyncthingBridge();
    if (!bridge.supported) {
      throw StateError('当前平台不支持无局域网设备加入。');
    }

    final token = _randomToken();
    final folderId = 'artist-workbench-bootstrap-$token';
    final support = await getApplicationSupportDirectory();
    final folder = Directory(
      '${support.path}${Platform.pathSeparator}account-bootstrap'
      '${Platform.pathSeparator}$folderId',
    );
    await folder.create(recursive: true);

    try {
      final keyBytes = _randomBytes(32);
      final payloadFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.json',
      );
      final doneFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.done',
      );
      await payloadFile.writeAsString(
        await _encryptTransferPayload(payload, keyBytes),
        flush: true,
      );
      await bridge.prepareFolder(
        folderId: folderId,
        label: '临时账号加入',
        folderPath: folder.path,
        force: true,
      );
      final status = await bridge.statusFolder(folderId);
      final sourceDeviceId = status.deviceId?.trim();
      if (sourceDeviceId == null || sourceDeviceId.length < 20) {
        throw StateError('无法读取本机同步设备身份。');
      }

      return SyncthingAccountTransferServer._(
        descriptor: AccountTransferDescriptor(
          encryptionKey: _encodeBase64Url(keyBytes),
          sourceDeviceId: sourceDeviceId,
          folderId: folderId,
        ),
        bridge: bridge,
        folder: folder,
        payloadFile: payloadFile,
        doneFile: doneFile,
        onTransferred: onTransferred,
      );
    } catch (_) {
      await _cleanupBootstrapFolder(bridge, folderId, folder);
      rethrow;
    }
  }

  Future<void> acceptResponse(AccountTransferResponseCode response) async {
    if (_closed) {
      throw const FormatException('这次添加设备会话已经结束，请重新生成二维码。');
    }
    if (!await response.verifies(descriptor)) {
      throw const FormatException('回应码不属于当前添加设备会话，请重新扫描。');
    }

    final existing = _acceptedReceiverDeviceId;
    if (existing != null && existing != response.receiverDeviceId) {
      throw const FormatException('当前二维码已经确认了另一台新设备，请重新生成二维码。');
    }

    await _bridge.pairFolder(
      folderId: descriptor.folderId,
      deviceId: response.receiverDeviceId,
      name: response.receiverName,
    );
    _acceptedReceiverDeviceId = response.receiverDeviceId;
  }

  Future<void> poll() async {
    if (_closed || _transferred) return;

    if (await _doneFile.exists()) {
      _transferred = true;
      _onTransferred?.call();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _bridge.removeFolderById(descriptor.folderId);
    } finally {
      try {
        if (await _payloadFile.exists()) await _payloadFile.delete();
        if (await _doneFile.exists()) await _doneFile.delete();
        if (await _folder.exists()) await _folder.delete(recursive: true);
      } catch (_) {}
    }
  }
}

class SyncthingAccountTransferClient {
  const SyncthingAccountTransferClient();

  Future<SyncthingAccountTransferClientSession> start(
    AccountTransferDescriptor descriptor,
  ) async {
    const bridge = EmbeddedSyncthingBridge();
    if (!bridge.supported) {
      throw const FormatException('当前平台不支持无局域网设备加入。');
    }

    final support = await getApplicationSupportDirectory();
    final folder = Directory(
      '${support.path}${Platform.pathSeparator}account-bootstrap'
      '${Platform.pathSeparator}${descriptor.folderId}',
    );
    await folder.create(recursive: true);
    try {
      final payloadFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.json',
      );
      final doneFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.done',
      );

      await bridge.prepareFolder(
        folderId: descriptor.folderId,
        label: '临时账号加入',
        folderPath: folder.path,
        force: true,
      );
      final status = await bridge.statusFolder(descriptor.folderId);
      final receiverDeviceId = status.deviceId?.trim();
      if (receiverDeviceId == null || receiverDeviceId.length < 20) {
        throw const FormatException('无法读取新设备的同步身份。');
      }

      final device = await DeviceDescriptor.current();
      final response = await AccountTransferResponseCode.create(
        descriptor: descriptor,
        receiverDeviceId: receiverDeviceId,
        receiverName: device.name,
      );

      await bridge.pairFolder(
        folderId: descriptor.folderId,
        deviceId: descriptor.sourceDeviceId,
        name: '原设备',
      );

      return SyncthingAccountTransferClientSession._(
        descriptor: descriptor,
        response: response,
        bridge: bridge,
        folder: folder,
        payloadFile: payloadFile,
        doneFile: doneFile,
      );
    } catch (_) {
      await _cleanupBootstrapFolder(bridge, descriptor.folderId, folder);
      rethrow;
    }
  }
}

Future<void> _cleanupBootstrapFolder(
  EmbeddedSyncthingBridge bridge,
  String folderId,
  Directory folder,
) async {
  try {
    await bridge.removeFolderById(folderId);
  } catch (_) {}
  try {
    if (await folder.exists()) await folder.delete(recursive: true);
  } catch (_) {}
}

class SyncthingAccountTransferClientSession {
  SyncthingAccountTransferClientSession._({
    required this.descriptor,
    required this.response,
    required EmbeddedSyncthingBridge bridge,
    required Directory folder,
    required File payloadFile,
    required File doneFile,
  }) : _bridge = bridge,
       _folder = folder,
       _payloadFile = payloadFile,
       _doneFile = doneFile;

  final AccountTransferDescriptor descriptor;
  final AccountTransferResponseCode response;
  final EmbeddedSyncthingBridge _bridge;
  final Directory _folder;
  final File _payloadFile;
  final File _doneFile;

  bool _closed = false;

  Future<String> receive({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (!_closed && DateTime.now().isBefore(deadline)) {
      await _bridge.requestScanFolder(descriptor.folderId);
      if (await _payloadFile.exists()) {
        final encrypted = await _payloadFile.readAsString();
        final clear = await _decryptTransferPayload(
          encrypted,
          descriptor.encryptionKey,
        );
        await _doneFile.writeAsString('done', flush: true);
        await _bridge.requestScanFolder(descriptor.folderId);
        return clear;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (_closed) {
      throw const FormatException('设备加入已取消。');
    }
    throw const FormatException(
      '等待原设备确认超时。请确认原设备仍停留在“添加设备”页面，'
      '并已经扫描或粘贴了这台设备的回应码。',
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _bridge.removeFolderById(descriptor.folderId);
    } finally {
      try {
        if (await _folder.exists()) await _folder.delete(recursive: true);
      } catch (_) {}
    }
  }
}

bool _validBootstrapFolderId(String value) {
  return RegExp(
    r'^artist-workbench-bootstrap-[A-Za-z0-9_-]{20,}$',
  ).hasMatch(value);
}

String _randomToken() {
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

Future<String> _encryptTransferPayload(
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
    'nonce': _encodeBase64Url(secretBox.nonce),
    'cipherText': _encodeBase64Url(secretBox.cipherText),
    'mac': _encodeBase64Url(secretBox.mac.bytes),
  });
}

Future<String> _decryptTransferPayload(String source, String encodedKey) async {
  final keyBytes = _decodeTransferKey(encodedKey);
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

List<int>? _decodeTransferKey(String source) {
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

String _encodeBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
