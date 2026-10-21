// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

class PublicRelayMessage {
  const PublicRelayMessage({required this.topic, required this.payload});

  final String topic;
  final String payload;
}

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
      throw StateError('Cloudflare 同步中转要求每个连接只绑定一个设备收件箱');
    }
    final topic = topicList.single;
    if (connected && _connectedTopic == topic) return;

    await disconnect();
    final target = _RelayTarget.parse(topic);
    final endpoint = _relayUri(
      configured: _configuredRelayUrl,
      target: target,
      clientId: clientId,
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
        ready.completeError(StateError('Cloudflare 同步中转连接已关闭'));
      }
      if (identical(_socket, socket)) {
        _socket = null;
        _connectedTopic = null;
      }
    });
    _errorSubscription = socket.onError.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('Cloudflare 同步中转连接失败'));
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
      throw StateError('Cloudflare 同步中转尚未连接');
    }
    socket.sendString(jsonEncode(<String, dynamic>{
      'type': 'publish',
      'topic': topic,
      'payload': payload,
    }));
  }

  void _handleIncoming(String event) {
    if (_messages.isClosed) return;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map) return;
      final topic = decoded['topic'];
      final payload = decoded['payload'];
      if (topic is! String || payload is! String) return;
      _messages.add(PublicRelayMessage(topic: topic, payload: payload));
    } catch (_) {
      // Ignore malformed relay frames. AES-GCM authentication is performed by
      // PublicPeerSyncService before any workspace data is accepted.
    }
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

class _RelayTarget {
  const _RelayTarget({required this.room, required this.inbox});

  final String room;
  final String inbox;

  static final RegExp _topic = RegExp(
    r'^adventurers-guild-peer/v1/([0-9a-f]{32})/inbox/([A-Za-z0-9_-]+)$',
  );

  factory _RelayTarget.parse(String topic) {
    final match = _topic.firstMatch(topic);
    if (match == null) {
      throw const FormatException('同步收件箱地址格式无效');
    }
    return _RelayTarget(room: match.group(1)!, inbox: match.group(2)!);
  }
}

Uri _relayUri({
  required String configured,
  required _RelayTarget target,
  required String clientId,
}) {
  final raw = configured.trim();
  final parsed = raw.isEmpty
      ? Uri.parse(Uri.parse(html.window.location.href).origin)
      : Uri.parse(raw);

  final scheme = switch (parsed.scheme) {
    'https' => 'wss',
    'http' => 'ws',
    'wss' || 'ws' => parsed.scheme,
    _ => throw const FormatException('Cloudflare 同步中转地址必须使用 HTTPS/WSS'),
  };
  final path = raw.isEmpty || parsed.path.isEmpty || parsed.path == '/'
      ? '/sync'
      : parsed.path;

  return parsed.replace(
    scheme: scheme,
    path: path,
    queryParameters: <String, String>{
      ...parsed.queryParameters,
      'room': target.room,
      'inbox': target.inbox,
      'client': clientId,
    },
  );
}
