import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/changelog/adventurer_news.dart';
import 'package:flutter_app/features/home/presentation/adventurer_news_dialog.dart';

void main() {
  const notice = AdventurerNewsNotice(
    previousBuild: 105,
    currentBuild: 110,
    entries: [
      AdventurerNewsEntry(
        introducedBuild: 107,
        title: '功能 A',
        description: '功能 A 的详细介绍。',
      ),
      AdventurerNewsEntry(
        introducedBuild: 110,
        title: '功能 B',
        description: '功能 B 的详细介绍。',
      ),
    ],
  );

  testWidgets('多版本见闻只用一个弹窗连续显示，无内部卡片', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () {
            showAdventurerNewsDialog(context, notice: notice);
          },
          child: const Text('open'),
        )),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.text('105 → 110 · 本次更新内容'), findsOneWidget);
    expect(find.text('功能 A'), findsOneWidget);
    expect(find.text('功能 A 的详细介绍。'), findsOneWidget);
    expect(find.text('v107'), findsOneWidget);
    expect(find.text('功能 B'), findsOneWidget);
    expect(find.text('功能 B 的详细介绍。'), findsOneWidget);
    expect(find.text('v110'), findsOneWidget);
    await tester.tap(find.text('我知道啦'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('窄屏仍能显示标题，且日志在同一弹窗内滚动', (tester) async {
    tester.view.physicalSize = const Size(350, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () {
            showAdventurerNewsDialog(context, notice: notice);
          },
          child: const Text('open'),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byType(Card), findsNothing);
  });
}
