import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../../core/notifications/order_deadline_reminder_service.dart';
import 'reminder_background_guide.dart';

class FeatureTogglePage extends StatelessWidget {
  const FeatureTogglePage({
    required this.store,
    this.onHideFeatureToggle,
    super.key,
  });

  final AppFeatureStore store;
  final VoidCallback? onHideFeatureToggle;

  Future<void> _setDeadlineReminders(BuildContext context, bool enabled) async {
    if (!enabled) {
      await store.setEnabled(AppFeature.deadlineReminders, false);
      return;
    }

    const reminderService = OrderDeadlineReminderService();
    try {
      final granted = await reminderService.ensurePermission();
      if (!granted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有通知权限，截稿提醒保持关闭。'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (context.mounted) {
        await showReminderBackgroundGuide(
          context: context,
          reminderService: reminderService,
        );
      }
      await store.setEnabled(AppFeature.deadlineReminders, true);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知设置没有完成，截稿提醒保持关闭。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '附加功能开关',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 16,
              top: 8,
              right: 16,
            ),
            children: [
              _InfoCard(
                child: Text(
                  '关闭只会隐藏功能和入口，不会删除已有数据。以后重新打开，原来的内容还会保留。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _FeatureSection(
                title: '排单附加项',
                children: [
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.clientInfo,
                    icon: Icons.person_outline_rounded,
                    title: '单主信息',
                    subtitle: '关闭后新增、详情和卡片不再显示单主。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.nodeProgress,
                    icon: Icons.stacked_line_chart_rounded,
                    title: '节点小进度',
                    subtitle: '控制节点内 0%～100% 的 ±10 进度条。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.search,
                    icon: Icons.search_rounded,
                    title: '搜索',
                    subtitle: '控制排单和成品页顶部的搜索框。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.sorting,
                    icon: Icons.sort_rounded,
                    title: '排序',
                    subtitle: '控制排单和成品页的排序入口。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.viewSwitch,
                    icon: Icons.grid_view_rounded,
                    title: '视图切换',
                    subtitle: '控制列表视图与卡片视图之间的切换入口。',
                  ),
                  if (!Platform.isWindows)
                    _FeatureSwitch(
                      store: store,
                      feature: AppFeature.deadlineReminders,
                      icon: Icons.notifications_active_outlined,
                      title: '截稿通知提醒',
                      subtitle: '截稿前 7 天和 1 天本地提醒。开启时会引导完成通知与后台设置。',
                      onChanged: (value) =>
                          _setDeadlineReminders(context, value),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _FeatureSection(
                title: '独立板块',
                children: [
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.products,
                    icon: Icons.image_outlined,
                    title: '成品',
                    subtitle: '关闭后隐藏成品板块和成品归档内容。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.schedule,
                    icon: Icons.calendar_month_outlined,
                    title: '日程',
                    subtitle: '关闭后底部不再显示日程入口。',
                  ),
                  _FeatureSwitch(
                    store: store,
                    feature: AppFeature.statistics,
                    icon: Icons.bar_chart_outlined,
                    title: '统计',
                    subtitle: '关闭后底部不再显示统计入口。',
                  ),
                ],
              ),
              if (store.abstractMode) ...[
                const SizedBox(height: 14),
                _FeatureSection(
                  title: '版本玩法',
                  children: [
                    _FeatureSwitch(
                      store: store,
                      feature: AppFeature.abstractEffects,
                      icon: Icons.auto_awesome_rounded,
                      title: '抽象版表现',
                      subtitle: '控制抽象版里的趣味表现；关闭后仅保留抽象版美化。',
                    ),
                    if (store.abstractEffects && onHideFeatureToggle != null)
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        secondary: const Icon(Icons.visibility_off_outlined),
                        title: const Text('附加功能开关'),
                        subtitle: const Text('关闭后，本入口会在当前抽象版里消失。'),
                        value: true,
                        onChanged: (value) {
                          if (value) return;
                          onHideFeatureToggle?.call();
                          Navigator.of(context).maybePop();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '排单名、稿费、节点、截稿日期、备注、平台手续费、补款减款和归档属于基础功能，始终保留。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({
    required this.store,
    required this.feature,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onChanged,
  });

  final AppFeatureStore store;
  final AppFeature feature;
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function(bool value)? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: store.enabled(feature),
      onChanged: (value) async {
        final custom = onChanged;
        if (custom != null) {
          await custom(value);
        } else {
          await store.setEnabled(feature, value);
        }
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}
