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
  AdventurerNewsEntry(
    introducedBuild: 132,
    title: '竖排气泡排版修复',
    description: '修复桌宠侧边竖排气泡文字高低不齐、数字和标点错位的问题：改为固定字格逐字排版，两列等宽等距；当文字较长或可用空间不足时会整体等比缩小，不再依赖手工换行或空格拼排。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 133,
    title: '专注、参考图与 Windows 截图识别升级',
    description: '专注记录支持长按单条删除，时间范围筛选的“从/到”边界更符合直觉，并修复未结束专注在恢复时误用同步时间作为结束时间的问题。参考图新增附加功能开关，关闭只隐藏入口、不删除已有图片，成品也支持多张参考图查看、编辑、备份与双端同步。设备同步在其他设备离线时不再长期悬挂 99% 进度提示。Windows 截图识别改用 PaddleOCR 官方 C++ + Paddle Inference + PP-OCRv6 Small 离线链路，与手机继续共用同一套截图解析与导入规则。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 134,
    title: '桌宠文字泡与组件位置优化',
    description: '文字泡改为按内容自动撑开，短句不再占用过大的固定气泡；横向与竖向共用同一文字大小设置，竖排也会按实际字数自适应高度和列数。桌宠页面新增组件位置预览，可分别拖动横向文字泡、竖向文字泡和计时板相对桌宠的位置，并按桌宠预设保存。修复放大文字泡时布局最小值超过最大值导致桌宠宿主闪退的问题，并加强计时板缩放和配置热更新的异常保护。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 134,
    title: '公会视觉体验焕新',
    description: '统一精致西幻卡片、弹窗与轻量菜单的细边及柔和层次；页面背景更细腻，搜索框聚焦更清晰，按钮、进度条和标签继续保持简洁。保留全部原版图标、排版与操作，支持所有主题色和深浅色模式。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 134,
    title: '桌宠气泡新装扮与截图后卡住修复',
    description: '电脑桌宠文字泡可切换说话与思考两种样式，思考气泡采用圆点尾巴而不是对话框三角尖；每组桌宠预设可选配透明 PNG 图片放在文字泡内。修复使用快捷截图软件后桌宠可能一直停在按键 B 图的问题：改为实时检测按键与鼠标状态，释放按键后可自动回到 A 图，不再依赖容易漏掉松键事件的全局钩子。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 135,
    title: '内测前稳定性完善',
    description: '全面修复双端同步、完整备份恢复、截图批量导入、订单与成品并发操作、专注计时、Windows 桌宠和自动更新中的边界问题；同时关闭 Android 系统云备份，并加强激活与发码数据、安装包签名和更新文件完整性校验，减少异常中断、重复写入和跨设备状态互相覆盖。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 136,
    title: '更新与激活管理完善',
    description: '修复 Android 测试版 APK 下载到 100% 后安装动作丢失的问题；发码器新增拉取覆盖更新。激活与发码请求在 VPN 路由无法访问授权服务器时会仅针对授权域名尝试本地网络直连；发码器在打开、回到前台及服务端操作后自动刷新共享账本，并用记录版本冲突保护避免多管理员同时操作时静默覆盖。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 137,
    title: '发码器旧记录接入修复',
    description: '管理员首次接入共享账本时，旧发码器本地已有的 AW1/AW2 记录如果已在服务器存在相同编号、账号身份或激活码，会直接以服务器账本为准并跳过重复迁移，不再因为历史记录冲突导致管理员连接失败；未连接服务器时也允许直接删除当前设备上的旧版记录，不会误删服务器历史。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 138,
    title: '桌宠稳定性与交互修复',
    description: '修复思考气泡实际显示成大椭圆、调整气泡或计时板位置时人物跟着乱跑、气泡透明 PNG 导入后不显示的问题；A/B 图片恢复为按键或鼠标按下立即切到 B、松开立即回 A。进一步减少文字更新和 A/B 切换时的重复布局与图片重建，限制桌宠预览和宿主图片解码内存与缓存，并隔离配置热更新、计时刷新、拖动保存和宿主进程异常，降低大图、连续输入或快速调节设置时的闪退概率。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 139,
    title: '桌宠气泡图片与闪退继续修复',
    description: '文字泡内容改为“文字 / 图片”二选一：图片模式只显示导入的透明 PNG，不再和订单文字或自定义文字叠加；气泡 PNG 改为直接复用桌宠 A/B 图片同一套 WPF 图片解码、缓存和显示链路，只是把图片控件限制在气泡内部。图片模式新增独立“图片大小”滑条（50%～200%），按原始宽高比缩放，气泡随图片自动撑开；文字模式仍显示“文字大小”。桌宠图片删除与替换不再在当前界面仍可能使用文件时立即物理删除，改为下次启动前安全清理；同时把桌宠配置写入串行化，减少快速修改设置时的文件竞争与随机闪退。继续收紧高风险边界：异常/超大图片解码失败时直接放弃该图而不是带崩宿主，降低原生图片缓存上限，并防止快速开关桌宠时旧同步请求反向覆盖新状态；预览图和桌宠设置读取异常也会留在页面内处理，损坏或半解析配置也不会再触发旧图片清理。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 141,
    title: '同步与截图导入回归修复',
    description: '修复快速切换前后台时旧任务可能再次关闭设备同步核心、单次售卖时间与节点预设并发编辑的回归问题；画加截图识别不再把“已实名/未实名”这类账号状态当作单主姓名，也会从与姓名粘连的 OCR 结果中剔除状态文字。',
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
