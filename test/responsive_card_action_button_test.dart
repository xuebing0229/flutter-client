import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/shared/presentation/summary_card_widgets.dart';

void main() {
  Widget actionAtWidth(double width, {double fontSize = 24}) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        textTheme: TextTheme(labelLarge: TextStyle(fontSize: fontSize)),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ResponsiveCardActionButton(
              label: '确认节点',
              icon: Icons.check_circle_outline_rounded,
              onPressed: () {},
              compact: true,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('narrow card drops decorative icon, not text size or words', (
    tester,
  ) async {
    await tester.pumpWidget(actionAtWidth(110));

    final label = tester.widget<Text>(find.text('确认节点'));
    expect(label.maxLines, 1);
    expect(label.softWrap, false);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('roomy card keeps icon next to the single-line label', (
    tester,
  ) async {
    await tester.pumpWidget(actionAtWidth(250));

    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    final label = tester.widget<Text>(find.text('确认节点'));
    expect(label.maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
