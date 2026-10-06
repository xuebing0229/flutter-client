import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';

class WindowsSyncthingTransport {
  WindowsSyncthingTransport._();

  static final WindowsSyncthingTransport instance =
      WindowsSyncthingTransport._();

  static const int _apiPort = 8384;
  static const String _stateFileName = 'embedded-syncthing-windows.json';

  Future<void>? _starting;
  Future<void> _stateTail = Future<void>.value();

  Future<bool> isAutoStartEnabled(String folderId) async {
    final state = await _readState();
    final autoStart = state['autoStart'];
    if (autoStart is! Map) return false;
    return autoStart[folderId] == true;
  }

  Future<bool> prepare({
    required String folderId,
    required String label,
    required String folderPath,
    bool force = false,
  }) async {
    if (!Platform.isWindows) return false;
    if (!force && !await isAutoStartEnabled(folderId)) return false;

    await _ensureReady();
    await _configureFolder(
      folderId: folderId,
      label: label,
      folderPath: folderPath,
    );
    if (force) {
      await _updateState<void>((state) {
        final autoStart = <String, dynamic>{..._asMap(state['autoStart'])}
          ..[folderId] = true;
        state['autoStart'] = autoStart;
      });
    }
    return true;
  }

  Future<Map<Object?, Object?>> status(String folderId) async {
    if (!Platform.isWindows) {
      return <Object?, Object?>{
        'available': false,
        'running': false,
        'error': '当前平台暂未接入 Windows 同步核心',
      };
    }

    final binary = _binaryFile();
    if (!await binary.exists()) {
      return <Object?, Object?>{
        'available': false,
        'running': false,
        'error': '安装包中缺少 Windows 同步核心',
      };
    }

    final apiKey = await _ensureApiKey();
    if (!await _ping(apiKey)) {
      return <Object?, Object?>{'available': true, 'running': false};
    }

    try {
      final system = _jsonMap(
        await _request('GET', '/rest/system/status', apiKey: apiKey),
      );
      final version = _jsonMap(
        await _request('GET', '/rest/system/version', apiKey: apiKey),
      );
      final configured = _jsonList(
        await _request('GET', '/rest/config/devices', apiKey: apiKey),
      );
      final folders = _jsonList(
        await _request('GET', '/rest/config/folders', apiKey: apiKey),
      );
      final connectionRoot = _jsonMap(
        await _request('GET', '/rest/system/connections', apiKey: apiKey),
      );
      final connections = _asMap(connectionRoot['connections']);

      final folderDeviceIds = <String>{};
      for (final item in folders) {
        final folder = _asMap(item);
        if (folder['id']?.toString() != folderId) continue;
        final devices = folder['devices'];
        if (devices is List) {
          for (final device in devices) {
            final id = _asMap(device)['deviceID']?.toString() ?? '';
            if (id.isNotEmpty) folderDeviceIds.add(id);
          }
        }
        break;
      }

      final configuredDevices = <Map<String, dynamic>>[];
      for (final item in configured) {
        final map = _asMap(item);
        if (map.isEmpty) continue;
        final id = map['deviceID']?.toString() ?? '';
        if (!folderDeviceIds.contains(id)) continue;
        configuredDevices.add(<String, dynamic>{
          'deviceId': id,
          'name': map['name']?.toString() ?? '',
        });
      }

      final connectedDeviceIds = <String>[];
      for (final entry in connections.entries) {
        if (!folderDeviceIds.contains(entry.key)) continue;
        final map = _asMap(entry.value);
        if (map['connected'] == true) {
          connectedDeviceIds.add(entry.key);
        }
      }

      String? folderState;
      Map<String, dynamic>? syncProgress;
      if (folderId.isNotEmpty) {
        final encodedFolder = Uri.encodeQueryComponent(folderId);
        final candidates = <Map<String, dynamic>>[];
        final body = await _requestOptional(
          'GET',
          '/rest/db/status?folder=$encodedFolder',
          apiKey: apiKey,
        );
        if (body != null) {
          final map = _jsonMap(body);
          final raw = map['state']?.toString();
          if (raw != null && raw.isNotEmpty) folderState = raw;

          final globalBytes = (map['globalBytes'] as num?)?.toInt() ?? 0;
          final needBytes = (map['needBytes'] as num?)?.toInt() ?? 0;
          final globalItems =
              (map['globalTotalItems'] as num?)?.toInt() ??
              (map['globalFiles'] as num?)?.toInt() ??
              0;
          final needItems =
              (map['needTotalItems'] as num?)?.toInt() ??
              (map['needFiles'] as num?)?.toInt() ??
              0;
          final completion = globalBytes > 0
              ? ((globalBytes - needBytes) / globalBytes * 100)
                    .clamp(0, 100)
                    .toDouble()
              : globalItems > 0
              ? ((globalItems - needItems) / globalItems * 100)
                    .clamp(0, 100)
                    .toDouble()
              : 100.0;
          candidates.add(<String, dynamic>{
            'deviceId': '',
            'deviceName': '本机',
            'direction': 'receiving',
            'completion': completion,
            'globalBytes': globalBytes,
            'needBytes': needBytes,
            'globalItems': globalItems,
            'needItems': needItems,
          });
        }

        for (final remoteId in connectedDeviceIds) {
          final completionBody = await _requestOptional(
            'GET',
            '/rest/db/completion?folder=$encodedFolder'
                '&device=${Uri.encodeQueryComponent(remoteId)}',
            apiKey: apiKey,
          );
          if (completionBody == null) continue;
          final completionMap = _jsonMap(completionBody);
          final rawCompletion = completionMap['completion'];
          if (rawCompletion is! num) continue;

          var remoteName = remoteId.length > 7
              ? remoteId.substring(0, 7)
              : remoteId;
          for (final device in configuredDevices) {
            if (device['deviceId'] == remoteId) {
              final configuredName = device['name']?.toString().trim() ?? '';
              if (configuredName.isNotEmpty) remoteName = configuredName;
              break;
            }
          }

          candidates.add(<String, dynamic>{
            'deviceId': remoteId,
            'deviceName': remoteName,
            'direction': 'sending',
            'completion': rawCompletion.toDouble().clamp(0, 100),
            'globalBytes':
                (completionMap['globalBytes'] as num?)?.toInt() ?? 0,
            'needBytes': (completionMap['needBytes'] as num?)?.toInt() ?? 0,
            'globalItems':
                (completionMap['globalItems'] as num?)?.toInt() ?? 0,
            'needItems': (completionMap['needItems'] as num?)?.toInt() ?? 0,
          });
        }

        if (candidates.isNotEmpty) {
          candidates.sort(
            (left, right) => (left['completion'] as double).compareTo(
              right['completion'] as double,
            ),
          );
          syncProgress = candidates.first;
        }
      }

      return <Object?, Object?>{
        'available': true,
        'running': true,
        'deviceId': system['myID']?.toString(),
        'version': version['version']?.toString(),
        'connectedDeviceIds': connectedDeviceIds,
        'configuredDevices': configuredDevices,
        'folderState': folderState,
        'syncProgress': syncProgress,
      };
    } catch (error) {
      return <Object?, Object?>{
        'available': true,
        'running': true,
        'error': '读取 Windows 同步状态失败：$error',
      };
    }
  }

