import 'package:flutter/material.dart';

class SummaryCardSurface extends StatelessWidget {
  const SummaryCardSurface({
    required this.compact,
    required this.onTap,
    required this.child,
    this.onLongPress,
    super.key,
  });

  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            compact ? 12 : 16,
            compact ? 12 : 18,
            compact ? 12 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SummaryTag extends StatelessWidget {
  const SummaryTag({
    required this.text,
    this.compact = false,
    super.key,
  });

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 4 : 5,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.labelMedium)
              ?.copyWith(
            color: colors.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class SummaryMetaItem extends StatelessWidget {
  const SummaryMetaItem({
    required this.icon,
    required this.label,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: compact ? 15 : 18,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
