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
  AdventurerNewsEntry(
    introducedBuild: 126,
    title: 'Windows 桌宠',
    description: '电脑端附加功能新增桌宠：可以保存并一键切换多组自定义 A/B 图片预设，A 为平时状态、B 为按键操作状态；文字框可显示当前在画订单或自定义内容。桌宠美术资源和预设只保存在本机。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 127,
    title: '专注计时',
    description: '手机和电脑新增专注计时，可锁定一个排单或使用“自由专注”；专注历史会作为独立记录在设备间同步，关联排单仍存在时可确认后跳转查看。Windows 桌宠右上角会同步显示本次专注计时，并与头顶气泡分开占位。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 129,
    title: '桌宠与专注整合完善',
    description: '桌宠与专注合并为同一个左侧板块：电脑开启桌宠时显示 A/B 桌宠设置与专注，关闭桌宠或在手机端则保留专注；恢复 A/B 固定画布定位与对齐、桌宠和气泡大小、头顶/侧边气泡、当前在画订单选择与主题跟随。专注历史支持单次记录与按排单合并，按开始时间/时长、累计时长/次数/最近专注时间排序，并保留时间筛选与范围清理。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 130,
    title: '桌宠布局与专注体验完善',
    description: '桌宠 A/B 定位支持进入编辑模式后拖动与缩放，取消不会误保存；重做横向/竖向气泡与计时板布局，气泡按人物显示框居中并贴近边界，竖向文字改为竖排，计时板位于人物右侧上半部且可独立调大小。修复桌宠主题色与浅深色跟随慢一拍的问题。专注新增独立附加功能开关，关闭后隐藏专注区域与桌宠计时板；计时与历史时间统一显示到秒，单次记录按开始、结束、时长三行展示。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 131,
    title: '桌宠定位与主题跟随修复',
    description: '进一步修复桌宠主题同步：不再从旧页面主题状态取色，直接按当前主题模式、色板和 Windows 实际明暗模式生成气泡与计时板颜色。人物定位编辑移除误导性的内层参考框，并将“居中”和“重置”拆分：居中只调整上下左右位置，重置可恢复图片刚导入时保存的位置与大小。按订单合并的专注记录继续保留右侧展示，并将累计时长标注明确、放大加粗。',
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
