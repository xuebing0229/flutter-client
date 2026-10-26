import 'package:flutter/material.dart';

class AdjustmentDialogResult {
  const AdjustmentDialogResult({
    required this.amount,
    required this.feeEnabled,
    this.pricingEnabled = false,
  });

  final double amount;
  final bool feeEnabled;
  final bool pricingEnabled;
}

AdjustmentDialogResult mergeAdjustmentEdit({
  required double baselineAmount,
  required bool baselineFeeEnabled,
  required AdjustmentDialogResult draft,
  required double currentAmount,
  required bool currentFeeEnabled,
  bool baselinePricingEnabled = false,
  bool currentPricingEnabled = false,
}) {
  final amountChanged = draft.amount != baselineAmount;
  final feeChanged = draft.feeEnabled != baselineFeeEnabled;
  final pricingChanged = draft.pricingEnabled != baselinePricingEnabled;

  final mergedAmount = amountChanged
      ? (currentAmount + (draft.amount - baselineAmount))
          .clamp(0, double.infinity)
          .toDouble()
      : currentAmount;

  return AdjustmentDialogResult(
    amount: mergedAmount,
    feeEnabled: feeChanged ? draft.feeEnabled : currentFeeEnabled,
    pricingEnabled:
        pricingChanged ? draft.pricingEnabled : currentPricingEnabled,
  );
}

class AdjustmentDetailRow extends StatelessWidget {
  const AdjustmentDetailRow({
    required this.label,
    required this.amount,
    required this.feeEnabled,
    required this.sign,
    required this.onTap,
    this.pricingEnabled = false,
    super.key,
  });

  final String label;
  final double amount;
  final bool feeEnabled;
  final bool pricingEnabled;
  final String sign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = amount == 0
        ? '未设置'
        : [
            sign,
            '¥',
            formatAdjustmentMoney(amount),
            if (feeEnabled) '· 计手续费',
            if (pricingEnabled) '· 参与加价',
          ].join(' ');

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
  bool pricingEnabled = false,
  bool allowPricingParticipation = false,
}) {
  final controller = TextEditingController(
    text: amount == 0 ? '' : formatAdjustmentMoney(amount),
  );
  var nextFeeEnabled = feeEnabled;
  var nextPricingEnabled = pricingEnabled;
  String? errorText;

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
                      errorText: errorText,
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
                  if (allowPricingParticipation)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('参与加价计算'),
                      subtitle: const Text('×N 和 ±N% 会作用于这笔补款；固定金额加价不重复计算'),
                      value: nextPricingEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          nextPricingEnabled = value ?? false;
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
                  final raw = controller.text.trim();
                  final parsed = raw.isEmpty ? 0.0 : double.tryParse(raw);
                  if (parsed == null || !parsed.isFinite || parsed < 0) {
                    setDialogState(() {
                      errorText = '请输入有效的金额';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    AdjustmentDialogResult(
                      amount: parsed,
                      feeEnabled: nextFeeEnabled,
                      pricingEnabled: nextPricingEnabled,
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