  Future<void> pairDevice({
    required String folderId,
    required String deviceId,
    required String name,
  }) async {
    await _ensureReady();
    final apiKey = await _ensureApiKey();
    final normalizedId = deviceId.trim();
    if (normalizedId.length < 20) {
      throw const FormatException('同步设备 ID 格式无效');
    }

    final devices = _jsonList(
      await _request('GET', '/rest/config/devices', apiKey: apiKey),
    );
    Map<String, dynamic>? existingDevice;
    for (final item in devices) {
      final map = _asMap(item);
      if (map['deviceID'] == normalizedId) {
        existingDevice = Map<String, dynamic>.from(map);
        break;
      }
    }

    if (existingDevice == null) {
      await _request(
        'POST',
        '/rest/config/devices',
        apiKey: apiKey,
        body: jsonEncode(<String, dynamic>{
          'deviceID': normalizedId,
          'name': name.trim().isEmpty
              ? normalizedId.substring(0, 7)
              : name.trim(),
          'addresses': <String>['dynamic'],
        }),
      );
    } else if (name.trim().isNotEmpty) {
      existingDevice['name'] = name.trim();
      await _request(
        'PUT',
        '/rest/config/devices/${Uri.encodeComponent(normalizedId)}',
        apiKey: apiKey,
        body: jsonEncode(existingDevice),
      );
    }

    final folders = _jsonList(
      await _request('GET', '/rest/config/folders', apiKey: apiKey),
    );
    Map<String, dynamic>? folder;
    for (final item in folders) {
      final map = _asMap(item);
      if (map['id'] == folderId) {
        folder = Map<String, dynamic>.from(map);
        break;
      }
    }
    if (folder == null) {
      throw StateError('同步目录尚未准备好');
    }

    final sharedDevices = <dynamic>[
      if (folder['devices'] is List) ...folder['devices'] as List,
    ];
    final alreadyShared = sharedDevices.any(
      (item) => _asMap(item)['deviceID'] == normalizedId,
    );
    if (!alreadyShared) {
      sharedDevices.add(<String, dynamic>{'deviceID': normalizedId});
      folder['devices'] = sharedDevices;
      await _request(
        'PUT',
        '/rest/config/folders/${Uri.encodeComponent(folderId)}',
        apiKey: apiKey,
        body: jsonEncode(folder),
      );
    }

    await _updateState<void>((state) {
      final autoStart = <String, dynamic>{
        ..._asMap(state['autoStart']),
        folderId: true,
      };
      state['autoStart'] = autoStart;
    });
  }

