import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'layout_spacing.dart';

typedef CollectionCardGridRowItemBuilder = Widget Function(
  BuildContext context,
  int index,
  List<int> rowIndices,
  double cardWidth,
);

/// A lazy card grid that respects the desktop navigation pane.
///
/// By default cards keep their natural content height. Callers can opt into
/// equal-height rows and, when needed, a row-aware builder that receives the
/// sibling indices and actual card width so corresponding fields can align
/// without hard-coding global heights.
class CollectionCardGrid extends StatelessWidget {
  const CollectionCardGrid({
    required this.itemCount,
    required this.mobileAspectRatio,
    required this.desktopMinHeight,
    this.itemBuilder,
    this.rowItemBuilder,
    this.desktopAspectRatio = 1,
    this.minimumCardWidth = 0,
    this.equalizeRowHeights = false,
    super.key,
  }) : assert(itemBuilder != null || rowItemBuilder != null);

  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final CollectionCardGridRowItemBuilder? rowItemBuilder;

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
        final cardWidth =
            (availableWidth - spacing * (columns - 1)) / columns;

        return ListView.builder(
          padding: AppLayoutSpacing.tabScrollPaddingWithFab(
            left: 12,
            top: 0,
            right: 12,
          ),
          itemCount: rows,
          itemBuilder: (context, row) {
            final first = row * columns;
            final count = math.min(columns, itemCount - first);
            final rowIndices = List<int>.generate(
              count,
              (offset) => first + offset,
              growable: false,
            );

            Widget buildItem(int index) {
              final rowBuilder = rowItemBuilder;
              if (rowBuilder != null) {
                return rowBuilder(context, index, rowIndices, cardWidth);
              }
              return itemBuilder!(context, index);
            }

            final rowContent = equalizeRowHeights
                ? _EqualHeightRow(
                    spacing: spacing,
                    children: [
                      for (var column = 0; column < columns; column++)
                        first + column < itemCount
                            ? buildItem(first + column)
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
                              ? buildItem(first + column)
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
      child.layout(
        BoxConstraints.tightFor(width: columnWidth, height: rowHeight),
      );
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
