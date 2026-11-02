import 'dart:async';
import 'dart:io';

import 'public_relay_protocol.dart';

/// Lightweight Cloudflare WebSocket relay used by native clients.
///
/// The relay only sees an opaque room id, an opaque inbox id and encrypted
/// application frames. It does not persist workspace payloads.
class PublicRelayClient {
  PublicRelayClient({required this.clientId});

  static const String _configuredRelayUrl = String.fromEnvironment(
    'PUBLIC_SYNC_RELAY_URL',
    defaultValue: 'https://guild.apixb.top/sync',
  );

  final String clientId;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  String? _connectedTopic;

  final StreamController<PublicRelayMessage> _messages =
      StreamController<PublicRelayMessage>.broadcast();

  Stream<PublicRelayMessage> get messages => _messages.stream;

  bool get connected => _socket?.readyState == WebSocket.open;

  Future<void> connect(Iterable<String> topics) async {
    final topicList = topics.toList(growable: false);
    if (topicList.length != 1) {
      throw StateError('在线同步连接参数异常');
    }
    final topic = topicList.single;
    if (connected && _connectedTopic == topic) return;

    await disconnect();
    final endpoint = buildPublicRelayUri(
      configured: _configuredRelayUrl,
      topic: topic,
      clientId: clientId,
    );

    final socket = await WebSocket.connect(endpoint.toString());
    socket.pingInterval = const Duration(seconds: 30);
    _socket = socket;
    _connectedTopic = topic;
    _subscription = socket.listen(
      _handleIncoming,
      onDone: () {
        if (identical(_socket, socket)) {
          _socket = null;
          _connectedTopic = null;
        }
      },
      onError: (_) {
        if (identical(_socket, socket)) {
          _socket = null;
          _connectedTopic = null;
        }
      },
      cancelOnError: false,
    );
  }

  void publish(String topic, String payload) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('在线同步尚未连接');
    }
    socket.add(encodePublicRelayPublish(topic, payload));
  }

  void _handleIncoming(dynamic event) {
    if (event is! String || _messages.isClosed) return;
    final message = decodePublicRelayMessage(event);
    if (message != null) _messages.add(message);
  }

  Future<void> disconnect() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final socket = _socket;
    _socket = null;
    _connectedTopic = null;
    try {
      await socket?.close(WebSocketStatus.normalClosure, 'disconnect');
    } catch (_) {}
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}

