import 'dart:async';
import 'dart:io';

import 'public_relay_protocol.dart';
import 'public_relay_client_base.dart';

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

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool get connected => _socket?.readyState == WebSocket.open;

  Future<void> connect(Iterable<String> topics) async {
    final topic = requireSingleTopic(topics);
    if (connected && connectedTopic == topic) return;

    await disconnect();
    final endpoint = buildPublicRelayUri(
      configured: _configuredRelayUrl,
      topic: topic,
      clientId: clientId,
    );

    final socket = await WebSocket.connect(endpoint.toString());
    socket.pingInterval = const Duration(seconds: 30);
    _socket = socket;
    connectedTopic = topic;
    _subscription = socket.listen(
      _handleIncoming,
      onDone: () {
        if (identical(_socket, socket)) {
          _socket = null;
          connectedTopic = null;
        }
      },
      onError: (_) {
        if (identical(_socket, socket)) {
          _socket = null;
          connectedTopic = null;
        }
      },
      cancelOnError: false,
    );
  }

  void publish(String topic, String payload) {
    final socket = _socket;
    requireConnected(socket != null && socket.readyState == WebSocket.open);
    socket!.add(encodePublicRelayPublish(topic, payload));
  }

  void _handleIncoming(dynamic event) => emitIncoming(event);

  Future<void> disconnect() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final socket = _socket;
    _socket = null;
    connectedTopic = null;
    try {
      await socket?.close(WebSocketStatus.normalClosure, 'disconnect');
    } catch (_) {}
  }

}

