import 'package:flutter/material.dart';

import '../../orders/domain/queue_order.dart';

class FormFieldLabel extends StatelessWidget {
  const FormFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class ReadOnlyDetailRow extends StatelessWidget {
  const ReadOnlyDetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
    super.key,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class CommissionSettingsEditor extends StatelessWidget {
  const CommissionSettingsEditor({
    required this.platform,
    required this.feeEnabled,
    required this.huajiaLoveLevel,
    required this.onlineController,
    required this.offlineController,
    required this.onPlatformChanged,
    required this.onFeeEnabledChanged,
    required this.onHuajiaLoveLevelChanged,
    required this.onOnlinePercentChanged,
    this.afterPlatform,
    super.key,
  });

  final CommissionPlatform platform;
  final bool feeEnabled;
  final HuajiaLoveLevel huajiaLoveLevel;
  final TextEditingController onlineController;
  final TextEditingController offlineController;
  final ValueChanged<CommissionPlatform> onPlatformChanged;
  final ValueChanged<bool> onFeeEnabledChanged;
  final ValueChanged<HuajiaLoveLevel> onHuajiaLoveLevelChanged;
  final ValueChanged<double> onOnlinePercentChanged;
  final Widget? afterPlatform;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormFieldLabel('平台'),
        DropdownButtonFormField<CommissionPlatform>(
          initialValue: platform,
          items: CommissionPlatform.values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onPlatformChanged(value);
          },
        ),
        if (afterPlatform != null) ...[
          const SizedBox(height: 14),
          afterPlatform!,
        ],
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            platform == CommissionPlatform.huajia
                ? '画加手续费'
                : '手续费 5%',
          ),
          subtitle: Text(
            platform == CommissionPlatform.huajia
                ? '500元及以下按5%；超过500元后，前500元收25元，超出部分约1%'
                : '开启后从参与手续费的金额中扣除 5%',
          ),
          value: feeEnabled,
          onChanged: onFeeEnabledChanged,
        ),
        if (platform == CommissionPlatform.huajia && feeEnabled) ...[
          const SizedBox(height: 8),
          const FormFieldLabel('真爱永恒'),
          DropdownButtonFormField<HuajiaLoveLevel>(
            initialValue: huajiaLoveLevel,
            items: HuajiaLoveLevel.values
                .map(
                  (level) => DropdownMenuItem(
                    value: level,
                    child: Text(
                      level == HuajiaLoveLevel.none
                          ? '无折扣'
                          : '${level.label} · 手续费${(level.feeMultiplier * 10).toStringAsFixed(0)}折',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onHuajiaLoveLevelChanged(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            '折扣只作用于平台手续费，超过500元部分约1%的支付通道费不打折',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (platform.usesOnlineOfflineSplit) ...[
          const SizedBox(height: 8),
          const FormFieldLabel('线上 / 线下比例'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: onlineController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '线上',
                    suffixText: '%',
                  ),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) onOnlinePercentChanged(parsed);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: offlineController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '线下',
                    suffixText: '%',
                  ),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) onOnlinePercentChanged(100 - parsed);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '仅线上部分参与手续费计算',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

String formatPercentValue(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}


class DateTimePickerButton extends StatelessWidget {
  const DateTimePickerButton({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await showDialog<_DeadlinePickerResult>(
      context: context,
      builder: (_) => _DeadlinePickerDialog(initialValue: value),
    );
    if (result == null) return;
    onChanged(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(context),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value == null
                    ? '未设置（不倒计时）'
                    : formatDateTimeValue(value!),
              ),
            ),
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: '清除截稿时间',
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.undo_rounded),
            color: colors.onSecondaryContainer,
          ),
        ],
      ],
    );
  }
}

class _DeadlinePickerResult {
  const _DeadlinePickerResult(this.value);

  final DateTime? value;
}

class _DeadlinePickerDialog extends StatefulWidget {
  const _DeadlinePickerDialog({required this.initialValue});

  final DateTime? initialValue;

  @override
  State<_DeadlinePickerDialog> createState() => _DeadlinePickerDialogState();
}

