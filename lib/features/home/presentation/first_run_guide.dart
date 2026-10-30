import 'package:flutter/material.dart';

import '../../shared/presentation/spotlight_guide.dart';

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

enum QuickStartGuideDestination {
  orders,
  screenshotImport,
  products,
  schedule,
  statistics,
  presetCenter,
  receiptCenter,
  archive,
  sync,
  account,
  settings,
  pwaInstall,
  featureToggle,
}

class QuickStartGuideActions {
  const QuickStartGuideActions({
    required this.goTo,
    required this.createFirstOrder,
    required this.waitForFirstOrderArchive,
    required this.isAvailable,
    required this.finish,
  });

  final Future<void> Function(QuickStartGuideDestination destination) goTo;
  final Future<String?> Function() createFirstOrder;
  final Future<bool> Function(String orderId) waitForFirstOrderArchive;
  final bool Function(QuickStartGuideDestination destination) isAvailable;
  final Future<void> Function() finish;
}

Future<void> _showDetailedGuide(
  BuildContext context, {
  QuickStartGuideTargets? targets,
  Future<void> Function()? prepareQuickStart,
  QuickStartGuideActions? actions,
}) {
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
                            '从接稿、交付到多设备同步，按需要查看对应模块。',
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
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (targets != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!context.mounted) return;
                          await _showInteractiveQuickStart(
                            context,
                            targets,
                            prepare: prepareQuickStart,
                            actions: actions,
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放快速上手引导'),
                      ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('知道了'),
                    ),
                  ],
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
      '桌面端展开工具栏后，节点预设、归档、同步、账号与设置会在右侧工作区切换。',
      '排单和成品页右下角的“新增”按钮分别用于创建记录。',
    ],
  ),
  _GuideSection(
    icon: Icons.manage_accounts_outlined,
    title: '账号与首次登录',
    body: '账号是本地优先的工作空间身份。',
    bullets: [
      '首次注册需要激活码；注册完成后，日常登录只需要账号名和密码。',
      '账号名、密码和工作数据保存在应用本地，并通过设备同步迁移。',
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
      '修改后的预设会用于之后新建的排单；已有排单继续使用原来的节点配置。',
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
    body: '归档会把记录移出工作列表，并保留在归档页中。',
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
      '提醒异常时，去“设置 → 截稿提醒”查看状态并运行测试提醒。',
    ],
  ),
  _GuideSection(
    icon: Icons.sync_alt_rounded,
    title: '设备同步：首次配对',
    body: '同步通过设备到设备的端到端通道进行，可以跨网络连接已配对设备。',
    bullets: [
      '两台设备先登录同一个账号，再从“账号与设备 → 添加设备”开始。',
      '可以扫码、选择二维码图片，或复制粘贴配对码；新设备生成回应二维码/回应码后，还要回到原设备确认。',
      '首次配对时按页面提示保持两边页面打开；显示“首次绑定完成”后，日常同步直接从“设备同步”页进行。',
    ],
  ),
  _GuideSection(
    icon: Icons.pause_circle_outline_rounded,
    title: '设备同步：日常控制与冲突',
    body: '“设备同步”页同时显示同步开关、连接状态和冲突处理。',
    bullets: [
      '开关打开时，前台和后台都会自动交换设备数据；手机可能显示持续同步通知，这是后台同步服务的运行状态。',
      '开关关闭时，前台和后台都暂停交换数据，本地编辑会保留；重新打开后再继续同步。',
      '“等待其他设备”表示本机已经准备好，正在等待已连接的其他设备上线。',
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
      '登录页的“移除本机账号记录”会清理当前设备保存的数据和同步目录，其他设备继续保留各自的数据。',
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

ShapeBorder _extendedFabGuideShape(BuildContext context) {
  final themed = FloatingActionButtonTheme.of(context).shape;
  if (themed != null) return themed;
  return Theme.of(context).useMaterial3
      ? const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        )
      : const StadiumBorder();
}

ShapeBorder _textButtonGuideShape(BuildContext context) {
  final themed =
      TextButtonTheme.of(context).style?.shape?.resolve(const <WidgetState>{});
  if (themed != null) return themed;
  return Theme.of(context).useMaterial3
      ? const StadiumBorder()
      : const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        );
}

