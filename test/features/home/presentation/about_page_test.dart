import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/about_page.dart';

void main() {
  testWidgets('about page exposes version and open-source credits', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppAboutPage(version: '0.0.1', buildNumber: 167),
      ),
    );

    expect(find.widgetWithText(AppBar, '关于冒险者公会'), findsOneWidget);
    expect(find.text('版本 0.0.1 (167)'), findsOneWidget);
    expect(find.text('Syncthing'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();

    expect(find.text('VPet-Simulator.Core'), findsOneWidget);
    expect(find.textContaining('Apache License 2.0'), findsWidgets);
    expect(find.textContaining('不分发 VPet 自带角色动画资源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
