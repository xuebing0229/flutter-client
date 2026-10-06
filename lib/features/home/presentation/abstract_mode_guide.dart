import 'package:flutter/material.dart';

class _AbstractGuideSection {
  const _AbstractGuideSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}

const _sections = <_AbstractGuideSection>[
  _AbstractGuideSection(
    icon: Icons.dashboard_outlined,
    title: '先认识界面',
    body: '主工作区按排单、成品、日程、统计组织工作。',
    bullets: [
      '手机端从底部或菜单切换板块；桌面端从左侧导航切换。',
      '桌面端展开工具栏后，节点预设、归档、同步、账号与设置会在右侧工作区切换。',
      '排单和成品页右下角的“新增”按钮分别用于创建记录。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.manage_accounts_outlined,
    title: '账号与首次登录',
    body: '账号是本地优先的工作空间身份。',
    bullets: [
      '首次注册需要激活码；注册完成后，日常登录只需要账号名和密码。',
      '账号名、密码和工作数据保存在应用本地，并通过设备同步迁移。',
      '忘记密码时，可在仍登录的设备“账号与设备”里查看或修改凭据。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.playlist_add_check_rounded,
    title: '排单：从接稿到推进',
    body: '一笔排单就是一份从接稿到交付的工作记录。',
    bullets: [
      '新增时填写排单名、平台、稿费、截稿日期、备注、平台手续费、补款/减款和节点。',
      '卡片上的“－/＋”调整当前节点小进度；完成后点“确认节点”进入下一节点。',
      '开启附加功能后，顶部可以搜索或排序；长按卡片可置顶、归档、删除，也可以批量处理。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.account_tree_outlined,
    title: '节点预设：复用常用流程',
    body: '把常用的工作阶段保存下来，新排单可以直接套用。',
    bullets: [
      '打开“节点预设”，新增一套节点并按实际顺序命名。',
      '后续新增排单时选择对应预设，再按这笔稿件的情况调整。',
      '修改后的预设会用于之后新建的排单；已有排单继续使用原来的节点配置。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.image_outlined,
    title: '成品、日程与统计',
    body: '成品适合记录可重复售卖的作品，日程集中查看日期，统计汇总收入。',
    bullets: [
      '新增成品时可填写图名、平台、原始稿价、单次/多次售卖方式和描述。',
      '在成品详情里记录售出；售出记录会出现在日程对应日期。',
      '排单或成稿归档后，相关收入才会进入统计；成品也可以单独归档和恢复。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.archive_outlined,
    title: '归档与快捷操作',
    body: '归档会把记录移出工作列表，并保留在归档页中。',
    bullets: [
      '长按排单或成品可以快速归档；批量归档也可以一次选择多条。',
      '排单归档时可按节点结算，或按实际情况选择完整收入、补款/减款等结算方式。',
      '归档页可以查看并恢复；删除会从本地数据移除，不能从归档页恢复。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.tune_outlined,
    title: '附加功能与截稿提醒',
    body: '“附加功能开关”用于按工作习惯收起不常用入口。',
    bullets: [
      '可以开启搜索、排序、成品、日程、统计和截稿通知提醒；基础字段始终保留。',
      '如您已丢失您的附加功能开关，可回到普通版寻找。',
      '截稿提醒默认在截止前 7 天和 1 天发出本地通知。首次开启时按引导打开通知、精确闹钟和后台运行权限。',
      '提醒异常时，去“设置 → 截稿提醒”查看状态并运行测试提醒。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.sync_alt_rounded,
    title: '设备同步：首次配对',
    body: '同步通过设备到设备的端到端通道进行，可以跨网络连接已配对设备。',
    bullets: [
      '两台设备先登录同一个账号，再从“账号与设备 → 添加设备”开始。',
      '可以扫码、选择二维码图片，或复制粘贴配对码；新设备生成回应二维码/回应码后，还要回到原设备确认。',
      '首次配对时按页面提示保持两边页面打开；显示“首次绑定完成”后，日常同步直接从“设备同步”页进行。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.pause_circle_outline_rounded,
    title: '设备同步：日常控制与冲突',
    body: '“设备同步”页同时显示同步开关、连接状态和冲突处理。',
    bullets: [
      '开关打开时，前台和后台都会自动交换设备数据；手机可能显示持续同步通知，这是后台同步服务的运行状态。',
      '开关关闭时，前台和后台都暂停交换数据，本地编辑会保留；重新打开后再继续同步。',
      '“等待其他设备”表示本机同步核心已经就绪，正在等待已配对设备上线连接。',
      '出现数据冲突时，在同步页逐项选择要保留的设备版本，确认后才会继续合并。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.devices_other_outlined,
    title: '账号与设备管理',
    body: '这里管理账号资料、设备名称和设备授权关系。',
    bullets: [
      '可以修改账号名、密码和头像，也可以给设备改名。',
      '解绑设备会把它从使用中设备移除；在线设备会退出账号，离线设备在下次上线后收到解绑记录。',
      '登录页的“移除本机账号记录”会清理当前设备保存的数据和同步目录，其他设备继续保留各自的数据。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.inventory_2_outlined,
    title: '设置、备份与恢复',
    body: '同步之外，设置页还提供一份可搬运的完整备份。',
    bullets: [
      '“导出完整备份”包含排单、成品、节点预设、账号设备记录、归档状态和稿费数据。',
      '“导入完整备份”会覆盖当前本地数据；导入前确认文件属于当前激活账号，并保留一份最新备份。',
      '外观主题和功能开关也会随完整备份恢复；设备同步仍可在“设备同步”页单独暂停或恢复。',
    ],
  ),
];

Future<void> showAbstractModeGuide(
  BuildContext context, {
  bool forced = false,
}) {
  final size = MediaQuery.sizeOf(context);

  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (dialogContext) {
      return PopScope(
        canPop: !forced,
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 600 ? 16 : 48,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: size.height * .86,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '画师工作台（抽象版）使用教程',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '从接稿、交付到双端同步，按需要查看对应模块。',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!forced)
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    itemCount: _sections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final section = _sections[index];
                      final colors = Theme.of(context).colorScheme;
                      return Material(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: .38,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      section.icon,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${index + 1}. ${section.title}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(section.body),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              for (final bullet in section.bullets) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(bullet)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('签订契约'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
