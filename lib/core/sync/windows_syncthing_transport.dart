import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';

class WindowsSyncthingTransport {
  WindowsSyncthingTransport._();

  static final WindowsSyncthingTransport instance =
      WindowsSyncthingTransport._();

  // 8384 is Syncthing's public default GUI/API port. Older app builds used it
  // directly. New builds must never keep using that legacy channel: if the
  // saved transport still points at 8384, startup migrates the same Syncthing
  // profile to an app-private loopback port. The profile directory is kept, so
  // the Syncthing device identity and paired-folder configuration survive.
  static const int _legacyApiPort = 8384;
  static const String _stateFileName = 'embedded-syncthing-windows.json';
  static const Duration _localApiRequestTimeout = Duration(seconds: 8);
  static const Duration _processStartTimeout = Duration(seconds: 10);

  Future<void>? _starting;
  Future<int>? _resolvingPort;
  int? _resolvedApiPort;
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
      final remoteFolderStates = <String, String>{};
      final folderErrors = <String>[];
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

        final errorBody = await _requestOptional(
          'GET',
          '/rest/folder/errors?folder=$encodedFolder',
          apiKey: apiKey,
        );
        if (errorBody != null) {
          final root = _jsonMap(errorBody);
          final errors = root['errors'];
          if (errors is List) {
            for (final item in errors) {
              final message = _asMap(item)['error']?.toString().trim() ?? '';
              if (message.isNotEmpty) folderErrors.add(message);
            }
          }
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
          final remoteState = completionMap['remoteState']?.toString().trim();
          if (remoteState != null && remoteState.isNotEmpty) {
            remoteFolderStates[remoteId] = remoteState;
          }
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
            'remoteState': remoteState,
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
        'remoteFolderStates': remoteFolderStates,
        'folderErrors': folderErrors,
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
    } else if (name.trim().isNotEmpty &&
        existingDevice['name']?.toString().trim() != name.trim()) {
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
    if (await _ping(apiKey)) return;

    var port = await _ensureApiPort();

    // If a previous app-owned Syncthing survived an update/crash but no
    // longer answers with our current API key, it can keep both the profile
    // lock and the old GUI port. Stop only processes that are demonstrably
    // ours (same bundled exe or same private --home directory).
    await _terminateStaleBundledProcesses();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // Never compete with another service for a GUI/API port. In particular,
    // 8384 is Syncthing's public default and is commonly occupied by a normal
    // user installation. Rotate to a free app-private loopback port instead.
    if (!await _portIsAvailable(port)) {
      port = await _rotateApiPort();
    }

    final logFile = await _startupLogFile();
    try {
      if (await logFile.exists()) {
        await logFile.writeAsString('', flush: true);
      }
    } catch (_) {}

    await _startProcess(binary, apiKey, port, logFile);

    // A fresh Windows profile can be delayed by certificate generation,
    // database setup, or security scanning. Give it room, but no longer hide
    // the real failure behind an undifferentiated timeout.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (await _pingAt(apiKey, port)) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (await _pingAt(apiKey, port)) return;
    throw StateError(await _startupFailureMessage(logFile, port));
  }

  Future<void> _startProcess(
    File binary,
    String apiKey,
    int port,
    File logFile,
  ) async {
    final support = await getApplicationSupportDirectory();
    final configDir = Directory(
      '${support.path}${Platform.pathSeparator}syncthing-config',
    );
    await configDir.create(recursive: true);
    await logFile.parent.create(recursive: true);

    await Process.start(
      binary.path,
      <String>[
        '--home',
        configDir.path,
        '--gui-address',
        '127.0.0.1:$port',
        '--gui-apikey',
        apiKey,
        '--no-browser',
        '--no-restart',
        '--log-file=${logFile.path}',
        '--log-max-old-files=0',
      ],
      mode: ProcessStartMode.detached,
      environment: <String, String>{
        ...Platform.environment,
        'STNORESTART': '1',
        'STNODEFAULTFOLDER': '1',
      },
    ).timeout(_processStartTimeout);
  }

  Future<bool> _ping(String apiKey) async {
    final port = await _ensureApiPort();
    return _pingAt(apiKey, port);
  }

