import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/shared/presentation/collection_card_grid.dart';

void main() {
  Widget harness(double paneWidth) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: paneWidth,
            height: 700,
            child: CollectionCardGrid(
              itemCount: 8,
              mobileAspectRatio: 0.5,
              desktopMinHeight: 260,
              desktopAspectRatio: 1.1,
              itemBuilder: (_, index) => Text('item-$index'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('uses two columns when the desktop content pane is narrow', (
    tester,
  ) async {
    await tester.pumpWidget(harness(580));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, isNull);
  });

  testWidgets('uses four columns when the content pane itself is wide', (
    tester,
  ) async {
    await tester.pumpWidget(harness(920));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 4);
    expect(delegate.mainAxisExtent, isNotNull);
  });

  testWidgets('uses three columns for a medium desktop content pane', (
    tester,
  ) async {
    await tester.pumpWidget(harness(760));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 3);
    expect(delegate.mainAxisExtent, isNotNull);
  });

}
