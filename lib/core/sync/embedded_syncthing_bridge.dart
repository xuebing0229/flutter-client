import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../account/account_models.dart';
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
    if (Platform.isWindows) {
      return WindowsSyncthingTransport.instance.prepare(
        folderId: folderId,
        label: label,
        folderPath: folderPath,
        force: force,
      );
    }
    await _channel.invokeMapMethod<Object?, Object?>('ensureStarted');
    await _channel.invokeMethod<void>('configureFolder', <String, dynamic>{
      'folderId': folderId,
      'label': label,
      'path': folderPath,
    });
    return true;
  }

  Future<EmbeddedSyncthingStatus> statusFolder(String folderId) async {
    if (!supported) {
      return const EmbeddedSyncthingStatus(
        available: false,
        running: false,
        error: '当前平台暂未接入内置同步核心',
      );
    }
    try {
      if (Platform.isWindows) {
        return EmbeddedSyncthingStatus.fromMap(
          await WindowsSyncthingTransport.instance.status(folderId),
        );
      }
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'status',
        <String, dynamic>{'folderId': folderId},
      );
      if (raw == null) {
        throw StateError('同步核心没有返回状态。');
      }
      return EmbeddedSyncthingStatus.fromMap(raw);
    } on PlatformException catch (error) {
      return EmbeddedSyncthingStatus(
        available: false,
        running: false,
        error: error.message ?? error.code,
      );
    }
  }

  Future<void> pairFolder({
    required String folderId,
    required String deviceId,
    required String name,
  }) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.pairDevice(
        folderId: folderId,
        deviceId: deviceId,
        name: name,
      );
      return;
    }
    await _channel.invokeMethod<void>('pairDevice', <String, dynamic>{
      'folderId': folderId,
      'deviceId': deviceId.trim(),
      'name': name.trim(),
    });
  }

  Future<void> unshareFolderDevice({
    required String folderId,
    required String deviceId,
  }) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.unshareDevice(
        folderId: folderId,
        deviceId: deviceId,
      );
      return;
    }
    await _channel.invokeMethod<void>('unshareDevice', <String, dynamic>{
      'folderId': folderId,
      'deviceId': deviceId.trim(),
    });
  }

  Future<void> requestScanFolder(String folderId) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.requestScan(folderId);
      return;
    }
    await _channel.invokeMethod<void>('requestScan', <String, dynamic>{
      'folderId': folderId,
    });
  }

  Future<void> setFolderPaused({
    required String folderId,
    required bool paused,
  }) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.setFolderPaused(
        folderId: folderId,
        paused: paused,
      );
      return;
    }
    await _channel.invokeMethod<void>('setFolderPaused', <String, dynamic>{
      'folderId': folderId,
      'paused': paused,
    });
  }

  Future<void> removeFolderById(String folderId) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await WindowsSyncthingTransport.instance.removeFolder(folderId);
      return;
    }
    await _channel.invokeMethod<void>('removeFolder', <String, dynamic>{
      'folderId': folderId,
    });
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
