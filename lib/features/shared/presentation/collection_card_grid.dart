import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'layout_spacing.dart';

class CollectionCardGrid extends StatelessWidget {
  const CollectionCardGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.mobileAspectRatio,
    required this.desktopMinHeight,
    this.desktopAspectRatio = 1,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double mobileAspectRatio;
  final double desktopMinHeight;
  final double desktopAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        const horizontalPadding = 24.0;
        // Base the grid on the actual content pane, not the whole desktop
        // window. The 320 px side navigation can otherwise leave four cards
        // squeezed into a phone-width pane. Use three columns in the middle
        // instead of jumping straight from a desktop grid to two huge cards.
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        final desktop = columns >= 3;
        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding -
                spacing * (columns - 1)) /
            columns;

        return GridView.builder(
          padding: AppLayoutSpacing.tabScrollPaddingWithFab(
            left: 12,
            top: 0,
            right: 12,
          ),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: mobileAspectRatio,
            mainAxisExtent: desktop
                ? math.max(cardWidth / desktopAspectRatio, desktopMinHeight)
                : null,
          ),
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
