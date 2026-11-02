import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main() async {
  final configured = Platform.environment['PUBLIC_SYNC_RELAY_URL']?.trim();
  if (configured == null || configured.isEmpty) {
    stderr.writeln('PUBLIC_SYNC_RELAY_URL is not configured.');
    exitCode = 2;
    return;
  }

  final random = Random.secure();
  final room = List<int>.generate(16, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final inboxA = base64Url.encode(utf8.encode('smoke-a-$suffix')).replaceAll('=', '');
  final inboxB = base64Url.encode(utf8.encode('smoke-b-$suffix')).replaceAll('=', '');
  final topicA = 'adventurers-guild-peer/v1/$room/inbox/$inboxA';
  final topicB = 'adventurers-guild-peer/v1/$room/inbox/$inboxB';
  final payload = 'relay-smoke-$suffix';

  Uri endpoint(String inbox, String client) {
    final parsed = Uri.parse(configured);
    final scheme = switch (parsed.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' || 'ws' => parsed.scheme,
      _ => throw FormatException('Unsupported relay scheme: ${parsed.scheme}'),
    };
    final path = parsed.path.isEmpty || parsed.path == '/' ? '/sync' : parsed.path;
    return parsed.replace(
      scheme: scheme,
      path: path,
      queryParameters: <String, String>{
        ...parsed.queryParameters,
        'room': room,
        'inbox': inbox,
        'client': client,
      },
    );
  }

  WebSocket? a;
  WebSocket? b;
  StreamSubscription<dynamic>? bSubscription;
  try {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        b = await WebSocket.connect(endpoint(inboxB, 'smoke-b-$suffix').toString())
            .timeout(const Duration(seconds: 10));
        a = await WebSocket.connect(endpoint(inboxA, 'smoke-a-$suffix').toString())
            .timeout(const Duration(seconds: 10));
        break;
      } catch (error) {
        lastError = error;
        await a?.close();
        await b?.close();
        a = null;
        b = null;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }
    if (a == null || b == null) {
      throw StateError('Relay connection failed after retries: $lastError');
    }

    final received = Completer<void>();
    bSubscription = b.listen((event) {
      if (event is! String || received.isCompleted) return;
      try {
        final decoded = jsonDecode(event);
        if (decoded is Map &&
            decoded['topic'] == topicB &&
            decoded['payload'] == payload) {
          received.complete();
        }
      } catch (_) {}
    });

    a.add(jsonEncode(<String, dynamic>{
      'type': 'publish',
      'topic': topicB,
      'payload': payload,
    }));

    await received.future.timeout(const Duration(seconds: 10));
    stdout.writeln('Cloudflare relay runtime smoke test passed.');
  } finally {
    await bSubscription?.cancel();
    await a?.close(WebSocketStatus.normalClosure, 'smoke-complete');
    await b?.close(WebSocketStatus.normalClosure, 'smoke-complete');
  }
}
