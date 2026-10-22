import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../account/account_models.dart';
import 'sync_join_diagnostics.dart';
import 'windows_syncthing_transport.dart';

class EmbeddedSyncthingStatus {
  const EmbeddedSyncthingStatus({
    required this.available,
    required this.running,
    this.deviceId,
    this.version,
    this.connectedDeviceIds = const <String>[],
    this.configuredDevices = const <Map<String, dynamic>>[],
    this.folderState,
    this.remoteFolderStates = const <String, String>{},
    this.folderErrors = const <String>[],
    this.syncProgress,
    this.error,
  });

  final bool available;
  final bool running;
  final String? deviceId;
  final String? version;
  final List<String> connectedDeviceIds;
  final List<Map<String, dynamic>> configuredDevices;
  final String? folderState;

  /// Folder-level handshake state reported by each connected peer.
  ///
  /// Syncthing reports "valid" only after the remote device has accepted and
  /// shares this exact folder back. Device connectivity alone is not enough.
  final Map<String, String> remoteFolderStates;

  /// Runtime scan/pull errors for this exact folder.
  final List<String> folderErrors;

  final Map<String, dynamic>? syncProgress;
  final String? error;

  factory EmbeddedSyncthingStatus.fromMap(Map<Object?, Object?> map) {
    List<Map<String, dynamic>> mapList(Object? value) {
      if (value is! List) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final item in value)
          if (item is Map)
            item.map((key, value) => MapEntry(key.toString(), value)),
      ];
    }

    return EmbeddedSyncthingStatus(
      available: map['available'] == true,
      running: map['running'] == true,
      deviceId: map['deviceId'] as String?,
      version: map['version'] as String?,
      connectedDeviceIds: [
        if (map['connectedDeviceIds'] is List)
          for (final item in map['connectedDeviceIds'] as List)
            if (item is String) item,
      ],
      configuredDevices: mapList(map['configuredDevices']),
      folderState: map['folderState'] as String?,
      remoteFolderStates: map['remoteFolderStates'] is Map
          ? <String, String>{
              for (final entry in (map['remoteFolderStates'] as Map).entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const <String, String>{},
      folderErrors: [
        if (map['folderErrors'] is List)
          for (final item in map['folderErrors'] as List)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      syncProgress: map['syncProgress'] is Map
          ? (map['syncProgress'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : null,
      error: map['error'] as String?,
    );
  }
}

class EmbeddedSyncthingBridge {
  const EmbeddedSyncthingBridge();

  static const MethodChannel _channel = MethodChannel('app.syncthing');

  bool get supported => Platform.isAndroid || Platform.isWindows;

  Future<bool> prepareFolder({
    required String folderId,
    required String label,
    required String folderPath,
    bool force = false,
  }) async {
    if (!supported) return false;
    final diagnostic = _isJoinDiagnosticFolder(folderId);
    if (diagnostic) {
      await SyncJoinDiagnostics.record('bridge.prepare.begin', <String, Object?>{
        'folderId': folderId,
        'force': force,
      });
    }
    try {
      bool prepared;
      if (Platform.isWindows) {
        prepared = await WindowsSyncthingTransport.instance.prepare(
          folderId: folderId,
          label: label,
          folderPath: folderPath,
          force: force,
        );
      } else {
        await _channel.invokeMapMethod<Object?, Object?>('ensureStarted');
        await _channel.invokeMethod<void>('configureFolder', <String, dynamic>{
          'folderId': folderId,
          'label': label,
          'path': folderPath,
        });
        prepared = true;
      }
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.prepare.success', <String, Object?>{
          'folderId': folderId,
          'prepared': prepared,
        });
      }
      return prepared;
    } catch (error) {
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.prepare.error', <String, Object?>{
          'folderId': folderId,
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  Future<EmbeddedSyncthingStatus> statusFolder(String folderId) async {
    if (!supported) {
      return const EmbeddedSyncthingStatus(
        available: false,
        running: false,
        error: '当前平台暂未接入内置同步核心',
      );
    }
    EmbeddedSyncthingStatus status;
    try {
      if (Platform.isWindows) {
        status = EmbeddedSyncthingStatus.fromMap(
          await WindowsSyncthingTransport.instance.status(folderId),
        );
      } else {
        final raw = await _channel.invokeMapMethod<Object?, Object?>(
          'status',
          <String, dynamic>{'folderId': folderId},
        );
        if (raw == null) {
          throw StateError('同步核心没有返回状态。');
        }
        status = EmbeddedSyncthingStatus.fromMap(raw);
      }
    } on PlatformException catch (error) {
      status = EmbeddedSyncthingStatus(
        available: false,
        running: false,
        error: error.message ?? error.code,
      );
    }
    if (_isJoinDiagnosticFolder(folderId)) {
      await SyncJoinDiagnostics.record(
        'bridge.status',
        _statusDiagnosticFields(folderId, status),
      );
    }
    return status;
  }

  Future<void> pairFolder({
    required String folderId,
    required String deviceId,
    required String name,
  }) async {
    if (!supported) return;
    final diagnostic = _isJoinDiagnosticFolder(folderId);
    if (diagnostic) {
      await SyncJoinDiagnostics.record('bridge.pair.begin', <String, Object?>{
        'folderId': folderId,
        'deviceId': deviceId.trim(),
        'name': name.trim(),
      });
    }
    try {
      if (Platform.isWindows) {
        await WindowsSyncthingTransport.instance.pairDevice(
          folderId: folderId,
          deviceId: deviceId,
          name: name,
        );
      } else {
        await _channel.invokeMethod<void>('pairDevice', <String, dynamic>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
          'name': name.trim(),
        });
      }
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.pair.success', <String, Object?>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
        });
      }
    } catch (error) {
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.pair.error', <String, Object?>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  Future<void> unshareFolderDevice({
    required String folderId,
    required String deviceId,
  }) async {
    if (!supported) return;
    final diagnostic = _isJoinDiagnosticFolder(folderId);
    if (diagnostic) {
      await SyncJoinDiagnostics.record('bridge.unshare.begin', <String, Object?>{
        'folderId': folderId,
        'deviceId': deviceId.trim(),
      });
    }
    try {
      if (Platform.isWindows) {
        await WindowsSyncthingTransport.instance.unshareDevice(
          folderId: folderId,
          deviceId: deviceId,
        );
      } else {
        await _channel.invokeMethod<void>('unshareDevice', <String, dynamic>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
        });
      }
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.unshare.success', <String, Object?>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
        });
      }
    } catch (error) {
      if (diagnostic) {
        await SyncJoinDiagnostics.record('bridge.unshare.error', <String, Object?>{
          'folderId': folderId,
          'deviceId': deviceId.trim(),
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  Future<void> requestScanFolder(String folderId) async {
    if (!supported) return;
    try {
      if (Platform.isWindows) {
        await WindowsSyncthingTransport.instance.requestScan(folderId);
      } else {
        await _channel.invokeMethod<void>('requestScan', <String, dynamic>{
          'folderId': folderId,
        });
      }
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.scan.success', <String, Object?>{
          'folderId': folderId,
        });
      }
    } catch (error) {
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.scan.error', <String, Object?>{
          'folderId': folderId,
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  Future<void> setFolderPaused({
    required String folderId,
    required bool paused,
  }) async {
    if (!supported) return;
    try {
      if (Platform.isWindows) {
        await WindowsSyncthingTransport.instance.setFolderPaused(
          folderId: folderId,
          paused: paused,
        );
      } else {
        await _channel.invokeMethod<void>('setFolderPaused', <String, dynamic>{
          'folderId': folderId,
          'paused': paused,
        });
      }
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.pause.success', <String, Object?>{
          'folderId': folderId,
          'paused': paused,
        });
      }
    } catch (error) {
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.pause.error', <String, Object?>{
          'folderId': folderId,
          'paused': paused,
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  Future<bool> rebuildWindowsProfilePreservingIdentity() async {
    if (!Platform.isWindows) return false;
    await SyncJoinDiagnostics.record('bridge.profileRebuild.begin');
    try {
      await WindowsSyncthingTransport.instance.rebuildProfilePreservingIdentity();
      await SyncJoinDiagnostics.record('bridge.profileRebuild.success');
      return true;
    } catch (error) {
      await SyncJoinDiagnostics.record('bridge.profileRebuild.error', <String, Object?>{
        'error': error.toString(),
      });
      rethrow;
    }
  }

  Future<void> removeFolderById(String folderId) async {
    if (!supported) return;
    try {
      if (Platform.isWindows) {
        await WindowsSyncthingTransport.instance.removeFolder(folderId);
      } else {
        await _channel.invokeMethod<void>('removeFolder', <String, dynamic>{
          'folderId': folderId,
        });
      }
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.remove.success', <String, Object?>{
          'folderId': folderId,
        });
      }
    } catch (error) {
      if (_isJoinDiagnosticFolder(folderId)) {
        await SyncJoinDiagnostics.record('bridge.remove.error', <String, Object?>{
          'folderId': folderId,
          'error': error.toString(),
        });
      }
      rethrow;
    }
  }

  String folderIdForAccount(String accountId) {
    final safe = requireValidAccountId(accountId);
    return 'artist-workbench-$safe';
  }

  Future<bool> prepare({
    required String accountId,
    required String folderPath,
    bool force = false,
  }) {
    return prepareFolder(
      folderId: folderIdForAccount(accountId),
      label: '画师工作台',
      folderPath: folderPath,
      force: force,
    );
  }

  Future<EmbeddedSyncthingStatus> status({required String accountId}) {
    return statusFolder(folderIdForAccount(accountId));
  }

  Future<void> pairDevice({
    required String accountId,
    required String deviceId,
    required String name,
  }) {
    return pairFolder(
      folderId: folderIdForAccount(accountId),
      deviceId: deviceId,
      name: name,
    );
  }

  Future<void> unshareDevice({
    required String accountId,
    required String deviceId,
  }) {
    return unshareFolderDevice(
      folderId: folderIdForAccount(accountId),
      deviceId: deviceId,
    );
  }

  Future<void> removeAccountFolder({required String accountId}) {
    return removeFolderById(folderIdForAccount(accountId));
  }

  Future<void> requestScan({required String accountId}) {
    return requestScanFolder(folderIdForAccount(accountId));
  }

  Future<void> setAccountFolderPaused({
    required String accountId,
    required bool paused,
  }) {
    return setFolderPaused(
      folderId: folderIdForAccount(accountId),
      paused: paused,
    );
  }

  Future<void> stop({required String accountId}) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.stop(
        folderId: folderIdForAccount(accountId),
      );
      return;
    }
    await _channel.invokeMethod<void>('stop');
  }

  String pairingPayload({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String appDeviceId,
    required String devicePlatform,
  }) {
    return jsonEncode(<String, dynamic>{
      'kind': 'artist-workbench-sync',
      'version': 1,
      'accountId': accountId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'appDeviceId': appDeviceId,
      'devicePlatform': devicePlatform,
    });
  }

  ({
    String deviceId,
    String deviceName,
    String appDeviceId,
    String devicePlatform,
  })
  parsePairingPayload(String source, {required String accountId}) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['kind'] != 'artist-workbench-sync' ||
        decoded['version'] != 1) {
      throw const FormatException('这不是画师工作台的设备同步二维码。');
    }
    if (decoded['accountId'] != accountId) {
      throw const FormatException('两台设备登录的不是同一个账号。');
    }

    final deviceId = decoded['deviceId'];
    final appDeviceId = decoded['appDeviceId'];
    final deviceName = decoded['deviceName'];
    final devicePlatform = decoded['devicePlatform'];
    if (deviceId is! String || deviceId.trim().length < 20) {
      throw const FormatException('同步设备 ID 无效。');
    }
    if (appDeviceId is! String || appDeviceId.trim().isEmpty) {
      throw const FormatException('配对码缺少设备身份。');
    }
    if (deviceName is! String || deviceName.trim().isEmpty) {
      throw const FormatException('配对码缺少设备名称。');
    }
    if (devicePlatform is! String || devicePlatform.trim().isEmpty) {
      throw const FormatException('配对码缺少设备平台。');
    }

    return (
      deviceId: deviceId.trim(),
      deviceName: deviceName.trim(),
      appDeviceId: appDeviceId.trim(),
      devicePlatform: devicePlatform.trim(),
    );
  }
}

bool _isJoinDiagnosticFolder(String folderId) {
  return folderId.startsWith('artist-workbench-bootstrap-');
}

Map<String, Object?> _statusDiagnosticFields(
  String folderId,
  EmbeddedSyncthingStatus status,
) {
  return <String, Object?>{
    'folderId': folderId,
    'available': status.available,
    'running': status.running,
    'localDeviceId': status.deviceId,
    'syncthingVersion': status.version,
    'configuredDevices': status.configuredDevices,
    'connectedDeviceIds': status.connectedDeviceIds,
    'folderState': status.folderState,
    'remoteFolderStates': status.remoteFolderStates,
    'folderErrors': status.folderErrors,
    'progress': status.syncProgress,
    'error': status.error,
  };
}
