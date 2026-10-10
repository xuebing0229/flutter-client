import 'package:flutter/services.dart';

import 'beta_update_installer.dart';

class AndroidBetaUpdateInstaller implements BetaUpdateInstaller {
  const AndroidBetaUpdateInstaller();

  static const MethodChannel _channel = MethodChannel('app.beta_update');

  @override
  Future<Map<String, dynamic>> fetchLatestManifest() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'fetchLatestManifest',
    );

    if (raw == null) {
      throw StateError('Native update check returned no manifest.');
    }

    return raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  @override
  Future<String> downloadAndInstall({
    required Uri uri,
    required String fileName,
    UpdateDownloadProgressCallback? onProgress,
    UpdateDownloadPauseCallback? shouldPause,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'downloadAndInstall',
      <String, Object?>{
        'url': uri.toString(),
        'fileName': fileName,
      },
    );
    if (result == null) {
      throw StateError('Native update installer returned no status.');
    }
    return result;
  }
}
