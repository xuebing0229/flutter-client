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
    final desktop = MediaQuery.sizeOf(context).width >= 900;

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        const horizontalPadding = 24.0;
        final columns = desktop ? 4 : 2;
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
