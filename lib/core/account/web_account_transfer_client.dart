import 'dart:async';

import 'account_transfer_protocol.dart';

class WebAccountTransferClient {
  const WebAccountTransferClient();

  Future<WebAccountTransferClientSession> start(
    AccountTransferDescriptor descriptor, {
    String receiverName = '网页设备',
  }) async {
    final normalizedName = receiverName.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('网页设备名称无效。');
    }

    final appDeviceId = 'web-${randomAccountTransferToken()}';
    final response = await AccountTransferResponseCode.create(
      descriptor: descriptor,
      receiverDeviceId: appDeviceId,
      receiverName: normalizedName,
      receiverAppDeviceId: appDeviceId,
      receiverPlatform: 'web',
    );

    final session = WebAccountTransferClientSession._(
      descriptor: descriptor,
      response: response,
    );
    await session._connect();
    return session;
  }
}

class WebAccountTransferClientSession {
  WebAccountTransferClientSession._({
    required this.descriptor,
    required this.response,
  });

  final AccountTransferDescriptor descriptor;
  final AccountTransferResponseCode response;

  AccountTransferRelaySession? _relay;
  String? _clearPayload;
  bool _ackReceived = false;
  bool _closed = false;

  bool get connected => _relay?.connected == true;

  Future<void> _connect() async {
    try {
      final relay = await AccountTransferRelaySession.connect(
        descriptor: descriptor,
        localDeviceId: response.receiverDeviceId,
        onFrame: _handleFrame,
      );
      if (_closed) {
        await relay.close();
        throw const FormatException('设备加入已取消。');
      }
      _relay = relay;
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException('网页设备无法连接在线同步通道：$error');
    }
  }

  Future<void> _handleFrame(AccountTransferRelayFrame frame) async {
    if (_closed || frame.receiverDeviceId != response.receiverDeviceId) {
      return;
    }
    if (frame.type == 'payload') {
      _clearPayload = await decryptAccountTransferPayload(
        frame.body,
        descriptor.encryptionKey,
      );
      return;
    }
    if (frame.type == 'ack') {
      final clear = await decryptAccountTransferPayload(
        frame.body,
        descriptor.encryptionKey,
      );
      final expected = accountTransferRelayControlMessage(
        type: 'ack',
        folderId: descriptor.folderId,
        receiverDeviceId: response.receiverDeviceId,
      );
      if (clear == expected) _ackReceived = true;
    }
  }

  Future<String> receive({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      final clear = _clearPayload;
      if (clear != null) return _finishReceive(clear);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_closed) {
      throw const FormatException('设备加入已取消。');
    }
    throw const FormatException(
      '等待原设备确认超时。请确认原设备仍停留在“添加设备”页面并保持联网。',
    );
  }

  Future<String> _finishReceive(String clear) async {
    final relay = _relay;
    if (relay == null || !relay.connected) {
      throw const FormatException('在线同步连接已经断开，请保持两端联网后重试。');
    }
    final keyBytes = decodeAccountTransferKey(descriptor.encryptionKey);
    if (keyBytes == null) {
      throw const FormatException('设备加入二维码的加密密钥无效。');
    }
    final doneBody = await encryptAccountTransferPayload(
      accountTransferRelayControlMessage(
        type: 'done',
        folderId: descriptor.folderId,
        receiverDeviceId: response.receiverDeviceId,
      ),
      keyBytes,
    );

    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      if (_ackReceived) return clear;
      if (DateTime.now().difference(lastPublish) >=
          const Duration(seconds: 1)) {
        relay.publish(
          targetDeviceId: descriptor.sourceDeviceId,
          frame: AccountTransferRelayFrame(
            type: 'done',
            folderId: descriptor.folderId,
            receiverDeviceId: response.receiverDeviceId,
            body: doneBody,
          ),
        );
        lastPublish = DateTime.now();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (_closed) {
      throw const FormatException('设备加入已取消。');
    }
    throw const FormatException(
      '账号信息已经收到，但原设备没有完成最终确认。'
      '请让原设备继续停留在“添加设备”页面后重试。',
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final relay = _relay;
    _relay = null;
    await relay?.close();
  }
}
