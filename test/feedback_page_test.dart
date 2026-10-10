import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_app/features/home/presentation/feedback_page.dart';

void main() {
  testWidgets('feedback page opens the full-size themed QR card', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FeedbackPage()));

    expect(feedbackFormUrl, 'https://v.wjx.cn/vm/YXtnlrL.aspx');
    expect(find.widgetWithText(AppBar, '问题反馈'), findsOneWidget);
    expect(find.byType(FeedbackPoster), findsOneWidget);

    // Buttons appear below the poster on the default 800x600 test viewport.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('打开反馈问卷'), findsOneWidget);
    expect(find.text('保存反馈图片'), findsOneWidget);
    expect(find.text('复制反馈链接'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FeedbackPoster));
    await tester.pumpAndSettle();

    expect(find.text('反馈图片'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR value stays exactly the same in both theme modes', (
    tester,
  ) async {
    Future<Color> mountPoster(Brightness brightness) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(child: FeedbackPoster()),
          ),
        ),
      );
      // MaterialApp animates ThemeData changes; read the settled theme.
      await tester.pumpAndSettle();
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.data, feedbackFormUrl);
      expect(qr.backgroundColor, Colors.white);
      expect(tester.getSize(find.byType(FeedbackPoster)),
          const Size(360, 488));
      final outer = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(FeedbackPoster),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final background = (outer.decoration as BoxDecoration).color!;
      expect(background, theme.colorScheme.surfaceContainerLow);
      expect(tester.takeException(), isNull);
      return background;
    }

    final light = await mountPoster(Brightness.light);
    final dark = await mountPoster(Brightness.dark);
    expect(light, isNot(dark));
  });
}
