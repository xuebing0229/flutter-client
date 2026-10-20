import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef PublicPeerSignalSender = Future<void> Function(
  String targetDeviceId,
  Map<String, dynamic> signal,
);
typedef PublicPeerFrameHandler = Future<void> Function(
  String senderDeviceId,
  String frame,
);

/// WebRTC data-channel path for browser/native peer sync.
///
/// MQTT remains the encrypted signaling path and fallback transport. When a
/// direct data channel can be established, application frames stop traversing
/// the public relay and flow device-to-device instead.
class PublicPeerWebRtcTransport {
  PublicPeerWebRtcTransport({
    required this.deviceId,
    required this.sendSignal,
    required this.onFrame,
  });

  static const Duration _openTimeout = Duration(seconds: 4);

  final String deviceId;
  final PublicPeerSignalSender sendSignal;
  final PublicPeerFrameHandler onFrame;

  final Map<String, _PeerSession> _peers = <String, _PeerSession>{};
  final Map<String, Future<_PeerSession>> _creating =
      <String, Future<_PeerSession>>{};
  bool _disposed = false;

  bool get hasOpenPeer => _peers.values.any(
        (session) =>
            session.channel?.state == RTCDataChannelState.RTCDataChannelOpen,
      );

  Future<bool> send(String peerId, String frame) async {
    if (_disposed || peerId.isEmpty || peerId == deviceId) return false;

    final shouldInitiate = deviceId.compareTo(peerId) < 0;
    final session = await _ensurePeer(peerId, initiate: shouldInitiate);
    final channel = await _waitForOpen(session);
    if (channel == null) return false;

    try {
      await channel.send(RTCDataChannelMessage(frame));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> handleSignal(
    String peerId,
    Map<String, dynamic> signal,
  ) async {
    if (_disposed || peerId.isEmpty || peerId == deviceId) return;
    final type = signal['type'];
    if (type is! String) return;

    switch (type) {
      case 'offer':
        final sdp = signal['sdp'];
        if (sdp is! String || sdp.isEmpty) return;
        final session = await _ensurePeer(peerId, initiate: false);
        await session.connection.setRemoteDescription(
          RTCSessionDescription(sdp, 'offer'),
        );
        session.remoteDescriptionSet = true;
        await _flushCandidates(session);
        final answer = await session.connection.createAnswer();
        await session.connection.setLocalDescription(answer);
        final answerSdp = answer.sdp;
        if (answerSdp != null && answerSdp.isNotEmpty) {
          await sendSignal(peerId, <String, dynamic>{
            'type': 'answer',
            'sdp': answerSdp,
          });
        }
        break;
      case 'answer':
        final sdp = signal['sdp'];
        if (sdp is! String || sdp.isEmpty) return;
        final session = _peers[peerId];
        if (session == null) return;
        await session.connection.setRemoteDescription(
          RTCSessionDescription(sdp, 'answer'),
        );
        session.remoteDescriptionSet = true;
        await _flushCandidates(session);
        break;
      case 'candidate':
        final candidate = signal['candidate'];
        if (candidate is! String || candidate.isEmpty) return;
        final sdpMid = signal['sdpMid'] as String?;
        final rawIndex = signal['sdpMLineIndex'];
        final index = rawIndex is num ? rawIndex.toInt() : null;
        final rtcCandidate = RTCIceCandidate(candidate, sdpMid, index);
        final session = await _ensurePeer(peerId, initiate: false);
        if (!session.remoteDescriptionSet) {
          session.pendingCandidates.add(rtcCandidate);
        } else {
          await session.connection.addCandidate(rtcCandidate);
        }
        break;
      case 'reset':
        await _closePeer(peerId);
        break;
    }
  }

  Future<_PeerSession> _ensurePeer(
    String peerId, {
    required bool initiate,
  }) async {
    final existing = _peers[peerId];
    if (existing != null) return existing;

    final pending = _creating[peerId];
    if (pending != null) return pending;

    final future = _createPeer(peerId, initiate: initiate);
    _creating[peerId] = future;
    try {
      return await future;
    } finally {
      _creating.remove(peerId);
    }
  }

  Future<_PeerSession> _createPeer(
    String peerId, {
    required bool initiate,
  }) async {
    final connection = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.cloudflare.com:3478'},
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    final session = _PeerSession(peerId: peerId, connection: connection);
    _peers[peerId] = session;

    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (_disposed || value == null || value.isEmpty) return;
      unawaited(
        sendSignal(peerId, <String, dynamic>{
          'type': 'candidate',
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };

    connection.onDataChannel = (channel) {
      _attachChannel(session, channel);
    };

    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_closePeer(peerId, expected: session));
      }
    };

    if (initiate) {
      final init = RTCDataChannelInit()..ordered = true;
      final channel = await connection.createDataChannel('guild-sync-v1', init);
      _attachChannel(session, channel);

      final offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      final offerSdp = offer.sdp;
      if (offerSdp != null && offerSdp.isNotEmpty) {
        await sendSignal(peerId, <String, dynamic>{
          'type': 'offer',
          'sdp': offerSdp,
        });
      }
    }

    return session;
  }

  void _attachChannel(_PeerSession session, RTCDataChannel channel) {
    final old = session.channel;
    if (identical(old, channel)) return;
    session.channel = channel;

    channel.onMessage = (message) {
      if (_disposed || message.isBinary) return;
      unawaited(onFrame(session.peerId, message.text));
    };
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (!session.opened.isCompleted) session.opened.complete();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        if (!session.opened.isCompleted) {
          session.opened.completeError(StateError('WebRTC data channel closed'));
        }
      }
    };
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
        !session.opened.isCompleted) {
      session.opened.complete();
    }
  }

  Future<RTCDataChannel?> _waitForOpen(_PeerSession session) async {
    final current = session.channel;
    if (current?.state == RTCDataChannelState.RTCDataChannelOpen) {
      return current;
    }
    try {
      await session.opened.future.timeout(_openTimeout);
    } catch (_) {
      return null;
    }
    final channel = session.channel;
    return channel?.state == RTCDataChannelState.RTCDataChannelOpen
        ? channel
        : null;
  }

  Future<void> _flushCandidates(_PeerSession session) async {
    if (!session.remoteDescriptionSet || session.pendingCandidates.isEmpty) {
      return;
    }
    final pending = List<RTCIceCandidate>.from(session.pendingCandidates);
    session.pendingCandidates.clear();
    for (final candidate in pending) {
      await session.connection.addCandidate(candidate);
    }
  }

  Future<void> _closePeer(
    String peerId, {
    _PeerSession? expected,
  }) async {
    final session = _peers[peerId];
    if (session == null || (expected != null && !identical(session, expected))) {
      return;
    }
    _peers.remove(peerId);
    try {
      await session.channel?.close();
    } catch (_) {}
    try {
      await session.connection.close();
    } catch (_) {}
    try {
      await session.connection.dispose();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final ids = _peers.keys.toList(growable: false);
    for (final peerId in ids) {
      await _closePeer(peerId);
    }
    _creating.clear();
  }
}

class _PeerSession {
  _PeerSession({
    required this.peerId,
    required this.connection,
  });

  final String peerId;
  final RTCPeerConnection connection;
  final Completer<void> opened = Completer<void>();
  final List<RTCIceCandidate> pendingCandidates = <RTCIceCandidate>[];
  RTCDataChannel? channel;
  bool remoteDescriptionSet = false;
}
