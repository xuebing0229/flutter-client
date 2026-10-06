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
    icon: Icons.auto_awesome_rounded,
    title: '你已进入抽象版',
    body: '抽象版会把部分文案、提示和交互换成更抽象的表现，但工作数据还是同一份。',
    bullets: [
      '排单、成品、日程、统计、归档和设备同步的数据规则不会因为切换抽象版而变成另一套。',
      '切换抽象版不会复制、清空或重建现有数据。',
      '觉得过于抽象时，可以随时切回普通版。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.extension_outlined,
    title: '功能突然不见了？先看附加功能开关',
    body: '附加功能关闭后，对应入口会直接消失，看起来会像“被吃掉了”。',
    bullets: [
      '想重新打开时，进入左侧菜单的“附加功能开关”。',
      '成品、日程、统计、搜索、排序、视图切换等都可能因为开关关闭而隐藏。',
      '关闭入口只会隐藏功能，不会删除里面已经存在的数据。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.school_outlined,
    title: '抽象版有自己的使用教程',
    body: '只要抽象版处于开启状态，左侧菜单里的“使用教程”就会打开这份抽象版教程。',
    bullets: [
      '切回普通版以后，“使用教程”会自动恢复成普通版教程。',
      '第一次主动开启抽象版时，本教程会强制打开一次，避免打开后完全不知道发生了什么。',
      '以后想重看，直接从“使用教程”入口打开即可。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.sync_alt_rounded,
    title: '同步和备份还是认真的',
    body: '抽象的是表现，不是你的稿费和同步数据。',
    bullets: [
      '设备同步仍按原来的字段级合并和冲突处理规则工作。',
      '抽象版开关本身属于界面设置，会和其他界面设置一起同步。',
      '完整备份仍然包含排单、成品、节点预设、账号设备信息和界面设置。',
    ],
  ),
  _AbstractGuideSection(
    icon: Icons.undo_rounded,
    title: '想回普通版',
    body: '路径很简单：附加功能开关 → 抽象版 → 关闭。',
    bullets: [
      '关闭后立即回到普通版表现。',
      '以后再次开启不会重复强制弹教程；需要时可以手动从“使用教程”重看。',
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
                        Icons.auto_awesome_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '抽象版使用教程',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '先看完再抽象，至少知道东西去哪了。',
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
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(forced ? '我知道了，进入抽象版' : '知道了'),
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
