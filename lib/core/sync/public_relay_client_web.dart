// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'public_relay_protocol.dart';

/// Browser side of the Cloudflare WebSocket relay.
///
/// When PUBLIC_SYNC_RELAY_URL is omitted, PWA builds use /sync on the current
/// origin so the PWA assets and the relay can live in one Cloudflare Worker.
class PublicRelayClient {
  PublicRelayClient({required this.clientId});

  static const String _configuredRelayUrl = String.fromEnvironment(
    'PUBLIC_SYNC_RELAY_URL',
  );

  final String clientId;
  html.WebSocket? _socket;
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  StreamSubscription<html.Event>? _closeSubscription;
  StreamSubscription<html.Event>? _errorSubscription;
  String? _connectedTopic;

  final StreamController<PublicRelayMessage> _messages =
      StreamController<PublicRelayMessage>.broadcast();

  Stream<PublicRelayMessage> get messages => _messages.stream;

  bool get connected => _socket?.readyState == html.WebSocket.OPEN;

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
      fallbackOrigin: Uri.parse(html.window.location.href).origin,
    );

    final socket = html.WebSocket(endpoint.toString());
    final ready = Completer<void>();

    _socket = socket;
    _connectedTopic = topic;
    _messageSubscription = socket.onMessage.listen((event) {
      final data = event.data;
      if (data is String) _handleIncoming(data);
    });
    _closeSubscription = socket.onClose.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('在线同步连接已关闭'));
      }
      if (identical(_socket, socket)) {
        _socket = null;
        _connectedTopic = null;
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
    if (socket == null || socket.readyState != html.WebSocket.OPEN) {
      throw StateError('在线同步尚未连接');
    }
    socket.sendString(encodePublicRelayPublish(topic, payload));
  }

  void _handleIncoming(String event) {
    if (_messages.isClosed) return;
    final message = decodePublicRelayMessage(event);
    if (message != null) _messages.add(message);
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
    _connectedTopic = null;
    try {
      socket?.close(1000, 'disconnect');
    } catch (_) {}
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}

