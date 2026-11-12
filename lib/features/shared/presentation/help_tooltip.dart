import 'package:flutter/material.dart';

/// Shared tap-to-explain question-mark affordance.
///
/// Keep this as the single implementation for inline explanatory help so
/// feature pages do not drift into separate tooltip styles or behaviors.
class InlineHelpTooltip extends StatelessWidget {
  const InlineHelpTooltip({
    required this.message,
    this.size = 18,
    super.key,
  });

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Icon(
        Icons.help_outline_rounded,
        size: size,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.55),
      ),
    );
  }
}
