import 'package:flutter/material.dart';

import '../../../core/finance/pricing_adjustments.dart';
import '../../../core/finance/pricing_preset_store.dart';
import 'layout_spacing.dart';

class PricingPresetPage extends StatelessWidget {
  const PricingPresetPage({required this.store, super.key});

  final PricingPresetStore store;

  Future<void> _openEditor(
    BuildContext context, {
    PricingAdjustment? preset,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PricingPresetEditorPage(
          store: store,
          preset: preset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加价预设', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          if (store.presets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '还没有加价预设。\n可以把商用 ×2、加急 +30%、背景 +¥100 等规则保存下来，排单和成品都能直接套用。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: AppLayoutSpacing.pageScrollPaddingWithAction(
              context,
              left: 16,
              top: 16,
              right: 16,
            ),
            itemCount: store.presets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final preset = store.presets[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(preset.formulaLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openEditor(context, preset: preset),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建'),
      ),
    );
  }
}

class _PricingPresetEditorPage extends StatefulWidget {
  const _PricingPresetEditorPage({required this.store, this.preset});

  final PricingPresetStore store;
  final PricingAdjustment? preset;

  @override
  State<_PricingPresetEditorPage> createState() =>
      _PricingPresetEditorPageState();
}

class _PricingPresetEditorPageState extends State<_PricingPresetEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _multiplierController;
  late final TextEditingController _percentController;
  late final TextEditingController _fixedController;

  bool get _isNew => widget.preset == null;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _nameController = TextEditingController(text: preset?.name ?? '');
    _multiplierController = TextEditingController(
      text: preset == null ? '1' : formatPricingNumber(preset.multiplier),
    );
    _percentController = TextEditingController(
      text: preset == null || preset.percent == 0
          ? ''
          : formatPricingNumber(preset.percent),
    );
    _fixedController = TextEditingController(
      text: preset == null || preset.fixedAmount == 0
          ? ''
          : formatPricingNumber(preset.fixedAmount),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _multiplierController.dispose();
    _percentController.dispose();
    _fixedController.dispose();
    super.dispose();
  }

  double? _number(TextEditingController controller, {double? empty}) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return empty;
    return double.tryParse(raw);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final multiplier = _number(_multiplierController, empty: 1);
    final percent = _number(_percentController, empty: 0);
    final fixed = _number(_fixedController, empty: 0);

    if (name.isEmpty) {
      _message('请填写预设名称');
      return;
    }
    if (multiplier == null ||
        percent == null ||
        fixed == null ||
        !multiplier.isFinite ||
        !percent.isFinite ||
        !fixed.isFinite ||
        multiplier < 0) {
      _message('请输入有效的加价数值');
      return;
    }
    if (percent < -100) {
      _message('百分比不能低于 -100%');
      return;
    }

    widget.store.upsert(
      PricingAdjustment(
        id: widget.preset?.id ??
            'pricing-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        multiplier: multiplier,
        percent: percent,
        fixedAmount: fixed,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final preset = widget.preset;
    if (preset == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除加价预设？'),
        content: const Text('已经套用到排单或成品里的规则是快照，不会跟着被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.remove(preset.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final preview = PricingAdjustment(
      id: 'preview',
      name: '预览',
      multiplier: _number(_multiplierController, empty: 1) ?? 1,
      percent: _number(_percentController, empty: 0) ?? 0,
      fixedAmount: _number(_fixedController, empty: 0) ?? 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建加价预设' : '编辑加价预设'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: '删除',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 18,
          top: 12,
          right: 18,
        ),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：商用 / 加急 / 复杂背景',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _multiplierController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '倍率',
              prefixText: '× ',
              helperText: '不需要倍率时填 1',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _percentController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: '百分比',
              suffixText: '%',
              hintText: '例如 30 或 -10',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fixedController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: '固定金额',
              prefixText: '¥ ',
              hintText: '可正可负',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('计算预览'),
            subtitle: Text(preview.formulaLabel),
          ),
          Text(
            '倍率和百分比按套用顺序计算；所有固定金额统一最后加减，不会被后续倍率重复放大。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
