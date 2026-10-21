import 'package:flutter/material.dart';

import '../../../core/finance/pricing_adjustments.dart';
import '../../../core/finance/pricing_preset_store.dart';

class PricingPresetSelector extends StatelessWidget {
  const PricingPresetSelector({
    required this.store,
    required this.selected,
    required this.onChanged,
    super.key,
    this.label = '加价预设',
  });

  final PricingPresetStore store;
  final List<PricingAdjustment> selected;
  final ValueChanged<List<PricingAdjustment>> onChanged;
  final String label;

  bool _isSelected(String id) => selected.any((item) => item.id == id);

  void _toggle(PricingAdjustment preset, bool enabled) {
    final next = <PricingAdjustment>[
      for (final item in selected)
        if (item.id != preset.id) item.snapshot(),
    ];
    if (enabled) next.add(preset.snapshot());
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final presets = store.presets;
        final libraryIds = <String>{for (final item in presets) item.id};
        final detached = selected
            .where((item) => !libraryIds.contains(item.id))
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (presets.isEmpty && detached.isEmpty)
              Text(
                '还没有加价预设，可在侧栏的“加价预设”里新建。',
                style: TextStyle(color: colors.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in presets)
                    FilterChip(
                      selected: _isSelected(preset.id),
                      label: Text('${preset.name}  ${preset.formulaLabel}'),
                      onSelected: (value) => _toggle(preset, value),
                    ),
                  for (final preset in detached)
                    InputChip(
                      label: Text('${preset.name}  ${preset.formulaLabel}'),
                      selected: true,
                      onDeleted: () {
                        onChanged(<PricingAdjustment>[
                          for (final item in selected)
                            if (item.id != preset.id) item.snapshot(),
                        ]);
                      },
                    ),
                ],
              ),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已套用 ${selected.length} 个预设；保存后会冻结当前规则，之后修改预设不会影响这条记录。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}
