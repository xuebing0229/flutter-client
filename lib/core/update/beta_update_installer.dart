/// Platform-specific Beta update bridge.
///
/// Each supported platform fetches the shared public Beta metadata and handles
/// its own download/install handoff.
typedef UpdateDownloadProgressCallback = void Function(
  int receivedBytes,
  int? totalBytes,
);

typedef UpdateDownloadPauseCallback = bool Function();

abstract interface class BetaUpdateInstaller {
  Future<Map<String, dynamic>> fetchLatestManifest();

  Future<int?> resumableBytes({required String fileName});

  Future<String> downloadAndInstall({
    required Uri uri,
    required String fileName,
    UpdateDownloadProgressCallback? onProgress,
    UpdateDownloadPauseCallback? shouldPause,
  });
}
