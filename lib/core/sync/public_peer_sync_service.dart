import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../account/account_models.dart';
import 'public_relay_client.dart';
import 'public_webrtc_transport.dart';

typedef PeerAccountStateReader = AccountSyncState Function();
typedef PeerAccountStateMerger = Future<void> Function(AccountSyncState state);
typedef PeerRecordExporter = Future<List<Map<String, dynamic>>> Function();
typedef PeerRecordMerger =
    Future<void> Function(List<Map<String, dynamic>> records);
typedef PeerAssetPathReader = Iterable<String> Function();
typedef PeerAssetExists = Future<bool> Function(String relativePath);
typedef PeerAssetReader = Future<Uint8List?> Function(String relativePath);
typedef PeerAssetWriter =
    Future<void> Function(String relativePath, Uint8List bytes);

/// Browser-compatible online sync that keeps the native Syncthing path intact.
///
/// A public MQTT service is only a transient relay. Every application payload
/// is AES-GCM encrypted before it leaves the device and retained messages are
/// never used, so both devices still need to be online at the same time.
class PublicPeerSyncService extends ChangeNotifier {
  PublicPeerSyncService({
    required this.accountId,
    required this.deviceId,
    required this.captureAccountState,
    required this.mergeAccountState,
    required this.exportRecords,
    required this.mergeRecords,
    this.captureAssetPaths,
    this.assetExists,
    this.readAsset,
    this.writeAsset,
  });

  static const String _topicRoot = 'adventurers-guild-peer/v1';
  static const int _chunkCharacters = 22000;
  static const Duration _heartbeat = Duration(seconds: 12);

  final String accountId;
  final String deviceId;
  final PeerAccountStateReader captureAccountState;
  final PeerAccountStateMerger mergeAccountState;
  final PeerRecordExporter exportRecords;
  final PeerRecordMerger mergeRecords;
  final PeerAssetPathReader? captureAssetPaths;
  final PeerAssetExists? assetExists;
  final PeerAssetReader? readAsset;
  final PeerAssetWriter? writeAsset;

  final AesGcm _cipher = AesGcm.with256bits();
  final Random _random = Random.secure();
  final Map<String, _IncomingTransfer> _incoming =
      <String, _IncomingTransfer>{};
  final Map<String, String> _lastIncomingFingerprintByPeer =
      <String, String>{};

  PublicRelayClient? _relay;
  PublicPeerWebRtcTransport? _webrtc;
  StreamSubscription<PublicRelayMessage>? _relaySubscription;
  Timer? _heartbeatTimer;
  Timer? _syncDebounce;
  SecretKey? _secretKey;
  String? _roomHash;
  bool _disposed = false;
  bool _starting = false;
  bool _syncing = false;
  bool _connected = false;
  String? _lastError;
  DateTime? _lastSuccessfulSyncAt;

  bool get connected => _connected;
  bool get syncing => _syncing;
  String? get lastError => _lastError;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;

