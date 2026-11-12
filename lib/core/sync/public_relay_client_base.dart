import 'dart:async';

import 'public_relay_protocol.dart';

abstract class PublicRelayClientBase {
  PublicRelayClientBase({required this.clientId});

  final String clientId;
  String? connectedTopic;

  final StreamController<PublicRelayMessage> _messages =
      StreamController<PublicRelayMessage>.broadcast();

  Stream<PublicRelayMessage> get messages => _messages.stream;
  bool get connected;

  String requireSingleTopic(Iterable<String> topics) {
    final topicList = topics.toList(growable: false);
    if (topicList.length != 1) {
      throw StateError('在线同步连接参数异常');
    }
    return topicList.single;
  }

  void emitIncoming(Object? event) {
    if (_messages.isClosed || event is! String) return;
    final message = decodePublicRelayMessage(event);
    if (message != null) _messages.add(message);
  }

  void requireConnected(bool ready) {
    if (!ready) throw StateError('在线同步尚未连接');
  }

  Future<void> connect(Iterable<String> topics);
  void publish(String topic, String payload);
  Future<void> disconnect();

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
