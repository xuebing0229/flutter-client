import 'package:flutter/material.dart';

class AppAboutPage extends StatelessWidget {
  const AppAboutPage({
    required this.version,
    required this.buildNumber,
    super.key,
  });

  final String version;
  final int buildNumber;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '关于冒险者公会',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '冒险者公会',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '版本 $version ($buildNumber)',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '面向画师排单、成品、日程、收入与专注记录的本地优先工具。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '开源软件与致谢',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const _CreditTile(
                  title: 'Syncthing',
                  subtitle:
                      '用于设备间点对点同步。\n'
                      '许可证：Mozilla Public License 2.0\n'
                      '项目：https://github.com/syncthing/syncthing',
                ),
                const Divider(height: 1),
                const _CreditTile(
                  title: 'VPet-Simulator.Core',
                  subtitle:
                      '用于 Windows 桌宠功能的 WPF 桌宠渲染基础。\n'
                      '感谢 VPet Group 与 VPet contributors。\n'
                      '许可证：Apache License 2.0\n'
                      '项目：https://github.com/LorisYounger/VPet',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '冒险者公会的桌宠使用用户自行导入的 A/B 图片，不分发 VPet 自带角色动画资源。'
            '对应第三方许可证与声明随项目和相关组件一同保留。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SelectableText(subtitle),
      ),
    );
  }
}
