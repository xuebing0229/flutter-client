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
    final keyBytes = _decodeTransferKey(descriptor.encryptionKey);
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
      proof: _encodeBase64Url(proofBytes),
      receiverAppDeviceId: appDeviceId,
      receiverPlatform: platform,
      bindingProof: _encodeBase64Url(bindingProofBytes),
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

class _AccountTransferDiagnostics {
  _AccountTransferDiagnostics({required this.role});

  final String role;
  final List<String> _lines = <String>[];
  String? _lastStatusFingerprint;

  void event(String name, [Map<String, Object?> details = const <String, Object?>{}]) {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final payload = details.isEmpty ? '' : ' ' + jsonEncode(details);
    _lines.add('$stamp $name$payload');
    if (_lines.length > 500) {
      _lines.removeRange(0, _lines.length - 500);
    }
  }

  void status(
    String name,
    EmbeddedSyncthingStatus status, {
    required String folderId,
    bool force = false,
  }) {
    final data = <String, Object?>{
      'folderId': folderId,
      'platform': Platform.operatingSystem,
      'available': status.available,
      'running': status.running,
      'localDeviceId': status.deviceId,
      'version': status.version,
      'folderConfiguredDevices': status.configuredDevices,
      'folderConnectedDeviceIds': status.connectedDeviceIds,
      'allConfiguredDevices': status.allConfiguredDevices,
      'allConnectedDeviceIds': status.allConnectedDeviceIds,
      'folderState': status.folderState,
      'remoteFolderStates': status.remoteFolderStates,
      'folderErrors': status.folderErrors,
      'syncProgress': status.syncProgress,
      'error': status.error,
    };
    final fingerprint = jsonEncode(data);
    if (!force && fingerprint == _lastStatusFingerprint) return;
    _lastStatusFingerprint = fingerprint;
    event(name, data);
  }

  String report() {
    return <String>[
      '冒险者公会设备加入诊断',
      'role=$role',
      'generatedAt=${DateTime.now().toUtc().toIso8601String()}',
      ..._lines,
    ].join('\n');
  }
}

class SyncthingAccountTransferServer {
  SyncthingAccountTransferServer._({
    required this.descriptor,
    required EmbeddedSyncthingBridge bridge,
    required Directory folder,
    required File payloadFile,
    required File doneFile,
    required File ackFile,
    required _AccountTransferDiagnostics diagnostics,
    void Function()? onTransferred,
  }) : _bridge = bridge,
       _folder = folder,
       _payloadFile = payloadFile,
       _doneFile = doneFile,
       _ackFile = ackFile,
       _diagnostics = diagnostics,
       _onTransferred = onTransferred;

  final EmbeddedSyncthingBridge _bridge;
  final Directory _folder;
  final File _payloadFile;
  final File _doneFile;
  final File _ackFile;
  final _AccountTransferDiagnostics _diagnostics;
  final void Function()? _onTransferred;

  final AccountTransferDescriptor descriptor;

  bool _closed = false;
  bool _receiverFinished = false;
  bool _transferred = false;
  String? _acceptedReceiverDeviceId;
  String? _acceptedReceiverName;
  String? _acceptedReceiverAppDeviceId;
  String? _acceptedReceiverPlatform;

  bool get receiverFinished => _receiverFinished;
  bool get transferred => _transferred;
  String? get acceptedReceiverDeviceId => _acceptedReceiverDeviceId;
  String? get acceptedReceiverName => _acceptedReceiverName;
  String? get acceptedReceiverAppDeviceId => _acceptedReceiverAppDeviceId;
  String? get acceptedReceiverPlatform => _acceptedReceiverPlatform;
  String get diagnosticReport => _diagnostics.report();

