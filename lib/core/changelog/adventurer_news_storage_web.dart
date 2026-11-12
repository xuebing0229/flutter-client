import '../web/web_platform_bridge.dart';

class AdventurerNewsStorage {
  const AdventurerNewsStorage();

  static const _key = 'adventurers-guild.news.last-seen-build.v1';

  Future<int?> readLastSeen() async {
    final raw = webStorageGet(_key);
    if (raw == null) return null;
    final value = int.tryParse(raw.trim());
    return value != null && value >= 0 ? value : null;
  }

  Future<void> writeLastSeen(int build) async {
    webStorageSet(_key, build.toString());
  }
}
