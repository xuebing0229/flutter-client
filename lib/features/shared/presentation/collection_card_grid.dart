import 'package:flutter/material.dart';

import 'layout_spacing.dart';

/// A lazy, content-height card grid that respects the desktop navigation pane.
///
/// Every card takes only the vertical space needed by its actual text and
/// controls. The next row begins after the tallest card in the current row.
class CollectionCardGrid extends StatelessWidget {
  const CollectionCardGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.mobileAspectRatio,
    required this.desktopMinHeight,
    this.desktopAspectRatio = 1,
    this.minimumCardWidth = 0,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  // Kept temporarily for call-site compatibility; card height now follows
  // content instead of these fixed-height sizing hints.
  final double mobileAspectRatio;
  final double desktopMinHeight;
  final double desktopAspectRatio;
  final double minimumCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        const horizontalPadding = 24.0;
        final availableWidth = constraints.maxWidth - horizontalPadding;
        final idealColumns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : constraints.maxWidth < 320
            ? 1
            : 2;
        var columns = idealColumns;
        while (columns > 1 &&
            (availableWidth - spacing * (columns - 1)) / columns <
                minimumCardWidth) {
          columns--;
        }
        final rows = (itemCount + columns - 1) ~/ columns;

        return ListView.builder(
          padding: AppLayoutSpacing.tabScrollPaddingWithFab(
            left: 12,
            top: 0,
            right: 12,
          ),
          itemCount: rows,
          itemBuilder: (context, row) {
            final first = row * columns;
            return Padding(
              padding: EdgeInsets.only(
                bottom: row == rows - 1 ? 0 : spacing,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column != 0) const SizedBox(width: spacing),
                    Expanded(
                      child: first + column < itemCount
                          ? itemBuilder(context, first + column)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
