import 'dart:async';
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
  static const Duration _gracefulShutdownTimeout = Duration(seconds: 10);
  static const Duration _shutdownPollInterval = Duration(milliseconds: 100);
  static const Duration _startupNoticeTimeout = Duration(seconds: 60);

  Future<void>? _starting;
  Future<int>? _resolvingPort;
  int? _resolvedApiPort;
  bool _runtimePolicyApplied = false;
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

      final allConfiguredDevices = <Map<String, dynamic>>[];
      for (final item in configured) {
        final map = _asMap(item);
        if (map.isEmpty) continue;
        final id = map['deviceID']?.toString() ?? '';
        if (id.isEmpty) continue;
        allConfiguredDevices.add(<String, dynamic>{
          'deviceId': id,
          'name': map['name']?.toString() ?? '',
        });
      }

      final allConnectedDeviceIds = <String>[];
      for (final entry in connections.entries) {
        final map = _asMap(entry.value);
        if (map['connected'] == true) {
          allConnectedDeviceIds.add(entry.key);
        }
      }

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
        'allConnectedDeviceIds': allConnectedDeviceIds,
        'allConfiguredDevices': allConfiguredDevices,
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
      final payload = _jsonMap(
        await _request(
          'GET',
          '/rest/config/defaults/device',
          apiKey: apiKey,
        ),
      )
        ..['deviceID'] = normalizedId
        ..['name'] = name.trim().isEmpty
            ? normalizedId.substring(0, 7)
            : name.trim()
        ..['addresses'] = <String>['dynamic'];
      await _request(
        'POST',
        '/rest/config/devices',
        apiKey: apiKey,
        body: jsonEncode(payload),
      );
    } else if (name.trim().isNotEmpty &&
        existingDevice['name']?.toString().trim() != name.trim()) {
      await _request(
        'PATCH',
        '/rest/config/devices/${Uri.encodeComponent(normalizedId)}',
        apiKey: apiKey,
        body: jsonEncode(<String, dynamic>{'name': name.trim()}),
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
      await _request(
        'PATCH',
        '/rest/config/folders/${Uri.encodeComponent(folderId)}',
        apiKey: apiKey,
        body: jsonEncode(<String, dynamic>{'devices': sharedDevices}),
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

    await _request(
      'PATCH',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(<String, dynamic>{'devices': filtered}),
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
    await _request(
      'PATCH',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(<String, dynamic>{'paused': paused}),
    );
  }

  Future<void> stop({required String folderId}) async {
    final apiKey = await _ensureApiKey();
    final stopped = await _shutdownGracefully(apiKey);
    if (!stopped) {
      await _forceTerminateStaleBundledProcesses();
    }
    _runtimePolicyApplied = false;

    await _updateState<void>((state) {
      final autoStart = <String, dynamic>{..._asMap(state['autoStart'])}
        ..[folderId] = false;
      state['autoStart'] = autoStart;
    });
  }

  Future<void> rebuildProfilePreservingIdentity() async {
    if (!Platform.isWindows) return;

    await _ensureReady();
    final apiKey = await _ensureApiKey();
    final beforeSystem = _jsonMap(
      await _request('GET', '/rest/system/status', apiKey: apiKey),
    );
    final beforeDeviceId = beforeSystem['myID']?.toString().trim() ?? '';
    if (beforeDeviceId.isEmpty) {
      throw StateError('重建同步核心前无法读取当前设备身份。');
    }

    final support = await getApplicationSupportDirectory();
    final configDir = Directory(
      '${support.path}${Platform.pathSeparator}syncthing-config',
    );
    final certFile = File(
      '${configDir.path}${Platform.pathSeparator}cert.pem',
    );
    final keyFile = File(
      '${configDir.path}${Platform.pathSeparator}key.pem',
    );
    if (!await certFile.exists() || !await keyFile.exists()) {
      throw StateError('同步核心身份文件不完整，已取消自动重建。');
    }

    final backupDir = Directory(
      '${configDir.path}.repair-${DateTime.now().microsecondsSinceEpoch}',
    );

    await shutdown();
    await _forceTerminateStaleBundledProcesses();
    var movedOriginal = false;
    try {
      await configDir.rename(backupDir.path);
      movedOriginal = true;
      await configDir.create(recursive: true);
      await File(
        '${backupDir.path}${Platform.pathSeparator}cert.pem',
      ).copy(
        '${configDir.path}${Platform.pathSeparator}cert.pem',
      );
      await File(
        '${backupDir.path}${Platform.pathSeparator}key.pem',
      ).copy(
        '${configDir.path}${Platform.pathSeparator}key.pem',
      );

      _starting = null;
      await _ensureReady();

      final afterApiKey = await _ensureApiKey();
      final afterSystem = _jsonMap(
        await _request('GET', '/rest/system/status', apiKey: afterApiKey),
      );
      final afterDeviceId = afterSystem['myID']?.toString().trim() ?? '';
      if (afterDeviceId != beforeDeviceId) {
        throw StateError('同步核心重建后设备身份发生变化，已回滚。');
      }

      try {
        await backupDir.delete(recursive: true);
      } catch (_) {}
    } catch (error) {
      try {
        await shutdown();
      } catch (_) {}
      await _forceTerminateStaleBundledProcesses();
      if (movedOriginal && await backupDir.exists()) {
        try {
          if (await configDir.exists()) {
            await configDir.delete(recursive: true);
          }
        } catch (_) {}
        try {
          await backupDir.rename(configDir.path);
          _starting = null;
          await _ensureReady();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Stops the embedded process without changing any account's auto-start
  /// preference. Syncthing's Windows guidance gives graceful shutdown up to
  /// ten seconds; forced termination is only a last-resort fallback.
  Future<void> shutdown() async {
    if (!Platform.isWindows) return;

    try {
      final apiKey = await _ensureApiKey();
      final stopped = await _shutdownGracefully(apiKey);
      if (!stopped) {
        await _forceTerminateStaleBundledProcesses();
      }
    } catch (_) {
      await _forceTerminateStaleBundledProcesses();
    } finally {
      _runtimePolicyApplied = false;
    }
  }

  Future<bool> _shutdownGracefully(String apiKey) async {
    final apiWasReady = await _ping(apiKey);
    final processWasRunning = await _profileProcessesRunning();
    if (!apiWasReady && !processWasRunning) return true;

    if (apiWasReady) {
      try {
        await _request(
          'POST',
          '/rest/system/shutdown',
          apiKey: apiKey,
        );
      } catch (_) {
        // The API can disappear while the shutdown response is in flight.
        // Process/API disappearance below is the authoritative completion.
      }
    }

    final deadline = DateTime.now().add(_gracefulShutdownTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final processRunning = await _profileProcessesRunning();
      if (!processRunning && !await _ping(apiKey)) return true;
      await Future<void>.delayed(_shutdownPollInterval);
    }

    return !await _profileProcessesRunning() && !await _ping(apiKey);
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
      final payload = _jsonMap(
        await _request(
          'GET',
          '/rest/config/defaults/folder',
          apiKey: apiKey,
        ),
      )
        ..['id'] = folderId
        ..['label'] = label
        ..['path'] = folderPath
        ..['type'] = 'sendreceive'
        ..['devices'] = <dynamic>[];
      await _request(
        'POST',
        '/rest/config/folders',
        apiKey: apiKey,
        body: jsonEncode(payload),
      );
      return;
    }

    final unchanged =
        existing['label']?.toString() == label &&
        existing['path']?.toString() == folderPath &&
        existing['type']?.toString() == 'sendreceive';
    if (unchanged) return;

    await _request(
      'PATCH',
      '/rest/config/folders/${Uri.encodeComponent(folderId)}',
      apiKey: apiKey,
      body: jsonEncode(<String, dynamic>{
        'label': label,
        'path': folderPath,
        'type': 'sendreceive',
      }),
    );
  }

  Future<void> _ensureReady() async {
    final binary = _binaryFile();
    if (!await binary.exists()) {
      throw StateError('安装包中缺少 Windows 同步核心');
    }

    final apiKey = await _ensureApiKey();
    if (await _ping(apiKey)) {
      await _applyIntegrationPolicy(apiKey);
      return;
    }

    final existingStart = _starting;
    if (existingStart != null) {
      await _waitForStartup(existingStart);
      await _applyIntegrationPolicy(apiKey);
      return;
    }

    final start = _startAndWaitUntilReady(binary, apiKey);
    _starting = start;
    unawaited(
      start.then<void>(
        (_) {
          if (identical(_starting, start)) _starting = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_starting, start)) _starting = null;
        },
      ),
    );

    await _waitForStartup(start);
    await _applyIntegrationPolicy(apiKey);
  }

  Future<void> _waitForStartup(Future<void> startup) async {
    try {
      await startup.timeout(_startupNoticeTimeout);
    } on TimeoutException {
      throw TimeoutException(
        'Windows 同步核心启动时间较长，进程仍在继续启动；应用会自动继续等待。',
      );
    }
  }

  Future<void> _startAndWaitUntilReady(File binary, String apiKey) async {
    if (await _ping(apiKey)) return;

    var port = await _ensureApiPort();
    await _recoverStaleBundledProcesses(binary, apiKey, port);

    if (!await _portIsAvailable(port)) {
      port = await _rotateApiPort();
    }

    final logFile = await _startupLogFile();
    try {
      if (await logFile.exists()) {
        await logFile.writeAsString('', flush: true);
      }
    } catch (_) {}

    _runtimePolicyApplied = false;
    final process = await _startProcess(binary, apiKey, port, logFile);
    int? exitCode;
    Object? exitError;
    unawaited(
      process.exitCode.then<void>(
        (value) => exitCode = value,
        onError: (Object error, StackTrace _) {
          exitError = error;
        },
      ),
    );

    while (true) {
      if (await _pingAt(apiKey, port)) return;
      if (exitError != null) {
        throw StateError('Windows 同步核心进程状态读取失败：$exitError');
      }
      final code = exitCode;
      if (code != null) {
        throw StateError(
          '${await _startupFailureMessage(logFile, port)}（退出码 $code）',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<Process> _startProcess(
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

    final process = await Process.start(
      binary.path,
      <String>[
        '--home',
        configDir.path,
        '--gui-address',
        '127.0.0.1:$port',
        '--gui-apikey',
        apiKey,
        '--no-browser',
        '--no-console',
        '--no-restart',
        '--no-upgrade',
        '--log-file=${logFile.path}',
      ],
      mode: ProcessStartMode.detachedWithStdio,
      environment: Platform.environment,
    ).timeout(_processStartTimeout);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process;
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
        ? 'Windows 同步核心进程已退出，但日志没有给出明确原因。'
        : 'Windows 同步核心启动失败：$tail';
  }

  Future<void> _applyIntegrationPolicy(String apiKey) async {
    if (_runtimePolicyApplied) return;
    await _request(
      'PATCH',
      '/rest/config/options',
      apiKey: apiKey,
      body: jsonEncode(<String, dynamic>{
        'urAccepted': -1,
        'crashReportingEnabled': false,
        'autoUpgradeIntervalH': 0,
      }),
    );
    _runtimePolicyApplied = true;
  }

  Future<void> _recoverStaleBundledProcesses(
    File binary,
    String apiKey,
    int port,
  ) async {
    if (!await _profileProcessesRunning()) return;

    final support = await getApplicationSupportDirectory();
    final configDir = Directory(
      '${support.path}${Platform.pathSeparator}syncthing-config',
    );
    final deadline = DateTime.now().add(_gracefulShutdownTimeout);
    try {
      await Process.run(
        binary.path,
        <String>[
          '--home=${configDir.path}',
          'cli',
          '--gui-address=http://127.0.0.1:$port',
          '--gui-apikey=$apiKey',
          'operations',
          'shutdown',
        ],
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}

    while (DateTime.now().isBefore(deadline)) {
      if (!await _profileProcessesRunning()) return;
      await Future<void>.delayed(_shutdownPollInterval);
    }
    await _forceTerminateStaleBundledProcesses();
  }

  Future<bool> _profileProcessesRunning() async {
    if (!Platform.isWindows) return false;
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
        " } | Select-Object -ExpandProperty ProcessId";
    try {
      final result = await Process.run(
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
      return result.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _forceTerminateStaleBundledProcesses() async {
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