  Future<void> unshareDevice({
    required String folderId,
    required String deviceId,
  }) async {
    await _ensureReady();
    final apiKey = await _ensureApiKey();
    final normalizedId = deviceId.trim();
    if (normalizedId.isEmpty) return;

    final folders = _jsonList(
      await _request('GET', '/rest/config/folders', apiKey: apiKey),
    );
    Map<String, dynamic>? folder;
    for (final item in folders) {
      final map = _asMap(item);
      if (map['id'] == folderId) {
        folder = Map<String, dynamic>.from(map);
        break;
      }
    }
    if (folder == null) return;

    final devices = <dynamic>[
      if (folder['devices'] is List) ...folder['devices'] as List,
    ];
    final filtered = <dynamic>[
      for (final item in devices)
        if (_asMap(item)['deviceID'] != normalizedId) item,
    ];
    if (filtered.length == devices.length) return;

    folder['devices'] = filtered;
    await _request(
      'PUT',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(folder),
    );
  }

  Future<void> removeFolder(String folderId) async {
    await _ensureReady();
    final apiKey = await _ensureApiKey();
    final folders = _jsonList(
      await _request('GET', '/rest/config/folders', apiKey: apiKey),
    );
    final exists = folders.any(
      (item) => _asMap(item)['id']?.toString() == folderId,
    );
    if (exists) {
      await _request(
        'DELETE',
        '/rest/config/folders/${Uri.encodeComponent(folderId)}',
        apiKey: apiKey,
      );
    }

    await _updateState<void>((state) {
      final autoStart = <String, dynamic>{..._asMap(state['autoStart'])}
        ..remove(folderId);
      state['autoStart'] = autoStart;
    });
  }

  Future<void> requestScan(String folderId) async {
    await _ensureReady();
    final apiKey = await _ensureApiKey();
    await _request(
      'POST',
      '/rest/db/scan?folder=${Uri.encodeQueryComponent(folderId)}',
      apiKey: apiKey,
    );
  }

  Future<void> setFolderPaused({
    required String folderId,
    required bool paused,
  }) async {
    await _ensureReady();
    final apiKey = await _ensureApiKey();
    final folders = _jsonList(
      await _request('GET', '/rest/config/folders', apiKey: apiKey),
    );
    Map<String, dynamic>? folder;
    for (final item in folders) {
      final map = _asMap(item);
      if (map['id']?.toString() == folderId) {
        folder = Map<String, dynamic>.from(map);
        break;
      }
    }
    if (folder == null) return;

    if (folder['paused'] == paused) return;
    folder['paused'] = paused;
    await _request(
      'PUT',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(folder),
    );
  }

  Future<void> stop({required String folderId}) async {
    final apiKey = await _ensureApiKey();
    if (await _ping(apiKey)) {
      await _request('POST', '/rest/system/shutdown', apiKey: apiKey);
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!await _ping(apiKey)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    await _updateState<void>((state) {
      final autoStart = <String, dynamic>{..._asMap(state['autoStart'])}
        ..[folderId] = false;
      state['autoStart'] = autoStart;
    });
  }

  /// Stops the detached embedded process without changing any account's
  /// auto-start preference. The Windows self-updater calls this immediately
  /// before handing the installation directory to its replacement script.
  Future<void> shutdown() async {
    if (!Platform.isWindows) return;

    try {
      final apiKey = await _ensureApiKey();
      if (!await _ping(apiKey)) return;
      await _request(
        'POST',
        '/rest/system/shutdown',
        apiKey: apiKey,
      );
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!await _ping(apiKey)) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {
      // The update script performs a path-specific process check as a
      // fallback. A transient API failure must not prevent an update attempt.
    }
  }

  Future<void> _configureFolder({
    required String folderId,
    required String label,
    required String folderPath,
  }) async {
    final apiKey = await _ensureApiKey();
    final folders = _jsonList(
      await _request('GET', '/rest/config/folders', apiKey: apiKey),
    );
    Map<String, dynamic>? existing;
    for (final item in folders) {
      final map = _asMap(item);
      if (map['id'] == folderId) {
        existing = Map<String, dynamic>.from(map);
        break;
      }
    }

    if (existing == null) {
      await _request(
        'POST',
        '/rest/config/folders',
        apiKey: apiKey,
        body: jsonEncode(<String, dynamic>{
          'id': folderId,
          'label': label,
          'path': folderPath,
          'type': 'sendreceive',
          'devices': <dynamic>[],
        }),
      );
      return;
    }

    existing
      ..['label'] = label
      ..['path'] = folderPath
      ..['type'] = 'sendreceive';

    await _request(
      'PUT',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(existing),
    );
  }

  Future<void> _ensureReady() async {
    final binary = _binaryFile();
    if (!await binary.exists()) {
      throw StateError('安装包中缺少 Windows 同步核心');
    }

    final apiKey = await _ensureApiKey();
    if (await _ping(apiKey)) return;

    // Treat process creation + API readiness as one startup transaction.
    // A fresh Syncthing profile can take noticeably longer on Windows while
    // it creates its identity/configuration and is scanned by security tools.
    // All concurrent callers must wait for the same startup instead of
    // launching additional detached processes during that cold-start window.
    final existingStart = _starting;
    if (existingStart != null) {
      await existingStart;
      return;
    }

    final start = _startAndWaitUntilReady(binary, apiKey);
    _starting = start;
    try {
      await start;
    } finally {
      if (identical(_starting, start)) _starting = null;
    }
  }

  Future<void> _startAndWaitUntilReady(File binary, String apiKey) async {
    // Another caller/process may have finished starting between the first ping
    // and taking the startup lock.
    if (await _ping(apiKey)) return;

    await _startProcess(binary, apiKey);

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await _ping(apiKey)) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    // Avoid failing on the exact boundary if the API became ready while the
    // final delay was completing.
    if (await _ping(apiKey)) return;
    throw StateError('Windows 同步核心启动超时，请稍后重试');
  }

