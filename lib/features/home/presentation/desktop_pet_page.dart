import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/desktop_pet/desktop_pet_service.dart';
import '../../focus/presentation/focus_panel.dart';
import '../../focus/state/focus_store.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../shared/presentation/layout_spacing.dart';

class DesktopPetPage extends StatefulWidget {
  const DesktopPetPage({
    required this.orderStore,
    required this.focusStore,
    required this.onOpenOrder,
    required this.showDesktopPet,
    required this.showFocus,
    super.key,
  });

  final OrderStore orderStore;
  final FocusStore focusStore;
  final Future<void> Function(String orderId) onOpenOrder;
  final bool showDesktopPet;
  final bool showFocus;

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
    final active = widget.showFocus ? widget.focusStore.activeSession : null;
    if (active != null && active.orderId != order.id) {
      final lockedTitle = active.isFreeFocus
          ? '自由专注'
          : (active.orderTitleSnapshot ?? '原排单');
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('当前专注已锁定'),
          content: Text(
            '这次专注开始时锁定的是“$lockedTitle”。\n'
            '切换“当前在画订单”不会改写正在进行的专注。'
            '如果现在要开始画“${order.title}”，建议结束本次并新开一次计时。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('switch'),
              child: const Text('仅切换'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('restart'),
              child: const Text('结束并新开'),
            ),
          ],
        ),
      );
      if (action == null) return;
      if (action == 'restart') {
        widget.focusStore.stopActive();
        await _settings.selectCurrentOrder(
          orderId: order.id,
          title: order.title,
          node: order.currentNode.name,
          deadline: order.deadline,
        );
        widget.focusStore.start(order: order);
        return;
      }
    }

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
      final sourcePath = await _settings.pickAssetSource();
      if (sourcePath == null || !mounted) return;

      final hasCurrentImage = slot == DesktopPetAssetSlot.idleA
          ? preset.imageA != null
          : preset.imageB != null;
      final currentPlacement = slot == DesktopPetAssetSlot.idleA
          ? preset.placementA
          : preset.placementB;
      final otherPlacement = slot == DesktopPetAssetSlot.idleA
          ? preset.placementB
          : preset.placementA;
      final initialPlacement = hasCurrentImage
          ? currentPlacement
          : (slot == DesktopPetAssetSlot.keyB && preset.imageA != null
              ? preset.placementA
              : (slot == DesktopPetAssetSlot.idleA && preset.imageB != null
                  ? preset.placementB
                  : currentPlacement));
      final guidePath = slot == DesktopPetAssetSlot.idleA
          ? preset.imageB
          : preset.imageA;

      final placement = await showDialog<DesktopPetPlacement>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DesktopPetPlacementDialog(
          slot: slot,
          sourcePath: sourcePath,
          initialPlacement: initialPlacement,
          guidePath: guidePath,
          guidePlacement: otherPlacement,
        ),
      );
      if (placement == null) return;

      await _settings.importAssetFromPath(
        preset.id,
        slot,
        sourcePath,
        placement,
      );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.showDesktopPet ? '桌宠' : '专注',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _settings,
          widget.orderStore,
          widget.focusStore,
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
              if (widget.showDesktopPet) ...[
                _InfoCard(
                child: Text(
                  '每个桌宠预设就是一组 A/B 图片：A 是平时状态，B 只在键盘按键或鼠标点击时显示。'
                  '导入时会先进入固定桌宠画布定位，A/B 使用同一坐标系，避免切换时人物跳位。',
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
                      const SizedBox(height: 14),
                      _PairPlacementPreview(
                        preset: selected,
                        onPlacementChanged: (slot, placement) =>
                            _settings.setPlacement(
                          selected.id,
                          slot,
                          placement,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: '桌面显示',
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '文字泡位置',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<DesktopPetBubblePosition>(
                    segments: const [
                      ButtonSegment(
                        value: DesktopPetBubblePosition.above,
                        icon: Icon(Icons.vertical_align_top_rounded),
                        label: Text('头顶 · 横向'),
                      ),
                      ButtonSegment(
                        value: DesktopPetBubblePosition.side,
                        icon: Icon(Icons.view_sidebar_outlined),
                        label: Text('旁边 · 竖向'),
                      ),
                    ],
                    selected: <DesktopPetBubblePosition>{
                      _settings.bubblePosition,
                    },
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      unawaited(
                        _settings.setBubblePosition(selection.first),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _ScaleSetting(
                    label: '桌宠大小',
                    value: _settings.petScale,
                    min: 0.5,
                    max: 1.8,
                    onChanged: (value) =>
                        unawaited(_settings.setPetScale(value)),
                  ),
                  const SizedBox(height: 10),
                  _ScaleSetting(
                    label: '文字泡大小',
                    value: _settings.bubbleScale,
                    min: 0.65,
                    max: 1.8,
                    onChanged: (value) =>
                        unawaited(_settings.setBubbleScale(value)),
                  ),
                  const SizedBox(height: 10),
                  _ScaleSetting(
                    label: '计时板大小',
                    value: _settings.focusClockScale,
                    min: 0.65,
                    max: 1.8,
                    onChanged: (value) =>
                        unawaited(_settings.setFocusClockScale(value)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '头顶模式使用横向文字泡；旁边模式使用瘦长竖向文字泡。文字泡贴人物边界，计时板固定在人物右侧上半部；两者大小可分别调整并自动跟随当前主题。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: '文字泡内容',
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
                '“当前在画订单”由你在这里手动选择具体排单；桌宠图片、预设、显示大小和文字泡设置只保存在本机电脑，专注计时与历史记录会随账号在手机和电脑间同步。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
            ],
              if (!widget.showDesktopPet && widget.showFocus) ...[
                _InfoCard(
                  child: Text(
                    Platform.isWindows
                        ? '桌宠当前已关闭，这里只保留专注计时与专注记录；重新开启桌宠后，桌宠设置会回到同一个板块。'
                        : '手机端不显示桌宠形象，这里保留与电脑双端同步的排单专注计时和专注列表。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.showDesktopPet && !widget.showFocus) ...[
                _InfoCard(
                  child: Text(
                    '专注计时当前已关闭，这里只显示桌宠设置。已有专注记录不会删除，重新开启后会恢复。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.showFocus)
                FocusPanel(
                  orderStore: widget.orderStore,
                  focusStore: widget.focusStore,
                  onOpenOrder: widget.onOpenOrder,
                  desktopSettings: widget.showDesktopPet ? _settings : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopPetPlacementDialog extends StatefulWidget {
  const _DesktopPetPlacementDialog({
    required this.slot,
    required this.sourcePath,
    required this.initialPlacement,
    required this.guidePath,
    required this.guidePlacement,
  });

  final DesktopPetAssetSlot slot;
  final String sourcePath;
  final DesktopPetPlacement initialPlacement;
  final String? guidePath;
  final DesktopPetPlacement guidePlacement;

  @override
  State<_DesktopPetPlacementDialog> createState() =>
      _DesktopPetPlacementDialogState();
}

class _DesktopPetPlacementDialogState
    extends State<_DesktopPetPlacementDialog> {
  late DesktopPetPlacement _placement;
  bool _showGuide = true;

  @override
  void initState() {
    super.initState();
    _placement = widget.initialPlacement;
  }

  void _update({
    double? scale,
    double? offsetX,
    double? offsetY,
  }) {
    setState(() {
      _placement = _placement.copyWith(
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slotName =
        widget.slot == DesktopPetAssetSlot.idleA ? 'A · 平时状态' : 'B · 操作状态';
    final guideFile = widget.guidePath == null ? null : File(widget.guidePath!);
    final hasGuide = guideFile?.existsSync() == true;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '定位 $slotName',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '下面的方框就是桌宠人物的固定显示画布。拖动图片调整位置，用滑杆调整大小；A/B 共用同一套坐标。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide
                        .clamp(280.0, 430.0)
                        .toDouble();
                    return Center(
                      child: SizedBox.square(
                        dimension: side,
                        child: _PlacementCanvas(
                          sourcePath: widget.sourcePath,
                          placement: _placement,
                          guidePath: hasGuide ? widget.guidePath : null,
                          guidePlacement: widget.guidePlacement,
                          showGuide: _showGuide,
                          onPan: (delta) {
                            _update(
                              offsetX: _placement.offsetX +
                                  delta.dx / (side / 2),
                              offsetY: _placement.offsetY +
                                  delta.dy / (side / 2),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 54, child: Text('大小')),
                  Expanded(
                    child: Slider(
                      min: 0.35,
                      max: 3,
                      value: _placement.scale,
                      onChanged: (value) => _update(scale: value),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${_placement.scale.toStringAsFixed(2)}×',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              if (hasGuide)
                CheckboxListTile(
                  value: _showGuide,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('半透明叠加另一张状态图作为对齐参考'),
                  onChanged: (value) =>
                      setState(() => _showGuide = value ?? true),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _placement =
                          widget.slot == DesktopPetAssetSlot.keyB &&
                                  hasGuide
                              ? widget.guidePlacement
                              : _placement.copyWith(
                                  offsetX: 0,
                                  offsetY: 0,
                                ),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      widget.slot == DesktopPetAssetSlot.keyB && hasGuide
                          ? '跟随 A 的位置'
                          : '重置位置',
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_placement),
                    child: const Text('保存定位'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementCanvas extends StatelessWidget {
  const _PlacementCanvas({
    required this.sourcePath,
    required this.placement,
    required this.guidePath,
    required this.guidePlacement,
    required this.showGuide,
    required this.onPan,
  });

  final String sourcePath;
  final DesktopPetPlacement placement;
  final String? guidePath;
  final DesktopPetPlacement guidePlacement;
  final bool showGuide;
  final ValueChanged<Offset> onPan;

  Widget _placedImage(
    String path,
    DesktopPetPlacement value, {
    double opacity = 1,
  }) {
    return Positioned.fill(
      child: FractionalTranslation(
        translation: Offset(value.offsetX / 2, value.offsetY / 2),
        child: Transform.scale(
          scale: value.scale,
          child: Opacity(
            opacity: opacity,
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final guide = guidePath;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onPan(details.delta),
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.primary, width: 2),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DesktopPetCanvasGuidePainter(
                  lineColor: colors.outlineVariant,
                ),
              ),
              if (showGuide && guide != null)
                _placedImage(
                  guide,
                  guidePlacement,
                  opacity: 0.28,
                ),
              _placedImage(sourcePath, placement),
              Positioned(
                left: 10,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '桌宠显示范围',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopPetCanvasGuidePainter extends CustomPainter {
  const _DesktopPetCanvasGuidePainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DesktopPetCanvasGuidePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

class _PairPlacementPreview extends StatelessWidget {
  const _PairPlacementPreview({
    required this.preset,
    required this.onPlacementChanged,
  });

  final DesktopPetPreset preset;
  final Future<void> Function(
    DesktopPetAssetSlot slot,
    DesktopPetPlacement placement,
  ) onPlacementChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 520
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _SinglePlacementPreview(
                label: 'A · 平时状态',
                path: preset.imageA,
                placement: preset.placementA,
                importPlacement:
                    preset.importPlacementA ?? preset.placementA,
                onPlacementChanged: (placement) => onPlacementChanged(
                  DesktopPetAssetSlot.idleA,
                  placement,
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _SinglePlacementPreview(
                label: 'B · 操作状态',
                path: preset.imageB,
                placement: preset.placementB,
                importPlacement:
                    preset.importPlacementB ?? preset.placementB,
                onPlacementChanged: (placement) => onPlacementChanged(
                  DesktopPetAssetSlot.keyB,
                  placement,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SinglePlacementPreview extends StatefulWidget {
  const _SinglePlacementPreview({
    required this.label,
    required this.path,
    required this.placement,
    required this.importPlacement,
    required this.onPlacementChanged,
  });

  final String label;
  final String? path;
  final DesktopPetPlacement placement;
  final DesktopPetPlacement importPlacement;
  final Future<void> Function(DesktopPetPlacement placement)
      onPlacementChanged;

  @override
  State<_SinglePlacementPreview> createState() =>
      _SinglePlacementPreviewState();
}

class _SinglePlacementPreviewState extends State<_SinglePlacementPreview> {
  late DesktopPetPlacement _placement;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _placement = widget.placement;
  }

  @override
  void didUpdateWidget(covariant _SinglePlacementPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _editing = false;
      _saving = false;
      _placement = widget.placement;
      return;
    }
    if (!_editing &&
        !_samePlacement(oldWidget.placement, widget.placement)) {
      _placement = widget.placement;
    }
  }

  bool _samePlacement(
    DesktopPetPlacement left,
    DesktopPetPlacement right,
  ) {
    return (left.scale - right.scale).abs() < 0.0001 &&
        (left.offsetX - right.offsetX).abs() < 0.0001 &&
        (left.offsetY - right.offsetY).abs() < 0.0001;
  }

  void _beginEditing() {
    setState(() {
      _placement = widget.placement;
      _editing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _placement = widget.placement;
      _editing = false;
    });
  }

  Future<void> _finishEditing() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onPlacementChanged(_placement);
      if (!mounted) return;
      setState(() => _editing = false);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _move(Offset delta, double side) {
    if (!_editing || side <= 0) return;
    setState(() {
      _placement = _placement.copyWith(
        offsetX: _placement.offsetX + delta.dx / (side / 2),
        offsetY: _placement.offsetY + delta.dy / (side / 2),
      );
    });
  }

  void _setScale(double value) {
    if (!_editing) return;
    setState(() {
      _placement = _placement.copyWith(scale: value);
    });
  }

  void _centerDraft() {
    if (!_editing) return;
    setState(() {
      _placement = _placement.copyWith(
        offsetX: 0,
        offsetY: 0,
      );
    });
  }

  void _resetDraft() {
    if (!_editing) return;
    setState(() {
      _placement = widget.importPlacement;
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.path == null ? null : File(widget.path!);
    final exists = file?.existsSync() == true;
    final colors = Theme.of(context).colorScheme;

    Widget imageStack(File file) => Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: Offset(
                _placement.offsetX / 2,
                _placement.offsetY / 2,
              ),
              child: Transform.scale(
                scale: _placement.scale,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _DesktopPetCanvasGuidePainter(
                  lineColor: _editing
                      ? colors.primary.withValues(alpha: 0.7)
                      : colors.outlineVariant,
                ),
              ),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (exists && !_editing)
              TextButton.icon(
                onPressed: _beginEditing,
                icon: const Icon(Icons.open_with_rounded, size: 18),
                label: const Text('编辑位置'),
              ),
            if (exists && _editing)
              Text(
                '编辑中',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(
                      color: _editing ? colors.primary : colors.outlineVariant,
                      width: _editing ? 2 : 1,
                    ),
                  ),
                  child: exists
                      ? (_editing
                          ? MouseRegion(
                              cursor: SystemMouseCursors.move,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) =>
                                    _move(details.delta, side),
                                child: imageStack(file!),
                              ),
                            )
                          : imageStack(file!))
                      : Center(
                          child: Text(
                            '未导入',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        if (exists && _editing) ...[
          const SizedBox(height: 8),
          Text(
            '拖动画面调整位置；这里的改动只有点“完成”后才会保存。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 36, child: Text('大小')),
              Expanded(
                child: Slider(
                  min: 0.35,
                  max: 3,
                  value: _placement.scale,
                  onChanged: _setScale,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${_placement.scale.toStringAsFixed(2)}×',
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '上下左右居中',
                onPressed: _saving ? null : _centerDraft,
                icon: const Icon(Icons.center_focus_strong_rounded),
              ),
              IconButton(
                tooltip: '恢复导入时的位置和大小',
                onPressed: _saving ? null : _resetDraft,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : _cancelEditing,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _finishEditing,
                child: Text(_saving ? '保存中…' : '完成'),
              ),
            ],
          ),
        ],
      ],
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

class _ScaleSetting extends StatefulWidget {
  const _ScaleSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_ScaleSetting> createState() => _ScaleSettingState();
}

class _ScaleSettingState extends State<_ScaleSetting> {
  late double _draft;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.value;
  }

  @override
  void didUpdateWidget(covariant _ScaleSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && (oldWidget.value - widget.value).abs() > 0.001) {
      _draft = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _draft.clamp(widget.min, widget.max).toDouble();
    final percent = (value * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) * 20).round(),
            onChangeStart: (_) => _dragging = true,
            onChanged: (next) => setState(() => _draft = next),
            onChangeEnd: (next) {
              _dragging = false;
              widget.onChanged(next);
            },
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '$percent%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
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