Future<bool> _showVisibleSpotlights(
  BuildContext context,
  List<SpotlightGuideStep> candidates, {
  String finalLabel = '下一步',
}) async {
  if (!context.mounted) return false;
  final steps = candidates
      .where((step) => step.targetKey.currentContext != null)
      .toList(growable: false);
  if (steps.isEmpty) return true;
  return showSpotlightGuide(
    context,
    steps: steps,
    finalLabel: finalLabel,
  );
}

Future<void> _showInteractiveQuickStart(
  BuildContext context,
  QuickStartGuideTargets targets, {
  Future<void> Function()? prepare,
  QuickStartGuideActions? actions,
}) async {
  if (actions == null) {
    await prepare?.call();
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    await showSpotlightGuide(
      context,
      finalLabel: '开始使用',
      steps: [
        SpotlightGuideStep(
          targetKey: targets.addOrderKey,
          icon: Icons.add_circle_outline_rounded,
          title: '先记下第一笔业务',
          body: '从这里新增排单。手动填写适合单笔记录，截图导入适合一次整理多张平台订单截图。',
          targetShape: _extendedFabGuideShape(context),
          targetPadding: 0,
        ),
        SpotlightGuideStep(
          targetKey: targets.searchKey,
          icon: Icons.search_rounded,
          title: '快速找到排单',
          body: '可以搜索图名、单主、平台等内容，右侧展开还能切换搜索范围。',
        ),
        SpotlightGuideStep(
          targetKey: targets.toolbarKey,
          icon: Icons.dashboard_customize_outlined,
          title: '按你的习惯整理工作台',
          body: '这里可以排序和切换列表、卡片、总概览等视图。',
        ),
        SpotlightGuideStep(
          targetKey: targets.menuKey,
          icon: Icons.menu_rounded,
          title: '更多功能都在这里',
          body: '同步、备份、截图导入、小票、节点＆加价预设和设置都可以从菜单进入。',
        ),
      ].where((step) => step.targetKey.currentContext != null).toList(),
    );
    return;
  }

  Future<bool> showSection(
    QuickStartGuideDestination destination,
    List<SpotlightGuideStep> steps,
  ) async {
    if (!actions.isAvailable(destination)) return true;
    await actions.goTo(destination);
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return false;
    return _showVisibleSpotlights(context, steps);
  }

  Future<void> stop() async {
    await actions.finish();
  }

  await actions.goTo(QuickStartGuideDestination.orders);
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;

  final startFirstOrder = await _showVisibleSpotlights(
    context,
    [
      SpotlightGuideStep(
        targetKey: targets.addOrderKey,
        icon: Icons.add_circle_outline_rounded,
        title: '先完整走一遍第一笔排单',
        body: '先从新增排单开始。接下来会带你实际创建一笔自己的业务，再继续认识节点推进和归档。',
        targetShape: _extendedFabGuideShape(context),
        targetPadding: 0,
      ),
    ],
    finalLabel: '去创建',
  );
  if (!startFirstOrder || !context.mounted) {
    await stop();
    return;
  }

  final firstOrderId = await actions.createFirstOrder();
  if (!context.mounted) return;

  if (firstOrderId != null) {
    await actions.goTo(QuickStartGuideDestination.orders);
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    final continueFirstFlow = await _showVisibleSpotlights(
      context,
      [
        SpotlightGuideStep(
          targetKey: targets.firstOrderCardKey,
          icon: Icons.view_agenda_outlined,
          title: '这就是刚刚创建的排单',
          body: '之后大部分日常操作都可以直接从排单卡片完成。点卡片进详情，长按卡片则会打开置顶、归档、删除和批量操作。',
        ),
        SpotlightGuideStep(
          targetKey: targets.firstOrderProgressKey,
          icon: Icons.stacked_line_chart_rounded,
          title: '先推进节点里的小进度',
          body: '－/＋每次调整 10%，适合记录当前节点做到哪了。这个功能也可以在附加功能里关闭。',
        ),
        SpotlightGuideStep(
          targetKey: targets.firstOrderConfirmNodeKey,
          icon: Icons.check_circle_outline_rounded,
          title: '一个阶段完成后确认节点',
          body: '点“确认节点”会进入下一工作阶段；最后一个节点完成时，也可以直接进入顺利归档。',
          targetPadding: 0,
          borderRadius: 0,
        ),
      ],
      finalLabel: '练习归档',
    );
    if (!continueFirstFlow || !context.mounted) {
      await stop();
      return;
    }

    final archived = await actions.waitForFirstOrderArchive(firstOrderId);
    if (!context.mounted) return;
    if (archived) {
      final archiveShown = await showSection(
        QuickStartGuideDestination.archive,
        [
          SpotlightGuideStep(
            targetKey: targets.archivedOrderKey,
            icon: Icons.archive_outlined,
            title: '归档后的记录会留在这里',
            body: '归档会把它移出当前排单列表，并按顺利完成或中止结算保存最终收入。这里可以查看、恢复，也可以按时间清理旧归档。',
          ),
        ],
      );
      if (!archiveShown || !context.mounted) {
        await stop();
        return;
      }
    }
  }

  final orderToolsShown = await showSection(
    QuickStartGuideDestination.orders,
    [
      SpotlightGuideStep(
        targetKey: targets.searchKey,
        icon: Icons.search_rounded,
        title: '日常找单不用翻卡片',
        body: '搜索支持图名、单主、平台等字段；自定义标签开启后，还可以直接按标签筛选。',
      ),
      SpotlightGuideStep(
        targetKey: targets.toolbarKey,
        icon: Icons.dashboard_customize_outlined,
        title: '这里控制排序和视图',
        body: '可以按收入、剩余截稿等方式排序，并切换列表、卡片和总概览；总概览的列数也能自己填。',
      ),
    ],
  );
  if (!orderToolsShown || !context.mounted) {
    await stop();
    return;
  }

  final screenshotShown = await showSection(
    QuickStartGuideDestination.screenshotImport,
    [
      SpotlightGuideStep(
        targetKey: targets.screenshotImportKey,
        icon: Icons.document_scanner_outlined,
        title: '截图可以批量导入',
        body: '选择一张或多张平台订单截图后，会先在本机识别成可检查的条目。确认图名、时间、节点和疑似重复后，才会真正写入排单。',
        targetShape: _textButtonGuideShape(context),
        targetPadding: 0,
      ),
    ],
  );
  if (!screenshotShown || !context.mounted) {
    await stop();
    return;
  }

  final presetShown = await showSection(
    QuickStartGuideDestination.presetCenter,
    [
      SpotlightGuideStep(
        targetKey: targets.presetCenterKey,
        icon: Icons.account_tree_outlined,
        title: '把常用流程先做成预设',
        body: '节点预设保存草图、线稿、上色、成稿等工作阶段；同页的加价预设可以保存固定额、比例或阶梯加价，新增排单时直接复用。',
      ),
    ],
  );
  if (!presetShown || !context.mounted) {
    await stop();
    return;
  }

  final productsShown = await showSection(
    QuickStartGuideDestination.products,
    [
      SpotlightGuideStep(
        targetKey: targets.productsTabKey,
        icon: Icons.image_outlined,
        title: '成品是另一类业务记录',
        body: '这里记录已经完成、可以售卖的作品。可以新增单次售卖或多次售卖成品，每次售出都会留下单独的售出时间记录。',
      ),
    ],
  );
  if (!productsShown || !context.mounted) {
    await stop();
    return;
  }

  final scheduleShown = await showSection(
    QuickStartGuideDestination.schedule,
    [
      SpotlightGuideStep(
        targetKey: targets.scheduleTabKey,
        icon: Icons.calendar_month_outlined,
        title: '日程集中看截稿和交付',
        body: '日程会把待交稿、已交稿和当天收入按日期集中起来，适合每天检查接下来要赶哪些稿。',
      ),
    ],
  );
  if (!scheduleShown || !context.mounted) {
    await stop();
    return;
  }

  final statisticsShown = await showSection(
    QuickStartGuideDestination.statistics,
    [
      SpotlightGuideStep(
        targetKey: targets.statisticsTabKey,
        icon: Icons.bar_chart_rounded,
        title: '收入都在统计里汇总',
        body: '这里看月收入、年收入、本月待收入、平台分布和笔数。排单正式归档后才会计入已收入；未归档且本月截稿的排单会进入待收入。',
      ),
    ],
  );
  if (!statisticsShown || !context.mounted) {
    await stop();
    return;
  }

  final receiptShown = await showSection(
    QuickStartGuideDestination.receiptCenter,
    [
      SpotlightGuideStep(
        targetKey: targets.receiptCenterKey,
        icon: Icons.receipt_long_outlined,
        title: '小票有两种生成方式',
        body: '“按单子生成”可以挑排单或成品；“按单主生成”会统计某个单主某一年的已归档业务。生成后文字、字号、背景和字体颜色都可以继续编辑。',
      ),
    ],
  );
  if (!receiptShown || !context.mounted) {
    await stop();
    return;
  }

  final syncShown = await showSection(
    QuickStartGuideDestination.sync,
    [
      SpotlightGuideStep(
        targetKey: targets.syncKey,
        icon: Icons.sync_alt_rounded,
        title: '设备同步平时可以自动工作',
        body: '第一次加设备需要两边确认配对；完成后，已绑定设备会在打开时交换数据。这里也可以暂停同步、查看状态和手动立即同步。',
      ),
    ],
  );
  if (!syncShown || !context.mounted) {
    await stop();
    return;
  }

  final accountShown = await showSection(
    QuickStartGuideDestination.account,
    [
      SpotlightGuideStep(
        targetKey: targets.accountTitleKey,
        icon: Icons.manage_accounts_outlined,
        title: '账号与设备都在这里管理',
        body: '这里可以查看账号信息、当前使用中的设备、添加新设备和解绑设备。退出登录只退出当前账号；解绑才会把设备从账号的使用中设备里移除。',
        targetPadding: 4,
        borderRadius: 6,
      ),
    ],
  );
  if (!accountShown || !context.mounted) {
    await stop();
    return;
  }

  final settingsShown = await showSection(
    QuickStartGuideDestination.settings,
    [
      SpotlightGuideStep(
        targetKey: targets.settingsBackupKey,
        icon: Icons.inventory_2_outlined,
        title: '同步之外也要知道完整备份',
        body: '完整备份会带走排单、成品、预设、设置、设备记录、同步历史和参考图。换设备或做大改动前，可以先在这里留一份。',
      ),
    ],
  );
  if (!settingsShown || !context.mounted) {
    await stop();
    return;
  }

  final pwaInstallShown = await showSection(
    QuickStartGuideDestination.pwaInstall,
    [
      SpotlightGuideStep(
        targetKey: targets.pwaInstallKey,
        icon: Icons.install_desktop_rounded,
        title: '网页版也可以添加到桌面',
        body: '添加后可以像普通应用一样从桌面或主屏幕直接打开。支持安装提示的浏览器可以直接点这里安装；其他浏览器会告诉你对应的菜单操作。',
        borderRadius: 12,
      ),
    ],
  );
  if (!pwaInstallShown || !context.mounted) {
    await stop();
    return;
  }

  final featureShown = await showSection(
    QuickStartGuideDestination.featureToggle,
    [
      SpotlightGuideStep(
        targetKey: targets.featureToggleTitleKey,
        icon: Icons.extension_outlined,
        title: '附加功能可以按需要开关',
        body: '这一页集中管理搜索、标签、参考图、节点小进度、成品、日程、统计和截稿提醒等附加功能。关闭只是隐藏入口，不会删除已有数据。',
        targetPadding: 4,
        borderRadius: 6,
      ),
    ],
  );
  if (!featureShown || !context.mounted) {
    await stop();
    return;
  }

  await actions.finish();
}

Future<void> showFirstRunGuide(
  BuildContext context, {
  bool detailed = false,
  QuickStartGuideTargets? targets,
  Future<void> Function()? prepareQuickStart,
  QuickStartGuideActions? actions,
}) {
  if (detailed) {
    return _showDetailedGuide(
      context,
      targets: targets,
      prepareQuickStart: prepareQuickStart,
      actions: actions,
    );
  }
  if (targets != null) {
    return _showInteractiveQuickStart(
      context,
      targets,
      prepare: prepareQuickStart,
      actions: actions,
    );
  }

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
