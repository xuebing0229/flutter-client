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
    introducedBuild: 123,
    title: '设备同步体验升级',
    description: '手机和电脑在前台打开时会自动连接并同步，不再需要两边手动点同步；实际传输时会显示实时百分比和进度条，完成后自动消失。Android 同步不再长期占用通知栏，并增强了同步通道掉线后的自动恢复。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 124,
    title: '截图识别导入优化',
    description: '截图识别改用稳定的官方 PP-OCRv6 链路，并优化米画师进度归属、重复截图默认保留信息更完整版本、画加成品平台与卡片解析；旧的 OCR 异常退出记录也不会再反复打扰导入。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 125,
    title: '设备同步恢复与前台自动连接',
    description: '修复 124 测试版误带旧同步后台的问题；手机和电脑打开公会后会自动连接并同步，传输时显示真实百分比，Android 不再常驻“正在同步设备数据”通知。',
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
