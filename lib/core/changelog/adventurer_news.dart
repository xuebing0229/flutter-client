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
    description: '截图识别稳定性进一步提升，并优化米画师进度归属、重复截图默认保留信息更完整版本、画加成品平台与卡片解析；旧的识别异常退出记录也不会再反复打扰导入。',
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
    description: '专注记录支持长按单条删除，时间范围筛选的“从/到”边界更符合直觉，并修复未结束专注在恢复时误用同步时间作为结束时间的问题。参考图新增附加功能开关，关闭只隐藏入口、不删除已有图片，成品也支持多张参考图查看、编辑、备份与双端同步。设备同步在其他设备离线时不再长期悬挂 99% 进度提示。Windows 截图识别也进行了稳定性升级，并与手机继续共用同一套截图解析与导入规则。',
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
    description: '修复快速切换前后台时旧任务可能再次中断设备同步、单次售卖时间与节点预设并发编辑的回归问题；画加截图识别不再把“已实名/未实名”这类账号状态当作单主姓名，也会从与姓名粘连的识别结果中剔除状态文字。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 142,
    title: '内测回归继续清理',
    description: '继续对照审计前功能修复回归：排单和成品在处理同步同字段冲突时，选择同步版本只替换真正冲突的字段，不再误丢本机其它编辑；应用更新会重新获取最新测试版，并加强 Android 下载完成后的系统安装页面唤起。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 143,
    title: '桌宠素材保护修复',
    description: '修复电脑端更新或重启后可能误删桌宠预设图片的问题。桌宠不再根据配置自动猜测并清理“旧图片”；只有你明确执行删除预设或移除图片时，才会记录并清理对应的本机素材文件。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 145,
    title: '新设备加入状态修复',
    description: '修复首次扫码加入新设备时，两台设备其实已经建立同步连接却仍被误判为“等待原设备确认超时”的问题。加入页现在会识别真实连接状态，确认成功后直接显示已连接与账号传输进度；连接建立后也不会再被固定五分钟超时错误中断。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 146,
    title: 'UI 质感：毛玻璃与液态玻璃',
    description: '设置的外观区域新增“UI质感”，可在经典、毛玻璃、液态玻璃三种模式间切换。玻璃模式沿用当前主题色与深浅色，通过背景模糊、半透明表面和轻量高光作用于导航、抽屉、设置面板与排单/成品卡片；经典模式保持原界面。该选择会随账号设置一起备份与双端同步。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 147,
    title: 'UI 质感重新打磨',
    description: '重新整理毛玻璃与液态玻璃的使用范围：排单、成品与设置等内容卡片恢复清晰不透明，毛玻璃仅保留在确实有背景层的导航和浮层；液态玻璃在 Android 与 Windows 改为平台自适应质感，不再用渐变高光假装折射。经典模式保持不变。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 148,
    title: '十二种 UI 风格',
    description: '外观里的“UI质感”升级为“UI风格”，新增浮雕、极简、粗边、几何、复古浅色、复古深色、荧光、拼贴、黑白、黏土和玻璃，共十二种风格可选。每种风格会同时改变卡片、按钮、输入框、导航、弹窗、进度与背景等共享组件，并继续使用你当前选择的 UI 主题色；经典风格保持原版界面。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 149,
    title: 'UI 风格质感重做',
    description: '按示范文档中的原始组件效果重新制作 UI 风格：浮雕补回内凹明暗层，粗边恢复硬边与硬阴影，复古深色加入扫描线、网格与暗角，荧光加入点阵和发光层，拼贴改用示范中的浅色反设计版本，黏土加强厚圆角和偏移阴影，玻璃改为水滴边框、多层高光和真实背景模糊。主题色继续作为主强调色，经典界面保持不变。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 150,
    title: 'UI 风格明暗与组件统一修复',
    description: 'UI风格不再擅自切换浅色或深色：除“复古浅色 / 复古深色”外，其余风格都跟随当前明暗模式，浅色玻璃恢复乳白清透效果。修复搜索栏内外双重边框、业务卡片左侧无意义竖线，以及账号、专注、设备同步等页面仍残留固定白色硬矩形的问题。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 151,
    title: '测试版更新检查修复',
    description: '检查更新会优先读取最新发布信息，避免刚发布的新测试版短暂被误判成旧版本；Android 与 Windows 都保留备用检查方式。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 152,
    title: 'UI 风格按参考稿重新对齐',
    description: '重新按提供的界面参考逐项校准风格。玻璃取消组件内部的大块气泡高光，改回低透明玻璃底、细边、轻量背景色场和真实模糊；搜索框按浮雕、粗边、几何、复古、荧光、拼贴、黑白、黏土与玻璃分别使用参考中的圆角、边框、底色和内凹或发光关系，不再套统一外壳。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 153,
    title: 'UI 风格清晰度与搜索框修复',
    description: '修复搜索框圆角外壳里又出现矩形内框的问题，改为每种非经典风格只保留一层完整搜索表面；玻璃取消全局文字阴影和额外乳白高光，输入与按钮按参考降低背景模糊强度；荧光取消整页雾化和全局文字发光，恢复清晰的点阵、扫描线与局部霓虹强调。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 154,
    title: '自定义 UI 配色',
    description: 'UI主题色新增自定义调色。基础模式只选主主题色即可自动生成浅色和深色配色；高级模式可分别调整主色、辅助强调色、背景、卡片、次级表面、主文字、说明文字与边框颜色，并通过实时预览确认效果。自定义方案可以命名、保存、编辑、复制、删除和一键切换；还可生成带配色预览与二维码的分享图片、导出 .agtheme 配色文件或复制分享码。其他用户可以直接扫码、从相册选择分享图、导入文件或粘贴分享码，并在确认预览后保存使用；导入不会改变对方当前的 UI 风格。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 155,
    title: '配色编辑更顺手',
    description: '预设主题色名称改得更简洁直观；高级自定义调色中，深色配色新增“一键套用浅色配色”，会完整复制浅色模式的 8 项颜色，复制后仍可继续单独调整深色模式。自定义主题方案会进入完整备份与设备同步；完整备份还补齐截图导入重复检测历史，以及桌宠预设、A/B 美术、气泡图片、位置和缩放等本机自定义内容，恢复后不会丢失这些配置。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 156,
    title: '新设备加入与主题恢复修复',
    description: '修复旧版本留下无效自定义主题记录时可能把整个本地数据误判为读取失败的问题，找不到主题时只回退到原版，不再影响排单和成品数据；同时修复新设备已经连接原设备后账号数据仍长期不传输的问题，连接过程会自动重试，并在异常卡住时给出明确提示。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 157,
    title: 'Windows 卸载流程完善',
    description: 'Windows 卸载时会先关闭冒险者公会、桌宠和设备同步，再明确询问是否保留本机个人数据；选择彻底删除会清理账号、排单、成品、同步记录、桌宠素材、截图导入记录和设置。更新缓存只清理应用自己的缓存，用户导出的备份和图片不会被碰。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 158,
    title: 'Windows 新设备加入修复',
    description: '修复 Windows 新设备在生成回应码之前可能卡住的问题。新版会更可靠地处理旧版残留的同步任务与启动异常，首次使用等待更充分，失败时也会给出更明确的提示。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 159,
    title: '首次加入握手修复',
    description: '修复原电脑已登录、新手机首次加入时可能出现“设备已连接但账号数据始终不传”的问题。首次加入会确认连接真正准备完成后再开始传输，并在账号数据送达、正式同步建立、最终确认完成后结束加入流程；遇到异常会直接提示当前卡点，不再一直转圈。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 161,
    title: '完整备份导出修复',
    description: '修复旧账号升级新版 UI 风格后，历史设置残留可能导致完整备份失败的问题。新版会自动整理旧设置，并从同一份稳定的数据状态生成备份。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 162,
    title: 'Windows 同步通道迁移修复',
    description: '修复旧版 Windows 升级后可能继续受旧同步任务影响，导致设备看似已连接却反复修复、工作数据迟迟不同步的问题。升级后会保留原有设备关系，并自动完成兼容迁移。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 163,
    title: '设备同步卡住修复',
    description: '修复设备已经连接但同步仍长期停在 0% 的问题。现在会自动检查并恢复异常连接，在进度长时间不变化时主动重试；同步页也会明确区分“正在修复连接”和正常数据传输。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 164,
    title: 'Windows 同步初始化修复',
    description: '修复 Windows 新设备加入时可能长期停在准备阶段的问题。新版会在连接异常时及时停止等待并自动处理旧任务残留，避免不同安装版本互相影响，同时保留卡住后的自动恢复。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 165,
    title: 'Windows 数据包选择修复',
    description: '修复 Windows 在加入已有账号或导入备份时，明明选中了备份文件却仍可能提示文件不存在的问题。现在会先确认文件真实可用后再读取。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 166,
    title: '设备解绑传播修复',
    description: '修复设备从本机解绑后，其他设备的“使用中设备”仍可能长期保留旧设备的问题。即使其他设备当时不在线，解绑状态也会保留并在之后重新上线时继续同步，直到各设备都收到更新。退出登录逻辑保持不变。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 167,
    title: '关于与开源致谢',
    description: '设置新增“关于冒险者公会”，可查看当前版本以及项目使用的开源组件与许可证信息；补充 Syncthing 与 Windows 桌宠所使用 VPet-Simulator.Core 的来源和致谢说明。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 170,
    title: '重复设备记录修复',
    description: '同一台电脑或手机重复加入账号时，会识别为同一台设备，不再每加入一次就新增一条“使用中设备”。已经产生的同机重复记录也会在设备再次上线后自动合并，并从其他设备列表中清理。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 171,
    title: '设备身份去重继续修复',
    description: '修复部分旧设备升级后仍可能被误认为新设备的问题。新版会为每次安装保留稳定的设备身份，并自动兼容合并历史重复记录，之后再次加入不会重复新增设备。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 172,
    title: '桌宠与导入记录加入账号同步',
    description: '桌宠预设、A/B 图片、气泡图片、位置缩放和文字等设置现在保存在账号同步工作区，手机即使不显示桌宠也会作为同步中转；电脑重装后重新加入账号可以恢复桌宠资料。截图识别的已导入记录也改为设备间合并同步，避免换机后重复导入。完整备份在手机端同样会带上已同步的桌宠素材。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 173,
    title: '退出账号时关闭桌宠',
    description: '修复退出登录、返回账号选择或设备被远程解绑后，独立桌宠进程仍可能继续留在桌面的问题。离开账号前会先写入关闭状态并停止桌宠宿主，避免旧账号桌宠残留。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 174,
    title: '新设备加入与设备去重修复',
    description: '修复同名同平台的新设备可能被误认成旧设备，以及已解绑设备重新加入时连接可能被旧记录干扰的问题。新版会更准确地区分设备，并保护重新加入过程直到同步完成；账号页也不再展示内部已解绑记录数量。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 175,
    title: '新设备加入改为原子绑定',
    description: '新设备加入时会先确认设备身份，原设备确认回应码后再建立正式同步关系；新设备登录时会继续使用同一身份。这样可以避免“已连接但持续修复、旧设备看不到新设备、功能开关没同步完整”等半连接状态。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 176,
    title: '卡片与添加设备界面整理',
    description: '排单卡片视图改为同一行卡片等高，减少内容多少不同造成的参差感；添加设备页把“复制设备码”移到第一步二维码正下方，并移除底部重复入口，扫码和复制两种方式放在一起。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 178,
    title: '排单卡片字段对齐',
    description: '卡片视图不再只统一外框高度，而是给图名、单主等固定信息区预留一致行高，让同一排卡片的对应字段横向对齐；自定义标签改到独立一行，优先显示能放下的标签，剩余标签再用省略号表示，不再把唯一可见标签直接压成“#…”。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 179,
    title: '排单卡片改为按行自适应对齐',
    description: '图名、单主等字段不再写死两行或固定高度，而是按当前这一排卡片里实际占用最多的行数动态对齐；如果这一排都只占一行就只保留一行，另一排需要两三行时再随该排增长。卡片总高度随本排内容自适应，列表视图的图名也移到平台信息下一行并完整换行显示。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 182,
    title: '电池优化设置修复',
    description: '修复截稿提醒里的电池优化入口只打开系统通用列表、导致当前 App 即使反复调整也可能一直显示受限制的问题。Android 现在会直接请求将当前安装的冒险者公会加入系统电池优化豁免，返回 App 后自动重新读取状态；厂商自己的后台运行与省电设置说明继续保留。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 183,
    title: '网页版设备同步支持',
    description: '网页版现在可以和 Android、Windows 在设备同时打开时自动同步排单、成品、节点、设置与参考图，并继续支持完整备份用于手动恢复。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 185,
    title: '总概览、加价预设与小票',
    description: '排单新增可自由调节卡片大小的总概览视图，会按屏幕宽度自动排成合适列数；排单和成品共用新的加价预设，可组合倍率、百分比和固定金额并按记录保存快照，补款可自行选择是否参与倍率和百分比加价。排单与成品详情都可直接生成仿真小票，默认白底黑字，也能导入自定义背景和调整字体颜色；统计页同时新增本月待收入与年度收入。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 191,
    title: '重装后重新加入设备修复',
    description: '修复手机卸载重装或旧设备重新加入账号时，设备已经连上却仍无法完成账号同步的问题。原设备会在整个首次绑定期间持续确认连接状态；新设备也会显示更准确的“正在连接、账号已收到、等待正式绑定”等阶段。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 192,
    title: '新设备回应码显示修复',
    description: '修复两台设备刚建立连接时就误判“原设备已确认”，导致新设备的回应二维码提前消失的问题。新版会一直保留回应二维码，直到原设备真正确认并开始传输账号数据。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 193,
    title: '电脑确认回应码卡死修复',
    description: '修复 Windows 原设备收到新设备回应码后，确认页面可能长时间无响应、手机仍停在等待授权的问题。回应码会先完成确认，后续连接准备改为独立重试，单次同步异常不再卡住确认页面。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 195,
    title: '卸载后重新加入设备修复',
    description: '恢复此前已验证的新设备加入流程。解绑设备时新增“已卸载/丢失”处理：对已经无法再上线确认的旧安装，可明确结束等待并停止旧设备同步；此前已经解绑但未确认的旧设备，也可在“添加设备”页清理残留后重新加入。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 196,
    title: '临时账号目录卡死修复',
    description: '修复设备已经连接但账号加入仍长期卡住时，自动恢复可能只是重复无效重试的问题。新版会重新建立本次临时连接关系，同时不影响正式账号数据和原有设备身份。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 197,
    title: 'Windows 设备同步自愈',
    description: '当新设备加入后仍持续卡住，且普通恢复无效时，Windows 原设备会保留现有设备身份，只重建必要的同步状态后重新建立本次连接。账号、排单、成品、桌宠与截图识别数据不会删除；若恢复过程异常会自动回滚。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 198,
    title: '回应码确认前状态修复',
    description: '修复新设备尚未把回应码交回原设备时，就因为连接提前建立而错误进入自动恢复的问题。新设备现在只等待原设备确认回应码，不会在授权前自行修改连接状态；真正的连接建立与恢复会在确认之后执行。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 200,
    title: '设备加入诊断版',
    description: '为排查重装后新设备加入长期卡住的问题，本版恢复此前已验证的加入流程，并新增只读同步诊断。原设备和新设备都可以复制本次加入的详细状态，用于定位连接、授权和数据传输卡在哪一步；诊断不会删除账号或业务数据。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 201,
    title: 'Android 新设备加入后台切换修复',
    description: '修复手机首次加入账号时，为了把回应码交给电脑而短暂切到后台后，加入流程可能被意外中断的问题。已有同步任务不会重复启动；如果后台运行被系统停止，会保留本次加入状态并等待 App 回到前台后继续。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 202,
    title: '截图识别结构化回归修复',
    description: '修复新版米画师详情页在截图识别漏掉小标题或截稿行时被误拆成多条记录的问题，不再把“已全额支付、上传稿件、验收节点、创作节点、工作板”等界面文案当作图名；保留新版工作板、节点文字和总额识别能力。添加设备页同时会把与当前安装身份一致的解绑残留标记为“本机旧安装”。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 203,
    title: '截图导入类型误选保护',
    description: '排单与成品继续共用同一套截图识别流程，并会在解析前检查页面类型。成品导入遇到明确的米画师/画加排单详情页时会提示切换到排单导入；排单导入遇到明确的成品橱窗页时也会提示切换。用户仍可选择继续当前类型，且成品识别不再把“已全额支付、验收节点、上传稿件”等排单界面文案当作成品标题。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 204,
    title: '成品总概览与小票预设分享',
    description: '成品新增与排单一致的列表、卡片、总概览三视图，总概览只显示平台、图名、售卖方式与售出数量，并与排单共用总概览网格逻辑；统计页月度收入标题与已收入/待收入排版统一；小票标题区只显示平台，并支持把字体颜色与自定义背景一起封装进分享图片，在样式预设中从原图导入恢复。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 205,
    title: '网页版与三端共用逻辑继续对齐',
    description: '排单与成品的三种视图、总概览列数与排序设置在手机、电脑和网页版保持一致；截图识别的排单/成品类型切换提示也统一。小票预设背景在三端共用同一套数据，避免网页版与客户端表现不一致。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 206,
    title: '小票中心与单主年度小票',
    description: '左侧栏新增统一“生成小票”中心：可按排单或成品生成单张小票，并按归档状态、时间和关键字筛选；也可按年份搜索单主，汇总其已归档的排单与成品业务，列出图名、平台、每单金额和全年总额。小票新增透明底 PNG 导出；成品每次售出可选记录单主，历史售出记录也能补填。原“节点预设”和“加价预设”合并为“节点＆加价预设”入口。',
  ),
  AdventurerNewsEntry(
    introducedBuild: 211,
    title: '快速上手引导与小票恢复完善',
    description: '新增可重复播放的快速上手引导，会直接在真实界面上高亮“新增排单”、搜索、排序/视图和菜单入口，手机、电脑与网页版保持一致。小票“恢复默认”现在会同时恢复样式和已经编辑过的文字内容、字号，不再只恢复抬头或外观。',
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
