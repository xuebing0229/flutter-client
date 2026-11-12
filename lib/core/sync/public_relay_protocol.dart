import 'dart:convert';

class PublicRelayMessage {
  const PublicRelayMessage({required this.topic, required this.payload});

  final String topic;
  final String payload;
}

class PublicRelayTarget {
  const PublicRelayTarget({required this.room, required this.inbox});

  final String room;
  final String inbox;

  static final RegExp _topic = RegExp(
    r'^adventurers-guild-peer/v1/([0-9a-f]{32})/inbox/([A-Za-z0-9_-]+)$',
  );

  factory PublicRelayTarget.parse(String topic) {
    final match = _topic.firstMatch(topic);
    if (match == null) {
      throw const FormatException('同步收件箱地址格式无效');
    }
    return PublicRelayTarget(room: match.group(1)!, inbox: match.group(2)!);
  }
}

Uri buildPublicRelayUri({
  required String configured,
  required String topic,
  required String clientId,
  String? fallbackOrigin,
}) {
  final raw = configured.trim();
  if (raw.isEmpty && (fallbackOrigin == null || fallbackOrigin.trim().isEmpty)) {
    throw StateError('在线同步地址尚未配置');
  }
  final parsed = Uri.parse(raw.isEmpty ? fallbackOrigin!.trim() : raw);
  final target = PublicRelayTarget.parse(topic);
  final scheme = switch (parsed.scheme) {
    'https' => 'wss',
    'http' => 'ws',
    'wss' || 'ws' => parsed.scheme,
    _ => throw const FormatException('在线同步地址配置无效'),
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

String encodePublicRelayPublish(String topic, String payload) =>
    jsonEncode(<String, dynamic>{
      'type': 'publish',
      'topic': topic,
      'payload': payload,
    });

PublicRelayMessage? decodePublicRelayMessage(Object? event) {
  if (event is! String) return null;
  try {
    final decoded = jsonDecode(event);
    if (decoded is! Map) return null;
    final topic = decoded['topic'];
    final payload = decoded['payload'];
    if (topic is! String || payload is! String) return null;
    return PublicRelayMessage(topic: topic, payload: payload);
  } catch (_) {
    return null;
  }
}
