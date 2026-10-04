import 'package:flutter/material.dart';

class _GuideStep {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

Future<void> _showDetailedGuide(BuildContext context) {
  final size = MediaQuery.sizeOf(context);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
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
                            '画师工作台使用教程',
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
                  itemCount: _detailedGuide.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _DetailedGuideCard(
                      index: index + 1,
                      section: _detailedGuide[index],
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
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

const _detailedGuide = <_GuideSection>[
  _GuideSection(
    icon: Icons.dashboard_outlined,
    title: '先认识界面',
    body: '主工作区按排单、成品、日程、统计组织工作。',
    bullets: [
      '手机端从底部或菜单切换板块；桌面端从左侧导航切换。',
      '桌面端展开工具栏后，节点预设、归档、同步、账号与设置会在右侧工作区切换，不会覆盖主屏。',
      '排单和成品页右下角的“新增”按钮分别用于创建记录。',
    ],
  ),
  _GuideSection(
    icon: Icons.manage_accounts_outlined,
    title: '账号与首次登录',
    body: '账号是本地优先的工作空间身份。',
    bullets: [
      '首次注册需要激活码；注册完成后，日常登录只需要账号名和密码。',
      '账号名、密码和工作数据保存在应用本地，并通过设备同步迁移，不连接账号服务器。',
      '忘记密码时，可在仍登录的设备“账号与设备”里查看或修改凭据。',
    ],
  ),
  _GuideSection(
    icon: Icons.playlist_add_check_rounded,
    title: '排单：从接稿到推进',
    body: '一笔排单就是一份从接稿到交付的工作记录。',
    bullets: [
      '新增时填写排单名、平台、稿费、截稿日期、备注、平台手续费、补款/减款和节点。',
      '卡片上的“－/＋”调整当前节点小进度；完成后点“确认节点”进入下一节点。',
      '开启附加功能后，顶部可以搜索或排序；长按卡片可置顶、归档、删除，也可以批量处理。',
    ],
  ),
  _GuideSection(
    icon: Icons.account_tree_outlined,
    title: '节点预设：复用常用流程',
    body: '把常用的工作阶段保存下来，新排单可以直接套用。',
    bullets: [
      '打开“节点预设”，新增一套节点并按实际顺序命名。',
      '后续新增排单时选择对应预设，再按这笔稿件的情况调整。',
      '预设修改只影响之后如何创建和推进记录，不会回写已经存在的排单。',
    ],
  ),
  _GuideSection(
    icon: Icons.image_outlined,
    title: '成品、日程与统计',
    body: '成品适合记录可重复售卖的作品，日程集中查看日期，统计汇总收入。',
    bullets: [
      '新增成品时可填写图名、平台、原始稿价、单次/多次售卖方式和描述。',
      '在成品详情里记录售出；售出记录会出现在日程对应日期。',
      '排单或成稿归档后，相关收入才会进入统计；成品也可以单独归档和恢复。',
    ],
  ),
  _GuideSection(
    icon: Icons.archive_outlined,
    title: '归档与快捷操作',
    body: '归档是“暂时从工作列表移出”，不是立即删除。',
    bullets: [
      '长按排单或成品可以快速归档；批量归档也可以一次选择多条。',
      '排单归档时可按节点结算，或按实际情况选择完整收入、补款/减款等结算方式。',
      '归档页可以查看并恢复；删除会从本地数据移除，不能从归档页恢复。',
    ],
  ),
  _GuideSection(
    icon: Icons.tune_outlined,
    title: '附加功能与截稿提醒',
    body: '“附加功能开关”用于按工作习惯收起不常用入口。',
    bullets: [
      '可以开启搜索、排序、成品、日程、统计和截稿通知提醒；基础字段始终保留。',
      '截稿提醒默认在截止前 7 天和 1 天发出本地通知。首次开启时按引导打开通知、精确闹钟和后台运行权限。',
      '提醒异常时，去“设置 → 截稿提醒”查看状态和测试提醒，不需要反复清理后台。',
    ],
  ),
  _GuideSection(
    icon: Icons.sync_alt_rounded,
    title: '设备同步：首次配对',
    body: '同步是设备到设备的端到端通道，不依赖云端，也不要求两台设备连同一 Wi-Fi。',
    bullets: [
      '两台设备先登录同一个账号，再从“账号与设备 → 添加设备”开始。',
      '可以扫码、选择二维码图片，或复制粘贴配对码；新设备生成回应二维码/回应码后，还要回到原设备确认。',
      '首次配对时按页面提示保持两边页面打开；显示“首次绑定完成”后，日常同步不需要再次打开添加设备页面。',
    ],
  ),
  _GuideSection(
    icon: Icons.pause_circle_outline_rounded,
    title: '设备同步：日常控制与冲突',
    body: '“设备同步”页同时显示同步开关、连接状态和冲突处理。',
    bullets: [
      '开关打开时，前台和后台都会自动交换设备数据；手机可能显示持续同步通知，这是后台同步服务的运行状态。',
      '开关关闭时，前台和后台都暂停交换数据，本地编辑会保留；重新打开后再继续同步。',
      '“等待其他设备”表示本机同步核心已经就绪，但当前还没有连接上的已配对设备，不代表必须连接同一 Wi-Fi。',
      '出现数据冲突时，在同步页逐项选择要保留的设备版本，确认后才会继续合并。',
    ],
  ),
  _GuideSection(
    icon: Icons.devices_other_outlined,
    title: '账号与设备管理',
    body: '这里管理账号资料、设备名称和设备授权关系。',
    bullets: [
      '可以修改账号名、密码和头像，也可以给设备改名。',
      '解绑设备会把它从使用中设备移除；在线设备会退出账号，离线设备在下次上线后收到解绑记录。',
      '登录页的“移除本机账号记录”只删除当前设备保存的数据和同步目录，不会删除其他设备上的账号或数据。',
    ],
  ),
  _GuideSection(
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

class _GuideSection {
  const _GuideSection({
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

class _DetailedGuideCard extends StatelessWidget {
  const _DetailedGuideCard({
    required this.index,
    required this.section,
  });

  final int index;
  final _GuideSection section;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .38),
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
                  child: Icon(section.icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$index. ${section.title}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
  }
}

Future<void> showFirstRunGuide(
  BuildContext context, {
  bool detailed = false,
}) {
  if (detailed) return _showDetailedGuide(context);

  const steps = <_GuideStep>[
    _GuideStep(
      icon: Icons.add_circle_outline_rounded,
      title: '先新增一笔排单',
      body: '点右下角「新增排单」，填写稿件、平台、稿费、截稿时间和节点。',
    ),
    _GuideStep(
      icon: Icons.account_tree_outlined,
      title: '推进节点',
      body: '卡片上的－/＋调整当前节点小进度；完成后点「确认节点」进入下一节点。',
    ),
    _GuideStep(
      icon: Icons.touch_app_outlined,
      title: '长按有快捷操作',
      body: '长按排单或成品，可以置顶、归档、删除，也可以批量归档或批量删除。',
    ),
    _GuideStep(
      icon: Icons.payments_outlined,
      title: '收入统计',
      body: '成稿归档后计入收入统计；需要更多功能时，可以从左侧菜单打开完整使用教程。',
    ),
  ];

  var index = 0;

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final step = steps[index];
          final isLast = index == steps.length - 1;

          return AlertDialog(
            icon: Icon(step.icon, size: 34),
            title: Text(step.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text(
                  '${index + 1} / ${steps.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('跳过'),
              ),
              if (index > 0)
                TextButton(
                  onPressed: () {
                    setDialogState(() => index -= 1);
                  },
                  child: const Text('上一步'),
                ),
              FilledButton(
                onPressed: () {
                  if (isLast) {
                    Navigator.of(dialogContext).pop();
                  } else {
                    setDialogState(() => index += 1);
                  }
                },
                child: Text(isLast ? '开始使用' : '下一步'),
              ),
            ],
          );
        },
      );
    },
  );
}
