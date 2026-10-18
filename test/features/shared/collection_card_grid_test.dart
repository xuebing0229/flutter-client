import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/shared/presentation/collection_card_grid.dart';

void main() {
  Widget harness(
    double paneWidth, {
    double minimumCardWidth = 0,
    bool equalizeRowHeights = false,
  }) {
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
              minimumCardWidth: minimumCardWidth,
              equalizeRowHeights: equalizeRowHeights,
              itemBuilder: (_, index) => SizedBox(
                key: Key('item-$index'),
                height: index.isEven ? 80 : 140,
                child: Text('item-$index'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('two-column rows keep individual card heights', (tester) async {
    await tester.pumpWidget(harness(580));
    expect(tester.getSize(find.byKey(const Key('item-0'))).height, 80);
    expect(tester.getSize(find.byKey(const Key('item-1'))).height, 140);
    expect(tester.getTopLeft(find.byKey(const Key('item-0'))).dy,
        tester.getTopLeft(find.byKey(const Key('item-1'))).dy);
    expect(tester.getTopLeft(find.byKey(const Key('item-2'))).dy,
        tester.getBottomLeft(find.byKey(const Key('item-1'))).dy + 10);
  });


  testWidgets('can equalize card heights inside the same row', (tester) async {
    await tester.pumpWidget(harness(580, equalizeRowHeights: true));
    expect(tester.getSize(find.byKey(const Key('item-0'))).height, 140);
    expect(tester.getSize(find.byKey(const Key('item-1'))).height, 140);
    expect(
      tester.getTopLeft(find.byKey(const Key('item-2'))).dy,
      tester.getBottomLeft(find.byKey(const Key('item-0'))).dy + 10,
    );
  });

  testWidgets('row-aware builder receives sibling indices and card width',
      (tester) async {
    final seenRows = <List<int>>[];
    final seenWidths = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 580,
            height: 700,
            child: CollectionCardGrid(
              itemCount: 4,
              mobileAspectRatio: 0.5,
              desktopMinHeight: 260,
              rowItemBuilder: (_, index, rowIndices, cardWidth) {
                if (index == rowIndices.first) {
                  seenRows.add(List<int>.from(rowIndices));
                  seenWidths.add(cardWidth);
                }
                return SizedBox(height: 80, child: Text('row-aware-$index'));
              },
            ),
          ),
        ),
      ),
    );

    expect(seenRows, <List<int>>[
      <int>[0, 1],
      <int>[2, 3],
    ]);
    expect(seenWidths.every((width) => width > 250), isTrue);
  });

  testWidgets('wide content pane uses four columns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(920));
    for (var index = 0; index < 4; index++) {
      expect(tester.getTopLeft(find.byKey(Key('item-$index'))).dy,
          tester.getTopLeft(find.byKey(const Key('item-0'))).dy);
    }
    expect(tester.getTopLeft(find.byKey(const Key('item-4'))).dy,
        tester.getBottomLeft(find.byKey(const Key('item-1'))).dy + 10);
  });

  testWidgets('medium content pane uses three columns', (tester) async {
    await tester.pumpWidget(harness(760));
    expect(tester.getTopLeft(find.byKey(const Key('item-2'))).dy,
        tester.getTopLeft(find.byKey(const Key('item-0'))).dy);
    expect(tester.getTopLeft(find.byKey(const Key('item-3'))).dy,
        tester.getBottomLeft(find.byKey(const Key('item-1'))).dy + 10);
  });

  testWidgets('respects minimum space needed by large card controls',
      (tester) async {
    await tester.pumpWidget(harness(360, minimumCardWidth: 300));
    expect(tester.getTopLeft(find.byKey(const Key('item-1'))).dy,
        tester.getBottomLeft(find.byKey(const Key('item-0'))).dy + 10);
  });
}
