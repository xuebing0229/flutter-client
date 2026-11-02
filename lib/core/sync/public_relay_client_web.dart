// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'public_relay_protocol.dart';
import 'public_relay_client_base.dart';

/// Browser side of the Cloudflare WebSocket relay.
///
/// When PUBLIC_SYNC_RELAY_URL is omitted, PWA builds use /sync on the current
/// origin so the PWA assets and the relay can live in one Cloudflare Worker.
class PublicRelayClient extends PublicRelayClientBase {
  PublicRelayClient({required super.clientId});

  static const String _configuredRelayUrl = String.fromEnvironment(
    'PUBLIC_SYNC_RELAY_URL',
  );

  html.WebSocket? _socket;
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  StreamSubscription<html.Event>? _closeSubscription;
  StreamSubscription<html.Event>? _errorSubscription;
  bool get connected => _socket?.readyState == html.WebSocket.OPEN;

  Future<void> connect(Iterable<String> topics) async {
    final topic = requireSingleTopic(topics);
    if (connected && connectedTopic == topic) return;

    await disconnect();
    final endpoint = buildPublicRelayUri(
      configured: _configuredRelayUrl,
      topic: topic,
      clientId: clientId,
      fallbackOrigin: Uri.parse(html.window.location.href).origin,
    );

    final socket = html.WebSocket(endpoint.toString());
    final ready = Completer<void>();

    _socket = socket;
    connectedTopic = topic;
    _messageSubscription = socket.onMessage.listen((event) {
      final data = event.data;
      emitIncoming(data);
    });
    _closeSubscription = socket.onClose.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('在线同步连接已关闭'));
      }
      if (identical(_socket, socket)) {
        _socket = null;
        connectedTopic = null;
      }
    });
    _errorSubscription = socket.onError.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('在线同步连接失败'));
      }
    });
    final openSubscription = socket.onOpen.listen((_) {
      if (!ready.isCompleted) ready.complete();
    });

    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } finally {
      await openSubscription.cancel();
    }
  }

  void publish(String topic, String payload) {
    final socket = _socket;
    requireConnected(
      socket != null && socket.readyState == html.WebSocket.OPEN,
    );
    socket!.sendString(encodePublicRelayPublish(topic, payload));
  }

  Future<void> disconnect() async {
    await _messageSubscription?.cancel();
    await _closeSubscription?.cancel();
    await _errorSubscription?.cancel();
    _messageSubscription = null;
    _closeSubscription = null;
    _errorSubscription = null;

    final socket = _socket;
    _socket = null;
    connectedTopic = null;
    try {
      socket?.close(1000, 'disconnect');
    } catch (_) {}
  }

}

