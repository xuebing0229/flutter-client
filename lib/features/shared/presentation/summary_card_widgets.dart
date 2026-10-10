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
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = 20.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.21 : 0.075),
            blurRadius: 13,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Color.alphaBlend(
                  colors.primary.withValues(alpha: dark ? 0.35 : 0.27),
                  colors.outlineVariant,
                ),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    colors.primary.withValues(alpha: dark ? 0.035 : 0.022),
                    colors.surface,
                  ),
                  colors.surface,
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius - 4),
                          border: Border.all(
                            color: colors.primary.withValues(
                              alpha: dark ? 0.19 : 0.14,
                            ),
                            width: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  // Exactly the original spacing: visual strokes add no size.
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 18,
                    compact ? 12 : 16,
                    compact ? 12 : 18,
                    compact ? 12 : 16,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
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

/// Keeps card actions on one line without changing the user's text scale.
///
/// First trims the horizontal insets, then hides the decorative icon if needed.
/// The card grid can consult [minimumCardWidth] to fall back to one column
/// when the label itself no longer fits in a half-width card.
class ResponsiveCardActionButton extends StatelessWidget {
  const ResponsiveCardActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool compact;

  static double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Minimum outer width of a compact card containing this action.
  static double minimumCardWidth(BuildContext context, String label) =>
      _labelWidth(context, label) + 34; // 24 card + 8 button + 2 borders

  @override
  Widget build(BuildContext context) {
    final labelWidth = _labelWidth(context, label);
    final roomyInset = compact ? 12.0 : 16.0;
    final tightInset = compact ? 4.0 : 10.0;
    final iconSize = compact ? 18.0 : 20.0;
    final iconGap = compact ? 4.0 : 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconWithRoomyInsets =
            labelWidth + iconSize + iconGap + 2 * roomyInset <=
            constraints.maxWidth;
        final iconWithTightInsets =
            labelWidth + iconSize + iconGap + 2 * tightInset <=
            constraints.maxWidth;
        final showIcon = iconWithRoomyInsets || iconWithTightInsets;
        final horizontalInset = iconWithRoomyInsets ||
                (!showIcon && labelWidth + 2 * roomyInset <= constraints.maxWidth)
            ? roomyInset
            : tightInset;

        return FilledButton.tonal(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalInset,
              vertical: 10,
            ),
            minimumSize: const Size(0, 40),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                Icon(icon, size: iconSize),
                SizedBox(width: iconGap),
              ],
              Text(label, maxLines: 1, softWrap: false),
            ],
          ),
        );
      },
    );
  }
}
