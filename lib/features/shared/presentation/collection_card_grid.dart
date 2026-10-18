import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'layout_spacing.dart';

/// A lazy card grid that respects the desktop navigation pane.
///
/// By default cards keep their natural content height. Callers can opt into
/// equal-height rows when a visually aligned card wall is more appropriate.
class CollectionCardGrid extends StatelessWidget {
  const CollectionCardGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.mobileAspectRatio,
    required this.desktopMinHeight,
    this.desktopAspectRatio = 1,
    this.minimumCardWidth = 0,
    this.equalizeRowHeights = false,
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
  final bool equalizeRowHeights;

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
            final rowContent = equalizeRowHeights
                ? _EqualHeightRow(
                    spacing: spacing,
                    children: [
                      for (var column = 0; column < columns; column++)
                        first + column < itemCount
                            ? itemBuilder(context, first + column)
                            : const SizedBox.shrink(),
                    ],
                  )
                : Row(
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
                  );

            return Padding(
              padding: EdgeInsets.only(
                bottom: row == rows - 1 ? 0 : spacing,
              ),
              child: rowContent,
            );
          },
        );
      },
    );
  }
}

class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({
    required this.spacing,
    required super.children,
  });

  final double spacing;

  @override
  _RenderEqualHeightRow createRenderObject(BuildContext context) {
    return _RenderEqualHeightRow(spacing: spacing);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderEqualHeightRow renderObject,
  ) {
    renderObject.spacing = spacing;
  }
}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderEqualHeightRow({required double spacing}) : _spacing = spacing;

  double _spacing;

  double get spacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final columnWidth =
        (constraints.maxWidth - spacing * (childCount - 1)) / childCount;
    var rowHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      if (child.size.height > rowHeight) {
        rowHeight = child.size.height;
      }
      child = childAfter(child);
    }

    var column = 0;
    child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: columnWidth, height: rowHeight));
      final childParentData = child.parentData! as MultiChildLayoutParentData;
      childParentData.offset = Offset(column * (columnWidth + spacing), 0);
      column++;
      child = childParentData.nextSibling;
    }

    size = constraints.constrain(Size(constraints.maxWidth, rowHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