  Future<void> start() async {
    if (_disposed || _starting || _relay != null) return;
    _starting = true;
    try {
      await _prepareRoom();
      _webrtc = PublicPeerWebRtcTransport(
        deviceId: deviceId,
        sendSignal: _sendRtcSignal,
        onFrame: (sender, frame) => _handleRelayMessage(
          PublicRelayMessage(topic: _inboxTopic, payload: frame),
        ),
      );
      final relay = PublicRelayClient(clientId: _mqttClientId());
      _relay = relay;
      _relaySubscription = relay.messages.listen(
        (message) => unawaited(_handleRelayMessage(message)),
      );
      await _connectRelay();
      _heartbeatTimer = Timer.periodic(_heartbeat, (_) {
        unawaited(_heartbeatTick());
      });
      requestSync(immediate: true);
    } catch (error) {
      _lastError = '公共同步网络启动失败：$error';
      _connected = false;
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  Future<void> _prepareRoom() async {
    final state = captureAccountState();
    if (state.accountId != accountId || state.devices.isEmpty) {
      throw StateError('账号设备身份尚未准备好');
    }

    final devices = state.devices.values.toList(growable: false)
      ..sort((left, right) {
        final time = left.firstSeenAt.compareTo(right.firstSeenAt);
        return time == 0 ? left.id.compareTo(right.id) : time;
      });
    final anchor = devices.first;
    final seed =
        'guild-peer-sync-v1\u0000$accountId\u0000${anchor.id}';
    final roomDigest = await Sha256().hash(utf8.encode(seed));
    final keyDigest = await Sha256().hash(
      utf8.encode('guild-peer-key-v1\u0000$seed'),
    );
    _roomHash = _hex(roomDigest.bytes).substring(0, 32);
    _secretKey = SecretKey(keyDigest.bytes);
  }

  String _mqttClientId() {
    final compact = base64Url
        .encode(utf8.encode(deviceId))
        .replaceAll('=', '');
    final tail = compact.length <= 12
        ? compact
        : compact.substring(compact.length - 12);
    final nonce = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'ag-$tail-$nonce';
  }

  String get _inboxTopic =>
      '$_topicRoot/${_roomHash!}/inbox/${_topicDevice(deviceId)}';

  String _topicFor(String targetDeviceId) =>
      '$_topicRoot/${_roomHash!}/inbox/${_topicDevice(targetDeviceId)}';

  String _topicDevice(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  Future<void> _connectRelay() async {
    final relay = _relay;
    if (relay == null) return;
    try {
      await relay.connect(<String>[_inboxTopic]);
      _connected = relay.connected;
      if (_connected) _lastError = null;
    } catch (error) {
      _connected = false;
      _lastError = '公共同步网络连接失败：$error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _heartbeatTick() async {
    if (_disposed) return;
    _dropExpiredTransfers();
    if (_relay?.connected != true) {
      await _connectRelay();
    }
    if (_relay?.connected == true || _webrtc?.hasOpenPeer == true) {
      await _publishSnapshot();
    }
  }

  void requestSync({bool immediate = false}) {
    if (_disposed) return;
    _syncDebounce?.cancel();
    if (immediate) {
      unawaited(_publishSnapshot());
      return;
    }
    _syncDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_publishSnapshot()),
    );
  }

  Future<void> _publishSnapshot({String? onlyTarget}) async {
    if (_disposed || _syncing) return;
    if (_relay?.connected != true) {
      await _connectRelay();
      if (_relay?.connected != true && _webrtc?.hasOpenPeer != true) return;
    }

    final state = captureAccountState();
    if (state.accountId != accountId || state.isRevoked(deviceId)) return;

    final targets = <String>[
      for (final device in state.activeDevices)
        if (device.id != deviceId &&
            (onlyTarget == null || device.id == onlyTarget))
          device.id,
    ];
    if (targets.isEmpty) return;

    _syncing = true;
    notifyListeners();
    try {
      final records = await exportRecords();
      final assets = <String>{
        ...?captureAssetPaths?.call(),
      }.toList(growable: false)
        ..sort();

      final payload = <String, dynamic>{
        'type': 'snapshot',
        'accountId': accountId,
        'sender': deviceId,
        'account': state.toJson(),
        'records': records,
        'assets': assets,
      };
      for (final target in targets) {
        await _sendEncrypted(target, payload);
      }
      _lastSuccessfulSyncAt = DateTime.now();
      _lastError = null;
    } catch (error) {
      _lastError = '发送同步数据失败：$error';
    } finally {
      _syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _sendRtcSignal(
    String targetDeviceId,
    Map<String, dynamic> signal,
  ) {
    return _sendEncrypted(
      targetDeviceId,
      <String, dynamic>{
        'type': 'rtc-signal',
        'accountId': accountId,
        'sender': deviceId,
        'signal': signal,
      },
      allowDirect: false,
    );
  }

  Future<void> _sendEncrypted(
    String targetDeviceId,
    Map<String, dynamic> payload, {
    bool allowDirect = true,
  }) async {
    final relay = _relay;
    final secretKey = _secretKey;
    if (secretKey == null) return;

    final clear = utf8.encode(jsonEncode(payload));
    final box = await _cipher.encrypt(clear, secretKey: secretKey);
    final protected = jsonEncode(<String, dynamic>{
      'nonce': base64UrlEncode(box.nonce),
      'mac': base64UrlEncode(box.mac.bytes),
      'cipher': base64UrlEncode(box.cipherText),
    });

    final transferId =
        '${deviceId.substring(0, min(8, deviceId.length))}-'
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(0x7fffffff).toRadixString(36)}';
    final total = (protected.length / _chunkCharacters).ceil().clamp(1, 100000);

    for (var index = 0; index < total; index++) {
      final start = index * _chunkCharacters;
      final end = min(protected.length, start + _chunkCharacters);
      final frame = jsonEncode(<String, dynamic>{
        'v': 1,
        'id': transferId,
        'from': deviceId,
        'to': targetDeviceId,
        'index': index,
        'total': total,
        'data': protected.substring(start, end),
      });
      var sentDirect = false;
      if (allowDirect) {
        try {
          sentDirect = await _webrtc?.send(targetDeviceId, frame) ?? false;
        } catch (_) {
          sentDirect = false;
        }
      }
      if (!sentDirect) {
        if (relay == null || !relay.connected) {
          throw StateError('点对点连接不可用，公共同步网络也未连接');
        }
        relay.publish(_topicFor(targetDeviceId), frame);
      }
      if (index % 8 == 7) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }
  }

  Future<void> _handleRelayMessage(PublicRelayMessage message) async {
    if (_disposed || message.topic != _inboxTopic) return;

    Map<String, dynamic> frame;
    try {
      final raw = jsonDecode(message.payload);
      if (raw is! Map) return;
      frame = raw.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return;
    }

    if (frame['v'] != 1 ||
        frame['to'] != deviceId ||
        frame['from'] is! String ||
        frame['id'] is! String ||
        frame['index'] is! int ||
        frame['total'] is! int ||
        frame['data'] is! String) {
      return;
    }

    final sender = frame['from'] as String;
    if (sender == deviceId) return;
    final localState = captureAccountState();
    if (localState.isRevoked(sender)) return;

    final total = frame['total'] as int;
    final index = frame['index'] as int;
    if (total <= 0 || total > 100000 || index < 0 || index >= total) return;

    final id = frame['id'] as String;
    final transfer = _incoming.putIfAbsent(
      id,
      () => _IncomingTransfer(sender: sender, total: total),
    );
    if (transfer.sender != sender || transfer.total != total) {
      _incoming.remove(id);
      return;
    }
    transfer.chunks[index] = frame['data'] as String;
    transfer.lastUpdatedAt = DateTime.now();
    if (transfer.chunks.length != total) return;

    _incoming.remove(id);
    final protected = StringBuffer();
    for (var i = 0; i < total; i++) {
      final chunk = transfer.chunks[i];
      if (chunk == null) return;
      protected.write(chunk);
    }
    await _handleEncrypted(sender, protected.toString());
  }

  Future<void> _handleEncrypted(String sender, String source) async {
    final secretKey = _secretKey;
    if (secretKey == null) return;

    try {
      final raw = jsonDecode(source);
      if (raw is! Map ||
          raw['nonce'] is! String ||
          raw['mac'] is! String ||
          raw['cipher'] is! String) {
        return;
      }
      final box = SecretBox(
        base64Url.decode(raw['cipher'] as String),
        nonce: base64Url.decode(raw['nonce'] as String),
        mac: Mac(base64Url.decode(raw['mac'] as String)),
      );
      final clear = await _cipher.decrypt(box, secretKey: secretKey);
      final clearText = utf8.decode(clear);
      final fingerprint = _hex((await Sha256().hash(clear)).bytes);
      final decoded = jsonDecode(clearText);
      if (decoded is! Map) return;
      final payload =
          decoded.map((key, value) => MapEntry(key.toString(), value));
      if (payload['accountId'] != accountId ||
          payload['sender'] != sender ||
          payload['type'] is! String) {
        return;
      }

      switch (payload['type'] as String) {
        case 'snapshot':
          if (_lastIncomingFingerprintByPeer[sender] == fingerprint) return;
          _lastIncomingFingerprintByPeer[sender] = fingerprint;
          await _receiveSnapshot(sender, payload);
          break;
        case 'asset-request':
          await _receiveAssetRequest(sender, payload);
          break;
        case 'asset':
          await _receiveAsset(sender, payload);
          break;
        case 'rtc-signal':
          final rawSignal = payload['signal'];
          if (rawSignal is Map) {
            await _webrtc?.handleSignal(
              sender,
              rawSignal.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
          break;
      }
    } catch (_) {
      // Wrong rooms, stale chunks and tampered public-relay messages are
      // intentionally ignored without surfacing their contents.
    }
  }

  Future<void> _receiveSnapshot(
    String sender,
    Map<String, dynamic> payload,
  ) async {
    final accountRaw = payload['account'];
    final recordRaw = payload['records'];
    if (accountRaw is! Map || recordRaw is! List) return;

    final incomingAccount = AccountSyncState.fromCompatibleJson(
      accountRaw.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (incomingAccount.accountId != accountId) return;

    final localBefore = captureAccountState();
    if (localBefore.isRevoked(sender)) return;

    final records = <Map<String, dynamic>>[];
    for (final item in recordRaw) {
      if (item is Map) {
        records.add(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }

    await mergeAccountState(incomingAccount);
    if (captureAccountState().isRevoked(deviceId)) return;
    await mergeRecords(records);

    final missing = <String>[];
    final exists = assetExists;
    final assetList = payload['assets'];
    if (exists != null && assetList is List) {
      for (final value in assetList.whereType<String>()) {
        if (value.isEmpty || missing.length >= 200) continue;
        try {
          if (!await exists(value)) missing.add(value);
        } catch (_) {}
      }
    }
    if (missing.isNotEmpty) {
      await _sendEncrypted(sender, <String, dynamic>{
        'type': 'asset-request',
        'accountId': accountId,
        'sender': deviceId,
        'paths': missing,
      });
    }

    _lastSuccessfulSyncAt = DateTime.now();
    _lastError = null;
    if (!_disposed) notifyListeners();
    requestSync(immediate: true);
  }

  Future<void> _receiveAssetRequest(
    String sender,
    Map<String, dynamic> payload,
  ) async {
    final reader = readAsset;
    if (reader == null) return;
    final rawPaths = payload['paths'];
    if (rawPaths is! List) return;

    for (final path in rawPaths.whereType<String>().take(200)) {
      try {
        final bytes = await reader(path);
        if (bytes == null) continue;
        await _sendEncrypted(sender, <String, dynamic>{
          'type': 'asset',
          'accountId': accountId,
          'sender': deviceId,
          'path': path,
          'bytes': base64Encode(bytes),
        });
      } catch (_) {}
    }
  }

  Future<void> _receiveAsset(
    String sender,
    Map<String, dynamic> payload,
  ) async {
    final writer = writeAsset;
    final path = payload['path'];
    final encoded = payload['bytes'];
    if (writer == null || path is! String || encoded is! String) return;

    final state = captureAccountState();
    if (state.isRevoked(sender)) return;

    try {
      final bytes = Uint8List.fromList(base64Decode(encoded));
      await writer(path, bytes);
      _lastSuccessfulSyncAt = DateTime.now();
      _lastError = null;
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  void _dropExpiredTransfers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    _incoming.removeWhere(
      (_, transfer) => transfer.lastUpdatedAt.isBefore(cutoff),
    );
  }

  String _hex(List<int> bytes) => bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncDebounce?.cancel();
    _heartbeatTimer?.cancel();
    unawaited(_relaySubscription?.cancel());
    _relaySubscription = null;
    final relay = _relay;
    _relay = null;
    final webrtc = _webrtc;
    _webrtc = null;
    if (webrtc != null) unawaited(webrtc.dispose());
    if (relay != null) unawaited(relay.dispose());
    super.dispose();
  }
}

class _IncomingTransfer {
  _IncomingTransfer({required this.sender, required this.total})
      : lastUpdatedAt = DateTime.now();

  final String sender;
  final int total;
  final Map<int, String> chunks = <int, String>{};
  DateTime lastUpdatedAt;
}