  Future<void> _startProcess(File binary, String apiKey) async {
    final support = await getApplicationSupportDirectory();
    final configDir = Directory(
      '${support.path}${Platform.pathSeparator}syncthing-config',
    );
    await configDir.create(recursive: true);

    await Process.start(
      binary.path,
      <String>[
        '--home',
        configDir.path,
        '--gui-address',
        '127.0.0.1:$_apiPort',
        '--gui-apikey',
        apiKey,
        '--no-browser',
        '--no-restart',
        '--log-max-old-files=0',
      ],
      mode: ProcessStartMode.detached,
      environment: <String, String>{
        ...Platform.environment,
        'STNORESTART': '1',
        'STNODEFAULTFOLDER': '1',
      },
    );
  }

  Future<bool> _ping(String apiKey) async {
    try {
      await _request('GET', '/rest/system/ping', apiKey: apiKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _requestOptional(
    String method,
    String path, {
    required String apiKey,
  }) async {
    try {
      return await _request(method, path, apiKey: apiKey);
    } catch (_) {
      return null;
    }
  }

  Future<String> _request(
    String method,
    String path, {
    required String apiKey,
    String? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$_apiPort$path'),
      );
      request.headers
        ..set('X-API-Key', apiKey)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      } else if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
        request.headers.contentType = ContentType.json;
      }

      final response = await request.close().timeout(
        const Duration(seconds: 7),
      );
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Syncthing API HTTP ${response.statusCode}'
          '${responseBody.isEmpty ? '' : ': $responseBody'}',
        );
      }
      return responseBody;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _ensureApiKey() async {
    final state = await _readState();
    final existing = state['apiKey'];
    if (existing is String && existing.isNotEmpty) return existing;

    return _updateState<String>((latest) {
      final racedExisting = latest['apiKey'];
      if (racedExisting is String && racedExisting.isNotEmpty) {
        return racedExisting;
      }

      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final generated = base64UrlEncode(bytes).replaceAll('=', '');
      latest['apiKey'] = generated;
      return generated;
    });
  }

  File _binaryFile() {
    final executableDir = File(Platform.resolvedExecutable).parent;
    return File(
      '${executableDir.path}${Platform.pathSeparator}'
      'syncthing${Platform.pathSeparator}syncthing.exe',
    );
  }

  Future<File> _stateFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}$_stateFileName');
  }

  Future<Map<String, dynamic>> _readState() async {
    await _stateTail;
    return _readStateUnsafe();
  }

  Future<Map<String, dynamic>> _readStateUnsafe() async {
    final file = await _stateFile();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return _asMap(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<T> _updateState<T>(T Function(Map<String, dynamic> state) update) {
    final operation = _stateTail.then<T>((_) async {
      final state = await _readStateUnsafe();
      final result = update(state);
      await _writeStateUnsafe(state);
      return result;
    });
    _stateTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _writeStateUnsafe(Map<String, dynamic> state) async {
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    await atomicWriteString(file, jsonEncode(state));
  }

  Map<String, dynamic> _jsonMap(String source) {
    return _asMap(jsonDecode(source));
  }

  List<dynamic> _jsonList(String source) {
    final decoded = jsonDecode(source);
    return decoded is List ? decoded : const <dynamic>[];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }
}
