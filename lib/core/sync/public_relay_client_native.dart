import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PublicRelayMessage {
  const PublicRelayMessage({required this.topic, required this.payload});

  final String topic;
  final String payload;
}

/// Lightweight Cloudflare WebSocket relay used by native clients.
///
/// The relay only sees an opaque room id, an opaque inbox id and encrypted
/// application frames. It does not persist workspace payloads.
class PublicRelayClient {
  PublicRelayClient({required this.clientId});

  static const String _configuredRelayUrl = String.fromEnvironment(
    'PUBLIC_SYNC_RELAY_URL',
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
      throw StateError('Cloudflare 同步中转尚未连接');
    }
    socket.add(jsonEncode(<String, dynamic>{
      'type': 'publish',
      'topic': topic,
      'payload': payload,
    }));
  }

  void _handleIncoming(dynamic event) {
    if (event is! String || _messages.isClosed) return;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map) return;
      final topic = decoded['topic'];
      final payload = decoded['payload'];
      if (topic is! String || payload is! String) return;
      _messages.add(PublicRelayMessage(topic: topic, payload: payload));
    } catch (_) {
      // Ignore malformed relay frames. Application payloads are authenticated
      // again by AES-GCM in PublicPeerSyncService.
    }
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
  if (raw.isEmpty) {
    throw StateError(
      '尚未配置 Cloudflare 同步中转地址（PUBLIC_SYNC_RELAY_URL）',
    );
  }

  final parsed = Uri.parse(raw);
  final scheme = switch (parsed.scheme) {
    'https' => 'wss',
    'http' => 'ws',
    'wss' || 'ws' => parsed.scheme,
    _ => throw const FormatException('Cloudflare 同步中转地址必须使用 HTTPS/WSS'),
  };
  final path = parsed.path.isEmpty || parsed.path == '/'
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
