import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/desktop_pet/desktop_pet_service.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../shared/presentation/layout_spacing.dart';

class DesktopPetPage extends StatefulWidget {
  const DesktopPetPage({
    required this.orderStore,
    super.key,
  });

  final OrderStore orderStore;

  @override
  State<DesktopPetPage> createState() => _DesktopPetPageState();
}

class _DesktopPetPageState extends State<DesktopPetPage> {
  final DesktopPetSettings _settings = DesktopPetSettings();
  final TextEditingController _customTextController = TextEditingController();
  Timer? _customTextSaveDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _settings.load();
    if (!mounted) return;
    _customTextController.text = _settings.customText;
  }

  @override
  void dispose() {
    _customTextSaveDebounce?.cancel();
    _customTextController.dispose();
    _settings.dispose();
    super.dispose();
  }

  List<QueueOrder> get _activeOrders => widget.orderStore.orders
      .where((order) => !order.isArchived && !order.isCompleted)
      .toList(growable: false);

  Future<void> _selectCurrentOrder(QueueOrder order) async {
    await _settings.selectCurrentOrder(
      orderId: order.id,
      title: order.title,
      node: order.currentNode.name,
      deadline: order.deadline,
    );
  }

  Future<String?> _askName({
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '桌宠预设名称',
              hintText: '给这个预设起个名字',
            ),
            onSubmitted: (value) {
              final normalized = value.trim();
              if (normalized.isNotEmpty) {
                Navigator.of(dialogContext).pop(normalized);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.trim();
                if (normalized.isNotEmpty) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createPreset() async {
    final name = await _askName(title: '新建桌宠预设');
    if (name == null) return;
    await _settings.createPreset(name);
  }

  Future<void> _renamePreset(DesktopPetPreset preset) async {
    final name = await _askName(
      title: '重命名桌宠预设',
      initialValue: preset.name,
    );
    if (name == null) return;
    await _settings.renamePreset(preset.id, name);
  }

  Future<void> _deletePreset(DesktopPetPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除桌宠预设？'),
        content: Text('“${preset.name}”以及这组 A/B 图片会从本机删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _settings.deletePreset(preset.id);
    }
  }

  Future<void> _pick(
    DesktopPetPreset preset,
    DesktopPetAssetSlot slot,
  ) async {
    try {
      await _settings.importAsset(preset.id, slot);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _scheduleCustomTextSave(String value) {
    _customTextSaveDebounce?.cancel();
    _customTextSaveDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_settings.setCustomText(value)),
    );
  }

  String _formatDeadline(DateTime? deadline) {
    if (deadline == null) return '未设置截稿时间';
    final now = DateTime.now();
    final delta = deadline.difference(now);
    if (delta.isNegative) return '已超过截稿时间';
    final days = delta.inDays;
    final hours = delta.inHours.remainder(24);
    final minutes = delta.inMinutes.remainder(60);
    if (days > 0) return '剩余 $days 天 $hours 小时';
    if (hours > 0) return '剩余 $hours 小时 $minutes 分';
    return '剩余 ${delta.inMinutes.clamp(0, 999999)} 分';
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return Scaffold(
        appBar: AppBar(title: const Text('桌宠')),
        body: const Center(child: Text('桌宠仅在 Windows 电脑版提供。')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '桌宠',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _settings,
          widget.orderStore,
        ]),
        builder: (context, _) {
          if (!_settings.loaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final selected = _settings.selectedPreset;
          final activeOrders = _activeOrders;

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
                  '每个桌宠预设就是一组 A/B 图片：A 是平时状态，B 只在键盘按键或鼠标点击时显示。'
                  '切换预设会整组切换美术资源。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Section(
                title: '桌宠预设',
                trailing: FilledButton.tonalIcon(
                  onPressed: _createPreset,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建预设'),
                ),
                children: [
                  if (_settings.presets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '还没有桌宠预设。新建一个名称后，再给它导入 A/B 两张图。',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _settings.presets)
                            ChoiceChip(
                              label: Text(preset.name),
                              selected:
                                  preset.id == _settings.selectedPresetId,
                              onSelected: (_) =>
                                  _settings.selectPreset(preset.id),
                            ),
                        ],
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selected.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: '重命名',
                            onPressed: () => _renamePreset(selected),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: '删除预设',
                            onPressed: () => _deletePreset(selected),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      _AssetTile(
                        title: 'A · 平时状态',
                        subtitle: '没有按键操作时显示',
                        path: selected.imageA,
                        onImport: () =>
                            _pick(selected, DesktopPetAssetSlot.idleA),
                        onClear: () => _settings.clearAsset(
                          selected.id,
                          DesktopPetAssetSlot.idleA,
                        ),
                      ),
                      const Divider(height: 1),
                      _AssetTile(
                        title: 'B · 操作状态',
                        subtitle: '键盘按键或鼠标点击时显示；松开后回到 A',
                        path: selected.imageB,
                        onImport: () =>
                            _pick(selected, DesktopPetAssetSlot.keyB),
                        onClear: () => _settings.clearAsset(
                          selected.id,
                          DesktopPetAssetSlot.keyB,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: '文字框内容',
                children: [
                  const SizedBox(height: 4),
                  SegmentedButton<DesktopPetTextMode>(
                    segments: const [
                      ButtonSegment(
                        value: DesktopPetTextMode.currentOrder,
                        icon: Icon(Icons.draw_outlined),
                        label: Text('当前在画订单'),
                      ),
                      ButtonSegment(
                        value: DesktopPetTextMode.custom,
                        icon: Icon(Icons.edit_note_rounded),
                        label: Text('自定义文字'),
                      ),
                    ],
                    selected: <DesktopPetTextMode>{_settings.textMode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      _settings.setTextMode(selection.first);
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_settings.textMode ==
                      DesktopPetTextMode.currentOrder)
                    _CurrentOrderPicker(
                      orders: activeOrders,
                      selectedOrderId: _settings.currentOrderId,
                      formatDeadline: _formatDeadline,
                      onSelected: _selectCurrentOrder,
                    )
                  else
                    TextField(
                      controller: _customTextController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: '自定义文字内容',
                        hintText: '例如：今天也在努力画画……',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _scheduleCustomTextSave,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '“当前在画订单”由你在这里手动选择具体排单；桌宠图片、预设和这项选择都只保存在本机电脑。',
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

class _CurrentOrderPicker extends StatelessWidget {
  const _CurrentOrderPicker({
    required this.orders,
    required this.selectedOrderId,
    required this.formatDeadline,
    required this.onSelected,
  });

  final List<QueueOrder> orders;
  final String? selectedOrderId;
  final String Function(DateTime?) formatDeadline;
  final Future<void> Function(QueueOrder order) onSelected;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('当前没有可选择的进行中排单。'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final order in orders)
              SizedBox(
                width: cardWidth,
                child: _CurrentOrderChoiceCard(
                  order: order,
                  selected: order.id == selectedOrderId,
                  deadlineText: formatDeadline(order.deadline),
                  onTap: () => onSelected(order),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CurrentOrderChoiceCard extends StatelessWidget {
  const _CurrentOrderChoiceCard({
    required this.order,
    required this.selected,
    required this.deadlineText,
    required this.onTap,
  });

  final QueueOrder order;
  final bool selected;
  final String deadlineText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${order.platform.label} · ${order.clientName.trim().isEmpty ? '未填写单主' : order.clientName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.currentNode.name} · $deadlineText',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.onImport,
    required this.onClear,
  });

  final String title;
  final String subtitle;
  final String? path;
  final VoidCallback onImport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final exists = file?.existsSync() == true;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: exists
              ? Image.file(
                  file!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exists)
            IconButton(
              tooltip: '清除',
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          FilledButton.tonal(
            onPressed: onImport,
            child: Text(exists ? '替换' : '导入'),
          ),
        ],
      ),
      onTap: onImport,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}
