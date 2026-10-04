import 'package:flutter/material.dart';

class AdjustmentDialogResult {
  const AdjustmentDialogResult({
    required this.amount,
    required this.feeEnabled,
  });

  final double amount;
  final bool feeEnabled;
}

class AdjustmentDetailRow extends StatelessWidget {
  const AdjustmentDetailRow({
    required this.label,
    required this.amount,
    required this.feeEnabled,
    required this.sign,
    required this.onTap,
    super.key,
  });

  final String label;
  final double amount;
  final bool feeEnabled;
  final String sign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = amount == 0
        ? '未设置'
        : [sign, '¥', formatAdjustmentMoney(amount), if (feeEnabled) '· 计手续费']
            .join(' ');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
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
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

Future<AdjustmentDialogResult?> showAdjustmentDialog({
  required BuildContext context,
  required String label,
  required double amount,
  required bool feeEnabled,
}) {
  final controller = TextEditingController(
    text: amount == 0 ? '' : formatAdjustmentMoney(amount),
  );
  var nextFeeEnabled = feeEnabled;

  return showDialog<AdjustmentDialogResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('设置$label'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '$label金额',
                      prefixText: '¥ ',
                      hintText: '0',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('计手续费'),
                    subtitle: const Text('按当前平台的手续费规则计算'),
                    value: nextFeeEnabled,
                    onChanged: (value) {
                      setDialogState(() {
                        nextFeeEnabled = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(controller.text.trim()) ?? 0;
                  Navigator.of(dialogContext).pop(
                    AdjustmentDialogResult(
                      amount: parsed < 0 ? 0 : parsed,
                      feeEnabled: nextFeeEnabled,
                    ),
                  );
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

String formatAdjustmentMoney(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
