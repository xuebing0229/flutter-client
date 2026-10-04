/// Platform-specific Beta update bridge.
///
/// Each supported platform fetches the shared public Beta metadata and handles
/// its own download/install handoff.
abstract interface class BetaUpdateInstaller {
  Future<Map<String, dynamic>> fetchLatestManifest();

  Future<String> downloadAndInstall({
    required Uri uri,
    required String fileName,
  });
}
