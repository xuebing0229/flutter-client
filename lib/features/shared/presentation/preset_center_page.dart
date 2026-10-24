import 'package:flutter/material.dart';

import '../../../core/finance/pricing_preset_store.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/presentation/node_preset_page.dart';
import 'pricing_preset_page.dart';

class PresetCenterPage extends StatelessWidget {
  const PresetCenterPage({
    required this.nodePresetStore,
    required this.pricingPresetStore,
    super.key,
  });

  final NodePresetStore nodePresetStore;
  final PricingPresetStore pricingPresetStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '节点＆加价预设',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('节点预设'),
              subtitle: const Text('管理草图、线稿、上色、成稿等流程节点'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NodePresetPage(store: nodePresetStore),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('加价预设'),
              subtitle: const Text('管理倍率、百分比和固定金额加价'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PricingPresetPage(store: pricingPresetStore),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
