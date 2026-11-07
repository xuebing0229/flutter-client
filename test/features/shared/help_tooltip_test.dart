import 'package:flutter/material.dart';
import 'package:flutter_app/features/shared/presentation/help_tooltip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('InlineHelpTooltip shows its message on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: InlineHelpTooltip(message: '解释文字'),
          ),
        ),
      ),
    );

    expect(find.text('解释文字'), findsNothing);

    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('解释文字'), findsOneWidget);
  });
}
