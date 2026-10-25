import 'package:flutter/material.dart';

import '../../../core/features/app_feature_store.dart';

class FeatureTogglePage extends StatelessWidget {
  const FeatureTogglePage({
    required this.store,
    this.onHideFeatureToggle,
    super.key,
  });

  final AppFeatureStore store;
  final VoidCallback? onHideFeatureToggle;

  static const _items = <(AppFeature, String, String)>[
    (AppFeature.clientInfo, '单主信息', '显示排单的单主信息'),
    (AppFeature.nodeProgress, '节点小进度', '显示并调整当前节点的小进度'),
    (AppFeature.customTags, '自定义标签', '为排单添加自定义标签'),
    (AppFeature.referenceImages, '参考图', '保存排单与成品参考图'),
    (AppFeature.search, '搜索', '显示列表搜索'),
    (AppFeature.sorting, '排序', '显示排序选项'),
    (AppFeature.viewSwitch, '列表 / 卡片切换', '允许切换展示方式'),
    (AppFeature.products, '成品', '显示成品管理'),
    (AppFeature.schedule, '日程', '显示日程'),
    (AppFeature.statistics, '统计', '显示收入统计'),
    (AppFeature.abstractMode, '抽象版', '启用抽象模式'),
    (AppFeature.abstractEffects, '抽象表现', '启用抽象模式附加效果'),
    (AppFeature.focus, '专注记录', '显示专注计时与历史记录'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('附加功能开关')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '网页版会显示当前平台可用的功能；无法使用的功能会自动隐藏。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final item in _items)
              SwitchListTile(
                title: Text(item.$2),
                subtitle: Text(item.$3),
                value: store.enabled(item.$1),
                onChanged: (value) => store.setEnabled(item.$1, value),
              ),
          ],
        ),
      ),
    );
  }
}