class _DeadlinePickerDialogState extends State<_DeadlinePickerDialog> {
  late DateTime _visibleMonth;
  DateTime? _selected;

  static const _weekdayLabels = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  void initState() {
    super.initState();
    final seed = widget.initialValue ?? DateTime.now();
    _visibleMonth = DateTime(seed.year, seed.month);
    _selected = widget.initialValue;
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + delta,
      );
    });
  }

  void _selectDate(DateTime date) {
    final previous = _selected;
    setState(() {
      _selected = DateTime(
        date.year,
        date.month,
        date.day,
        previous?.hour ?? 23,
        previous?.minute ?? 59,
      );
    });
  }

  void _quickSelect(Duration offset) {
    final target = DateTime.now().add(offset);
    final normalized = DateTime(
      target.year,
      target.month,
      target.day,
      target.hour,
      target.minute,
    );
    setState(() {
      _selected = normalized;
      _visibleMonth = DateTime(normalized.year, normalized.month);
    });
  }

  Future<void> _pickTime() async {
    final selected = _selected;
    if (selected == null) return;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selected),
    );
    if (picked == null) return;

    setState(() {
      _selected = DateTime(
        selected.year,
        selected.month,
        selected.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _selected;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择截稿时间',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                selected == null
                    ? '当前未设置，不会进行截稿倒计时'
                    : formatDateTimeValue(selected),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DeadlineQuickChip(
                    label: '24h',
                    onPressed: () => _quickSelect(const Duration(hours: 24)),
                  ),
                  _DeadlineQuickChip(
                    label: '48h',
                    onPressed: () => _quickSelect(const Duration(hours: 48)),
                  ),
                  _DeadlineQuickChip(
                    label: '72h',
                    onPressed: () => _quickSelect(const Duration(hours: 72)),
                  ),
                  _DeadlineQuickChip(
                    label: '7天',
                    onPressed: () => _quickSelect(const Duration(days: 7)),
                  ),
                  _DeadlineQuickChip(
                    label: '30天',
                    onPressed: () => _quickSelect(const Duration(days: 30)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '${_visibleMonth.year}年${_visibleMonth.month}月',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final label in _weekdayLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _DeadlineMonthGrid(
                month: _visibleMonth,
                selected: selected,
                onSelect: _selectDate,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: selected == null ? null : _pickTime,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(
                        selected == null
                            ? '先选择日期'
                            : '时间 ${_two(selected.hour)}:${_two(selected.minute)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      const _DeadlinePickerResult(null),
                    ),
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('清除时间'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: selected == null
                        ? null
                        : () => Navigator.of(context).pop(
                              _DeadlinePickerResult(selected),
                            ),
                    child: const Text('确定'),
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

class _DeadlineQuickChip extends StatelessWidget {
  const _DeadlineQuickChip({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.bolt_rounded, size: 17),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _DeadlineMonthGrid extends StatelessWidget {
  const _DeadlineMonthGrid({
    required this.month,
    required this.selected,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstOffset = firstDay.weekday % 7;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((firstOffset + dayCount + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final day = index - firstOffset + 1;
        if (day < 1 || day > dayCount) {
          return const SizedBox.shrink();
        }

        final date = DateTime(month.year, month.month, day);
        return _DeadlineDayCell(
          date: date,
          selected: selected != null && _sameDayDate(date, selected!),
          today: _sameDayDate(date, DateTime.now()),
          onTap: () => onSelect(date),
        );
      },
    );
  }
}

class _DeadlineDayCell extends StatelessWidget {
  const _DeadlineDayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (today)
                Positioned(
                  top: 1,
                  right: 2,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 11,
                    color: selected
                        ? colors.onPrimary.withValues(alpha: 0.9)
                        : colors.primary,
                  ),
                ),
              Text(
                '${date.day}',
                style: TextStyle(
                  color: selected ? colors.onPrimary : colors.onSurface,
                  fontWeight: selected || today
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameDayDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String formatDateTimeValue(DateTime value) {
  return '${value.year}-${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';
}

String _two(int number) => number.toString().padLeft(2, '0');
