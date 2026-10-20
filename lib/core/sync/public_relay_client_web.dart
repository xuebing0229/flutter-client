import 'dart:async';

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

class PublicRelayMessage {
  const PublicRelayMessage({required this.topic, required this.payload});
  final String topic;
  final String payload;
}

class PublicRelayClient {
  PublicRelayClient({required this.clientId});

  final String clientId;
  MqttBrowserClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _subscription;
  final StreamController<PublicRelayMessage> _messages =
      StreamController<PublicRelayMessage>.broadcast();

  Stream<PublicRelayMessage> get messages => _messages.stream;

  bool get connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect(Iterable<String> topics) async {
    if (connected) {
      for (final topic in topics) {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
      }
      return;
    }
    await disconnect();

    final client = MqttBrowserClient(
      'wss://test.mosquitto.org',
      clientId,
    )
      ..port = 8081
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 6000
      ..autoReconnect = false
      ..websocketProtocols = MqttClientConstants.protocolsSingleDefault
      ..setProtocolV311();

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
      rethrow;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final status = client.connectionStatus;
      client.disconnect();
      throw StateError('公共同步网络连接失败：$status');
    }

    _client = client;
    _subscription = client.updates?.listen((events) {
      for (final event in events) {
        final payload = event.payload;
        if (payload is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );
        if (!_messages.isClosed) {
          _messages.add(PublicRelayMessage(topic: event.topic, payload: text));
        }
      }
    });
    for (final topic in topics) {
      client.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void publish(String topic, String payload) {
    final client = _client;
    if (client == null || !connected) {
      throw StateError('公共同步网络尚未连接');
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    final bytes = builder.payload;
    if (bytes == null) return;
    client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      bytes,
      retain: false,
    );
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    final client = _client;
    _client = null;
    client?.disconnect();
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
