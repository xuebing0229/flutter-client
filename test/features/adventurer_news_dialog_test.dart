import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/changelog/adventurer_news.dart';
import 'package:flutter_app/features/home/presentation/adventurer_news_dialog.dart';

void main() {
  testWidgets('skipped versions render one continuous news block', (tester) async {
    final notice = AdventurerNewsNotice(
      previousBuild: 105,
      currentBuild: 108,
      entries: newsBetweenBuilds(105, 108),
    );
    bool? acknowledged;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                acknowledged = await showAdventurerNewsDialog(
                  context,
                  notice: notice,
                );
              },
              child: const Text('查看见闻'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看见闻'));
    await tester.pumpAndSettle();

    expect(find.text('105 → 108 · 本次新增 3 项'), findsOneWidget);
    expect(find.byKey(const ValueKey('adventurer-news-unified-content')),
        findsOneWidget);
    for (final entry in notice.entries) {
      expect(find.text(entry.description), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(entry.description),
          matching: find.byKey(
            const ValueKey('adventurer-news-unified-content'),
          ),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('版本 106'), findsNothing);
    expect(find.text('版本 107'), findsNothing);
    expect(find.text('版本 108'), findsNothing);

    await tester.tap(find.text('我知道啦'));
    await tester.pumpAndSettle();
    expect(acknowledged, isTrue);
  });

  testWidgets('one-build upgrade only lists unseen entries', (tester) async {
    final notice = AdventurerNewsNotice(
      previousBuild: 107,
      currentBuild: 108,
      entries: newsBetweenBuilds(107, 108),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdventurerNewsDialog(
                context,
                notice: notice,
              ),
              child: const Text('查看'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();

    expect(find.text('107 → 108 · 本次新增 1 项'), findsOneWidget);
    expect(find.text('新见闻阅读优化'), findsOneWidget);
    expect(find.text('截图识别批量导入'), findsNothing);
  });
}
