import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/feedback_page.dart';

void main() {
  testWidgets('feedback entry shows direct link actions and scannable poster', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FeedbackPage()));

    expect(feedbackFormUrl, 'https://v.wjx.cn/vm/YXtnlrL.aspx');
    expect(find.text('问题反馈'), findsOneWidget);
    expect(find.text('打开反馈问卷'), findsOneWidget);
    expect(find.text('保存反馈图片'), findsOneWidget);
    expect(find.text('复制反馈链接'), findsOneWidget);
    expect(find.byType(FeedbackPoster), findsOneWidget);

    await tester.tap(find.byType(FeedbackPoster));
    await tester.pumpAndSettle();

    expect(find.text('反馈图片'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