  Future<bool> _pingAt(String apiKey, int port) async {
    try {
      await _requestAt(
        'GET',
        '/rest/system/ping',
        apiKey: apiKey,
        port: port,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _ensureApiPort() async {
    final cached = _resolvedApiPort;
    if (cached != null) return cached;

    final resolving = _resolvingPort;
    if (resolving != null) return resolving;

    final future = _resolveApiPort();
    _resolvingPort = future;
    try {
      return await future;
    } finally {
      if (identical(_resolvingPort, future)) _resolvingPort = null;
    }
  }

  Future<int> _resolveApiPort() async {
    final state = await _readState();
    final saved = state['apiPort'];
    if (saved is int &&
        saved >= 1024 &&
        saved <= 65535 &&
        saved != _legacyApiPort) {
      _resolvedApiPort = saved;
      return saved;
    }

    // Builds before 158 could persist 8384 and keep an old app-owned Syncthing
    // alive there forever. Reusing it bypasses the stale-process cleanup below,
    // so the app can repeatedly repair the old channel instead of bringing up
    // the current private one. Always migrate legacy/unknown state to a fresh
    // private port; _startAndWaitUntilReady then stops only our bundled stale
    // process and restarts the SAME profile on this port.
    return _rotateApiPort();
  }

  Future<int> _rotateApiPort() async {
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final port = socket.port;
    await socket.close();
    await _persistApiPort(port);
    return port;
  }

  Future<void> _persistApiPort(int port) async {
    _resolvedApiPort = port;
    await _updateState<void>((state) {
      state['apiPort'] = port;
    });
  }

  Future<bool> _portIsAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<File> _startupLogFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}syncthing-config'
      '${Platform.pathSeparator}embedded-startup.log',
    );
  }

  Future<String> _startupFailureMessage(File logFile, int port) async {
    String log = '';
    try {
      if (await logFile.exists()) {
        log = await logFile.readAsString();
      }
    } catch (_) {}

    final lower = log.toLowerCase();
    if (lower.contains('address already in use') ||
        lower.contains('bind:') && lower.contains('in use')) {
      return 'Windows 同步核心启动失败：本机端口 $port 被其他程序占用。'
          '请重试，应用会重新选择专用端口。';
    }
    if (lower.contains('already running') ||
        lower.contains('database is locked') ||
        lower.contains('lock') && lower.contains('syncthing')) {
      return 'Windows 同步核心启动失败：检测到旧的同步核心仍占用本机数据目录。'
          '请关闭旧版冒险者公会后重试。';
    }
    if (lower.contains('access is denied') ||
        lower.contains('permission denied')) {
      return 'Windows 同步核心启动失败：系统拒绝了同步核心访问。'
          '请检查安全软件是否拦截了冒险者公会内置的 syncthing.exe。';
    }

    final lines = log
        .split(RegExp(r'[\r\n]+'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final tail = lines.isEmpty ? '' : lines.last.trim();
    return tail.isEmpty
        ? 'Windows 同步核心在 60 秒内没有启动完成。'
            '这次没有检测到端口冲突；请重试，若仍失败可根据同步核心日志继续定位。'
        : 'Windows 同步核心启动失败：$tail';
  }

  Future<void> _terminateStaleBundledProcesses() async {
    if (!Platform.isWindows) return;
    final support = await getApplicationSupportDirectory();
    final configDir = Directory(
      '${support.path}${Platform.pathSeparator}syncthing-config',
    );
    String quote(String value) => value.replaceAll("'", "''");
    final home = quote(configDir.absolute.path);
    final script =
        "\$ErrorActionPreference='SilentlyContinue';"
        "Get-CimInstance Win32_Process -Filter \"Name='syncthing.exe'\" | "
        "Where-Object { "
        "\$_.CommandLine -and "
        "\$_.CommandLine.IndexOf('$home', "
        "[StringComparison]::OrdinalIgnoreCase) -ge 0"
        " } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }";
    try {
      await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Failing to inspect/stop a stale process should not block a normal
      // startup attempt; the startup log will expose a profile-lock failure.
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
    final port = await _ensureApiPort();
    return _requestAt(
      method,
      path,
      apiKey: apiKey,
      port: port,
      body: body,
    );
  }

  Future<String> _requestAt(
    String method,
    String path, {
    required String apiKey,
    required int port,
    String? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      // Keep every localhost REST call bounded as one transaction. Waiting for
      // the response body used to be unbounded, so a half-alive/stale Syncthing
      // process could accept the connection and leave the app spinner waiting
      // forever before the normal 60-second startup diagnostics could run.
      return await (() async {
        final request = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:$port$path'),
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

        final response = await request.close();
        final responseBody = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Syncthing API HTTP ${response.statusCode}'
            '${responseBody.isEmpty ? '' : ': $responseBody'}',
          );
        }
        return responseBody;
      })().timeout(_localApiRequestTimeout);
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
