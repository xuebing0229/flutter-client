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

    await tester.tap(find.byType(FeedbackPoster));
    await tester.pumpAndSettle();

    expect(find.text('反馈图片'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback poster renders against the effective theme in both modes', (
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
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
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
      final effectiveTheme = Theme.of(tester.element(find.byType(FeedbackPoster)));
      expect(background, effectiveTheme.colorScheme.surfaceContainerLow);
      expect(tester.takeException(), isNull);
      return background;
    }

    await mountPoster(Brightness.light);
    await mountPoster(Brightness.dark);
  });
}
