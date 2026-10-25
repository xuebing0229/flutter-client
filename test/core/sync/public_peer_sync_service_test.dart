import 'dart:async';

import 'package:flutter_app/core/account/account_models.dart';
import 'package:flutter_app/core/sync/public_peer_sync_service.dart';
import 'package:flutter_app/core/sync/public_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unacknowledged web change is retried when the other device comes online',
    () async {
      final hub = _RelayHub();
      final nativeDevice = AccountDevice(
        id: 'native-device',
        name: '手机',
        platform: 'android',
        firstSeenAt: DateTime.utc(2026, 1, 1),
        lastSeenAt: DateTime.utc(2026, 1, 1),
      );
      final webDevice = AccountDevice(
        id: 'web-device',
        name: '网页设备',
        platform: 'web',
        firstSeenAt: DateTime.utc(2026, 1, 2),
        lastSeenAt: DateTime.utc(2026, 1, 2),
      );

      AccountSyncState nativeState = _state(
        devices: <String, AccountDevice>{
          nativeDevice.id: nativeDevice,
        },
      );
      AccountSyncState webState = _state(
        devices: <String, AccountDevice>{
          nativeDevice.id: nativeDevice,
          webDevice.id: webDevice,
        },
      );

      final webRecords = <Map<String, dynamic>>[
        <String, dynamic>{'marker': 'edited-on-web'},
      ];
      List<Map<String, dynamic>> nativeReceived = const [];
      final received = Completer<void>();

      final web = PublicPeerSyncService(
        accountId: webState.accountId,
        deviceId: webDevice.id,
        captureAccountState: () => webState,
        mergeAccountState: (incoming) async {
          webState = webState.merge(incoming);
        },
        exportRecords: () async => webRecords,
        mergeRecords: (_) async {},
        relayFactory: hub.createClient,
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      addTearDown(web.dispose);

      await web.start();

      // Let the first snapshot be sent while the native peer is offline. The
      // relay deliberately has no offline queue, so this attempt is dropped.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(web.lastSuccessfulSyncAt, isNull);

      final native = PublicPeerSyncService(
        accountId: nativeState.accountId,
        deviceId: nativeDevice.id,
        captureAccountState: () => nativeState,
        mergeAccountState: (incoming) async {
          nativeState = nativeState.merge(incoming);
        },
        exportRecords: () async => const <Map<String, dynamic>>[],
        mergeRecords: (incoming) async {
          nativeReceived = [
            for (final item in incoming) Map<String, dynamic>.from(item),
          ];
          if (!received.isCompleted) received.complete();
        },
        relayFactory: hub.createClient,
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      addTearDown(native.dispose);

      await native.start();

      await received.future.timeout(const Duration(seconds: 1));

      expect(nativeReceived, webRecords);
      expect(nativeState.devices, contains(webDevice.id));

      // The sender only marks the transfer successful after the receiving peer
      // has processed it and returned the encrypted acknowledgement.
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (web.lastSuccessfulSyncAt == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(web.lastSuccessfulSyncAt, isNotNull);

      // Once both directions are acknowledged, the protocol must become idle
      // instead of bouncing snapshots forever.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final settledPublishCount = hub.publishCount;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(hub.publishCount, settledPublishCount);
    },
  );
}

AccountSyncState _state({
  required Map<String, AccountDevice> devices,
}) {
  return AccountSyncState(
    accountId: 'account-1',
    accountName: '雪饼',
    password: 'test-password',
    accountNameUpdatedAt: DateTime.utc(2026, 1, 1),
    passwordUpdatedAt: DateTime.utc(2026, 1, 1),
    devices: devices,
    revocations: const <String, DeviceRevocation>{},
  );
}

class _RelayHub {
  int publishCount = 0;

  final Map<String, Set<_FakeRelayClient>> _listeners =
      <String, Set<_FakeRelayClient>>{};

  PublicRelayClient createClient(String clientId) {
    return _FakeRelayClient(clientId: clientId, hub: this);
  }

  void subscribe(String topic, _FakeRelayClient client) {
    _listeners.putIfAbsent(topic, () => <_FakeRelayClient>{}).add(client);
  }

  void unsubscribe(String? topic, _FakeRelayClient client) {
    if (topic == null) return;
    final listeners = _listeners[topic];
    listeners?.remove(client);
    if (listeners?.isEmpty ?? false) {
      _listeners.remove(topic);
    }
  }

  void publish(
    _FakeRelayClient sender,
    String topic,
    String payload,
  ) {
    publishCount += 1;
    final targets = List<_FakeRelayClient>.from(
      _listeners[topic] ?? const <_FakeRelayClient>{},
    );
    for (final target in targets) {
      if (identical(target, sender)) continue;
      target.emit(PublicRelayMessage(topic: topic, payload: payload));
    }
  }
}

class _FakeRelayClient extends PublicRelayClient {
  _FakeRelayClient({
    required super.clientId,
    required this.hub,
  });

  final _RelayHub hub;
  final StreamController<PublicRelayMessage> _controller =
      StreamController<PublicRelayMessage>.broadcast();

  String? _topic;
  bool _connected = false;

  @override
  Stream<PublicRelayMessage> get messages => _controller.stream;

  @override
  bool get connected => _connected;

  @override
  Future<void> connect(Iterable<String> topics) async {
    final values = topics.toList(growable: false);
    if (values.length != 1) {
      throw StateError('test relay requires one topic');
    }
    await disconnect();
    _topic = values.single;
    _connected = true;
    hub.subscribe(_topic!, this);
  }

  @override
  void publish(String topic, String payload) {
    if (!_connected) throw StateError('test relay is disconnected');
    hub.publish(this, topic, payload);
  }

  void emit(PublicRelayMessage message) {
    if (!_controller.isClosed) _controller.add(message);
  }

  @override
  Future<void> disconnect() async {
    hub.unsubscribe(_topic, this);
    _topic = null;
    _connected = false;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
