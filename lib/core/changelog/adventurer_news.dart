import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';

/// Each feature is recorded once, against the FIRST build where it ships.
/// Keep historical entries when publishing later builds: skipping versions
/// must produce the union of their features.
class AdventurerNewsEntry {
  const AdventurerNewsEntry({
    required this.introducedBuild,
    required this.title,
    required this.description,
  });

  final int introducedBuild;
  final String title;
  final String description;
}

/// Append a block when its feature ships; don't rewrite older entries.
/// Version 107 is the first build intended to contain this dialog.
const adventurerNewsCatalog = <AdventurerNewsEntry>[
  AdventurerNewsEntry(
    introducedBuild: 106,
    title: '截图识别批量导入',
    description: '支持从米画师和画加的排单截图识别订单，导入前可以逐项核对、补填字段并排除重复记录。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 107,
    title: '冒险者新见闻',
    description: '更新后首次进入公会，会自动汇总你上次使用版本以来的新功能；跨版本升级也不会漏掉中间的见闻。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 108,
    title: '新见闻阅读优化',
    description: '把跨版本新增内容整合成一份连续的更新说明，阅读更清爽，不再按版本分成多张卡片。',
  ),
];

List<AdventurerNewsEntry> newsBetweenBuilds(
  int previousBuild,
  int currentBuild, {
  List<AdventurerNewsEntry> catalog = adventurerNewsCatalog,
}) {
  if (currentBuild <= previousBuild) return const [];
  final found = catalog
      .where((entry) =>
          entry.introducedBuild > previousBuild &&
          entry.introducedBuild <= currentBuild)
      .toList()
    ..sort((a, b) => a.introducedBuild.compareTo(b.introducedBuild));
  return List.unmodifiable(found);
}

class AdventurerNewsNotice {
  const AdventurerNewsNotice({
    required this.previousBuild,
    required this.currentBuild,
    required this.entries,
  });

  final int previousBuild;
  final int currentBuild;
  final List<AdventurerNewsEntry> entries;
}

/// Local INSTALLATION-level acknowledgement (NOT account data / sync data).
/// Sharing the same account on Android and Windows must not suppress a popup
/// on the other device. Switching local accounts must not show it twice.
class AdventurerNewsStore {
  const AdventurerNewsStore();

  static const _fileName = 'adventurer-news-last-seen-build-v1.txt';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<int> installedBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<int?> _readLastSeen() async {
    final file = await _file();
    if (!await file.exists()) return null;
    // Corrupt files must not accidentally mark a newer version as read.
    final value = int.tryParse((await file.readAsString()).trim());
    return value != null && value >= 0 ? value : null;
  }

  Future<void> _writeLastSeen(int build) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await atomicWriteString(file, build.toString());
  }

  /// Called once on startup after account discovery but before the app can
  /// create its first account. A clean install has no update to announce.
  ///
  /// Before this feature existed, app versions had no last-seen record. For
  /// legacy installations we conservatively start from build 105, the last
  /// baseline before the changelog feature. Exact pre-feature installed
  /// build numbers cannot be recovered retroactively.
  Future<void> initialize({required bool hasExistingAccounts}) async {
    if (await _readLastSeen() != null) return;
    final initialBuild = hasExistingAccounts
        ? 105
        : await installedBuild();
    await _writeLastSeen(initialBuild);
  }

  Future<AdventurerNewsNotice?> pending() async {
    final currentBuild = await installedBuild();
    final previousBuild = await _readLastSeen();
    if (previousBuild == null || currentBuild <= previousBuild) return null;
    return AdventurerNewsNotice(
      previousBuild: previousBuild,
      currentBuild: currentBuild,
      entries: newsBetweenBuilds(previousBuild, currentBuild),
    );
  }

  /// Only called when the user presses the acknowledgement button, not when
  /// the dialog is opened. A crash / terminated app retries next launch.
  Future<void> acknowledge(int currentBuild) async {
    final previousBuild = await _readLastSeen();
    if (previousBuild != null && previousBuild >= currentBuild) return;
    await _writeLastSeen(currentBuild);
  }
}