  Future<String> captureDiagnosticReport() async {
    try {
      final status = await _bridge.statusFolder(descriptor.folderId);
      _diagnostics.status(
        'server.manualSnapshot',
        status,
        folderId: descriptor.folderId,
        force: true,
      );
    } catch (error) {
      _diagnostics.event('server.manualSnapshot.error', <String, Object?>{
        'error': '$error',
      });
    }
    return _diagnostics.report();
  }

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
    final diagnostics = _AccountTransferDiagnostics(role: 'source');
    diagnostics.event('server.start', <String, Object?>{
      'folderId': folderId,
      'platform': Platform.operatingSystem,
    });
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
      final ackFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.ack',
      );

      // Configure the bootstrap folder before creating the payload. If the
      // payload already exists before Syncthing starts watching this folder,
      // some Android runs can keep an empty index until a later rescan. The
      // receiver then connects successfully but waits forever for transfer.json.
      await bridge.prepareFolder(
        folderId: folderId,
        label: '临时账号加入',
        folderPath: folder.path,
        force: true,
      );
      diagnostics.event('server.prepareFolder.ok');
      await payloadFile.writeAsString(
        await _encryptTransferPayload(payload, keyBytes),
        flush: true,
      );
      await bridge.requestScanFolder(folderId);
      diagnostics.event('server.initialScan.ok');

      final status = await bridge.statusFolder(folderId);
      diagnostics.status(
        'server.initialStatus',
        status,
        folderId: folderId,
        force: true,
      );
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
        ackFile: ackFile,
        diagnostics: diagnostics,
        onTransferred: onTransferred,
      );
    } catch (_) {
      await _cleanupBootstrapFolder(bridge, folderId, folder);
      rethrow;
    }
  }

  Future<void> acceptResponse(AccountTransferResponseCode response) async {
    _diagnostics.event('server.acceptResponse.begin', <String, Object?>{
      'folderId': response.folderId,
      'sourceDeviceId': response.sourceDeviceId,
      'receiverDeviceId': response.receiverDeviceId,
      'receiverName': response.receiverName,
      'receiverAppDeviceId': response.receiverAppDeviceId,
      'receiverPlatform': response.receiverPlatform,
    });
    if (_closed) {
      throw const FormatException('这次添加设备会话已经结束，请重新生成二维码。');
    }
    if (!await response.verifies(descriptor)) {
      _diagnostics.event('server.acceptResponse.verify.failed');
      throw const FormatException('回应码不属于当前添加设备会话，请重新扫描。');
    }
    _diagnostics.event('server.acceptResponse.verify.ok');

    final existing = _acceptedReceiverDeviceId;
    if (existing != null && existing != response.receiverDeviceId) {
      throw const FormatException('当前二维码已经确认了另一台新设备，请重新生成二维码。');
    }

    _acceptedReceiverDeviceId = response.receiverDeviceId;
    _acceptedReceiverName = response.receiverName;
    _acceptedReceiverAppDeviceId = response.receiverAppDeviceId;
    _acceptedReceiverPlatform = response.receiverPlatform;

    // Device-level connectivity is not enough. Wait until Syncthing confirms
    // that the receiver shares THIS bootstrap folder back (remoteState=valid).
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    String? lastRemoteState;
    String? lastFolderError;
    var attempt = 0;
    while (!_closed && DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        await _bridge.pairFolder(
        folderId: descriptor.folderId,
        deviceId: response.receiverDeviceId,
          name: response.receiverName,
        );
        if (attempt == 1) {
          _diagnostics.event('server.pairFolder.ok', <String, Object?>{
            'attempt': attempt,
            'receiverDeviceId': response.receiverDeviceId,
          });
        }
      } catch (error) {
        _diagnostics.event('server.pairFolder.error', <String, Object?>{
          'attempt': attempt,
          'error': '$error',
        });
        rethrow;
      }
      try {
        await _bridge.setFolderPaused(
        folderId: descriptor.folderId,
          paused: false,
        );
        if (attempt == 1) {
          _diagnostics.event('server.unpauseFolder.ok');
        }
      } catch (error) {
        _diagnostics.event('server.unpauseFolder.error', <String, Object?>{
          'attempt': attempt,
          'error': '$error',
        });
        rethrow;
      }
      try {
        await _bridge.requestScanFolder(descriptor.folderId);
        if (attempt == 1) {
          _diagnostics.event('server.scanAfterAccept.ok');
        }
      } catch (error) {
        _diagnostics.event('server.scanAfterAccept.error', <String, Object?>{
          'attempt': attempt,
          'error': '$error',
        });
        rethrow;
      }

      final status = await _bridge.statusFolder(descriptor.folderId);
      _diagnostics.status(
        'server.acceptResponse.status',
        status,
        folderId: descriptor.folderId,
      );
      lastRemoteState =
          status.remoteFolderStates[response.receiverDeviceId]?.trim();
      if (status.folderErrors.isNotEmpty) {
        lastFolderError = status.folderErrors.first;
      }

      final connected = status.connectedDeviceIds.contains(
        response.receiverDeviceId,
      );
      if (connected && lastRemoteState == 'valid') {
        _diagnostics.event('server.acceptResponse.folder.valid', <String, Object?>{
          'attempt': attempt,
          'receiverDeviceId': response.receiverDeviceId,
        });
        await _bridge.requestScanFolder(descriptor.folderId);
        return;
      }

      if (lastRemoteState == 'paused') {
        _diagnostics.event('server.acceptResponse.folder.paused', <String, Object?>{
          'attempt': attempt,
        });
        throw const FormatException(
          '新设备已经连接，但临时账号同步目录在对端处于暂停状态。'
          '请让新设备保持在“确认新设备”页面后重新尝试。',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 750));
    }

    if (_closed) {
      _diagnostics.event('server.acceptResponse.closed');
      throw const FormatException('这次添加设备会话已经结束，请重新生成二维码。');
    }
    _diagnostics.event('server.acceptResponse.timeout', <String, Object?>{
      'attempts': attempt,
      'lastRemoteState': lastRemoteState,
      'lastFolderError': lastFolderError,
    });
    if (lastFolderError != null && lastFolderError.isNotEmpty) {
      throw FormatException('临时账号同步目录建立失败：$lastFolderError');
    }
    if (lastRemoteState == 'notSharing') {
      throw const FormatException(
        '两台设备已经连接，但新设备没有真正共享临时账号目录。'
        '请让新设备保持在“确认新设备”页面并重新生成配对。',
      );
    }
    throw FormatException(
      '临时账号同步目录没有完成握手'
      '${lastRemoteState == null || lastRemoteState.isEmpty ? '' : '（状态：$lastRemoteState）'}。'
      '请让两台设备都保持当前页面后重试。',
    );
  }

  Future<void> poll() async {
    if (_closed || _transferred) return;

    try {
      final status = await _bridge.statusFolder(descriptor.folderId);
      _diagnostics.status(
        'server.poll.status',
        status,
        folderId: descriptor.folderId,
      );
    } catch (error) {
      _diagnostics.event('server.poll.status.error', <String, Object?>{
        'error': '$error',
      });
    }

    if (_acceptedReceiverDeviceId != null) {
      await _bridge.requestScanFolder(descriptor.folderId);
    }

    if (!_receiverFinished && await _doneFile.exists()) {
      _receiverFinished = true;
      _diagnostics.event('server.receiverFinished.detected');
    }
  }

  Future<void> completeTransfer() async {
    if (_closed || _transferred) return;
    if (!_receiverFinished) {
      throw StateError('新设备尚未确认收到账号数据。');
    }
    if (_acceptedReceiverDeviceId == null) {
      throw StateError('新设备身份尚未确认。');
    }

    _diagnostics.event('server.completeTransfer.begin');
    await _ackFile.writeAsString('ack', flush: true);
    _diagnostics.event('server.ackFile.write.ok');
    await _bridge.requestScanFolder(descriptor.folderId);
    _diagnostics.event('server.completeTransfer.scan.ok');
    _transferred = true;
    _diagnostics.event('server.completeTransfer.done');
    _onTransferred?.call();
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
        if (await _ackFile.exists()) await _ackFile.delete();
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
      final ackFile = File(
        '${folder.path}${Platform.pathSeparator}transfer.ack',
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
      final provisionalAppDeviceId = _randomToken();
      final response = await AccountTransferResponseCode.create(
        descriptor: descriptor,
        receiverDeviceId: receiverDeviceId,
        receiverName: device.name,
        receiverAppDeviceId: provisionalAppDeviceId,
        receiverPlatform: device.platform,
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
        ackFile: ackFile,
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

typedef AccountTransferStatus = ({
  bool sourceConnected,
  bool folderReady,
  String? remoteFolderState,
  String? folderState,
  List<String> folderErrors,
  Map<String, dynamic>? progress,
});

class SyncthingAccountTransferClientSession {
  SyncthingAccountTransferClientSession._({
    required this.descriptor,
    required this.response,
    required EmbeddedSyncthingBridge bridge,
    required Directory folder,
    required File payloadFile,
    required File doneFile,
    required File ackFile,
  }) : _bridge = bridge,
       _folder = folder,
       _payloadFile = payloadFile,
       _doneFile = doneFile,
       _ackFile = ackFile;

  final AccountTransferDescriptor descriptor;
  final AccountTransferResponseCode response;
  final EmbeddedSyncthingBridge _bridge;
  final Directory _folder;
  final File _payloadFile;
  final File _doneFile;
  final File _ackFile;

  bool _closed = false;

  Future<AccountTransferStatus> transferStatus() async {
    final status = await _bridge.statusFolder(descriptor.folderId);
    final sourceConnected = status.connectedDeviceIds.contains(
      descriptor.sourceDeviceId,
    );
    final remoteFolderState =
        status.remoteFolderStates[descriptor.sourceDeviceId]?.trim();
    return (
      sourceConnected: sourceConnected,
      folderReady: sourceConnected && remoteFolderState == 'valid',
      remoteFolderState: remoteFolderState,
      folderState: status.folderState,
      folderErrors: status.folderErrors,
      progress: status.syncProgress,
    );
  }

  Future<Map<String, dynamic>?> transferProgress() async {
    return (await transferStatus()).progress;
  }

  Future<String> receive({
    Duration timeout = const Duration(minutes: 5),
    void Function(AccountTransferStatus status)? onStatus,
  }) async {
    final connectionDeadline = DateTime.now().add(timeout);
    DateTime? folderHandshakeDeadline;
    DateTime? payloadDeadline;
    var sourceConnected = false;
    var folderReady = false;
    var repairTick = 0;

    while (!_closed) {
      await _bridge.requestScanFolder(descriptor.folderId);

      var status = await transferStatus();
      onStatus?.call(status);

      if (status.sourceConnected && !sourceConnected) {
        sourceConnected = true;
        folderHandshakeDeadline = DateTime.now().add(
          const Duration(seconds: 45),
        );
      }

      if (status.folderReady && !folderReady) {
        folderReady = true;
        payloadDeadline = DateTime.now().add(const Duration(minutes: 3));
      }

      if (sourceConnected && !folderReady && repairTick++ % 4 == 0) {
        await _bridge.pairFolder(
          folderId: descriptor.folderId,
          deviceId: descriptor.sourceDeviceId,
          name: '原设备',
        );
        await _bridge.setFolderPaused(
          folderId: descriptor.folderId,
          paused: false,
        );
        await _bridge.requestScanFolder(descriptor.folderId);
        status = await transferStatus();
        onStatus?.call(status);
        if (status.folderReady) {
          folderReady = true;
          payloadDeadline = DateTime.now().add(const Duration(minutes: 3));
        }
      }

      if (status.folderErrors.isNotEmpty) {
        throw FormatException(
          '临时账号目录同步失败：${status.folderErrors.first}',
        );
      }

      if (await _payloadFile.exists()) {
        final encrypted = await _payloadFile.readAsString();
        final clear = await _decryptTransferPayload(
          encrypted,
          descriptor.encryptionKey,
        );

        await _doneFile.writeAsString('done', flush: true);
        await _bridge.requestScanFolder(descriptor.folderId);

        final ackDeadline = DateTime.now().add(const Duration(minutes: 2));
        while (!_closed && DateTime.now().isBefore(ackDeadline)) {
          await _bridge.requestScanFolder(descriptor.folderId);
          if (await _ackFile.exists()) return clear;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (_closed) {
          throw const FormatException('设备加入已取消。');
        }
        throw const FormatException(
          '账号数据已经收到，但原设备没有完成最终确认。'
          '请让原设备继续停留在“添加设备”页面后重试。',
        );
      }

      if (!sourceConnected &&
          !DateTime.now().isBefore(connectionDeadline)) {
        throw const FormatException(
          '等待原设备确认超时。请确认原设备仍停留在“添加设备”页面，'
          '并已经扫描或粘贴了这台设备的回应码。',
        );
      }

      if (sourceConnected &&
          !folderReady &&
          folderHandshakeDeadline != null &&
          !DateTime.now().isBefore(folderHandshakeDeadline)) {
        final state = status.remoteFolderState;
        if (state == 'paused') {
          throw const FormatException(
            '已经连接原设备，但临时账号同步目录在原设备上处于暂停状态。'
            '请让原设备重新打开“添加设备”后再试。',
          );
        }
        if (state == 'notSharing') {
          throw const FormatException(
            '已经连接原设备，但原设备没有真正共享临时账号目录。'
            '请让原设备保持在“添加设备”页面并重新确认回应码。',
          );
        }
        throw FormatException(
          '已经连接原设备，但临时账号目录没有完成同步握手'
          '${state == null || state.isEmpty ? '' : '（状态：$state）'}。',
        );
      }

      if (folderReady &&
          payloadDeadline != null &&
          !DateTime.now().isBefore(payloadDeadline)) {
        throw const FormatException(
          '临时账号同步目录已经对接成功，但账号数据仍没有传过来。'
          '请让原设备继续停留在“添加设备”页面后重试。',
        );
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    throw const FormatException('设备加入已取消。');
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
