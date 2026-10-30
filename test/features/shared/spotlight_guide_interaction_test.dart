import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/shared/presentation/spotlight_guide.dart';

void main() {
  testWidgets('highlighted text field remains interactive through guide hole',
      (tester) async {
    final targetKey = GlobalKey();
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    SpotlightTarget(
                      targetKey: targetKey,
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: '图名',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        showSpotlightGuide(
                          context,
                          steps: [
                            SpotlightGuideStep(
                              targetKey: targetKey,
                              icon: Icons.title_rounded,
                              title: '填写图名',
                              body: '直接点高亮输入框填写。',
                              targetPadding: 0,
                              borderRadius: 0,
                            ),
                          ],
                        );
                      },
                      child: const Text('打开引导'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开引导'));
    await tester.pump();

    expect(find.text('填写图名'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '测试标题');
    await tester.pump();

    expect(controller.text, '测试标题');
    expect(find.text('填写图名'), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    controller.dispose();
  });

  testWidgets('dimmed area remains blocked while guide is open',
      (tester) async {
    final targetKey = GlobalKey();
    var outsideTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    SpotlightTarget(
                      targetKey: targetKey,
                      child: const SizedBox(
                        width: 180,
                        height: 48,
                        child: ColoredBox(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 120),
                    FilledButton(
                      onPressed: () => outsideTapCount += 1,
                      child: const Text('暗区按钮'),
                    ),
                    FilledButton(
                      onPressed: () {
                        showSpotlightGuide(
                          context,
                          steps: [
                            SpotlightGuideStep(
                              targetKey: targetKey,
                              icon: Icons.touch_app_outlined,
                              title: '只允许目标交互',
                              body: '暗区仍应拦截点击。',
                              targetPadding: 0,
                              borderRadius: 0,
                            ),
                          ],
                        );
                      },
                      child: const Text('打开引导'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开引导'));
    await tester.pump();

    await tester.tap(find.text('暗区按钮'), warnIfMissed: false);
    await tester.pump();

    expect(outsideTapCount, 0);

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
  });


  testWidgets(
      'dropdown popup stays interactive and closes before moving guide step',
      (tester) async {
    final dropdownKey = GlobalKey();
    final secondKey = GlobalKey();
    var selected = '米画师';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 260),
                        SpotlightTarget(
                          targetKey: dropdownKey,
                          child: DropdownButtonFormField<String>(
                            initialValue: selected,
                            items: const [
                              DropdownMenuItem(
                                value: '米画师',
                                child: Text('米画师'),
                              ),
                              DropdownMenuItem(
                                value: '画加',
                                child: Text('画加'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => selected = value);
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        SpotlightTarget(
                          targetKey: secondKey,
                          child: const SizedBox(
                            width: 180,
                            height: 48,
                            child: ColoredBox(color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            showSpotlightGuide(
                              context,
                              steps: [
                                SpotlightGuideStep(
                                  targetKey: dropdownKey,
                                  icon: Icons.storefront_outlined,
                                  title: '选择平台',
                                  body: '下拉菜单应保持可操作。',
                                  targetPadding: 0,
                                  borderRadius: 0,
                                  preferCardAbove: true,
                                  allowOutsideTargetInteraction: true,
                                ),
                                SpotlightGuideStep(
                                  targetKey: secondKey,
                                  icon: Icons.payments_outlined,
                                  title: '第二步',
                                  body: '切换步骤前应先收起下拉菜单。',
                                  targetPadding: 0,
                                  borderRadius: 0,
                                ),
                              ],
                            );
                          },
                          child: const Text('打开下拉引导'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开下拉引导'));
    await tester.pump();
    await tester.pump();

    final dropdownRect = tester.getRect(
      find.byType(DropdownButtonFormField<String>),
    );
    final guideCardRect = tester.getRect(find.byType(Card));
    expect(guideCardRect.bottom, lessThanOrEqualTo(dropdownRect.top));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(ModalRoute.of(dropdownKey.currentContext!)!.isCurrent, isFalse);

    await tester.tap(find.text('画加').last);
    await tester.pumpAndSettle();

    expect(selected, '画加');
    expect(ModalRoute.of(dropdownKey.currentContext!)!.isCurrent, isTrue);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(ModalRoute.of(dropdownKey.currentContext!)!.isCurrent, isFalse);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('第二步'), findsOneWidget);
    expect(ModalRoute.of(dropdownKey.currentContext!)!.isCurrent, isTrue);

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
  });



  testWidgets('group progress is continuous and single steps hide 1 / 1',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  SpotlightTarget(
                    targetKey: targetKey,
                    child: const SizedBox(width: 160, height: 48),
                  ),
                  FilledButton(
                    onPressed: () {
                      showSpotlightGuide(
                        context,
                        progressStart: 1,
                        progressTotal: 3,
                        steps: [
                          SpotlightGuideStep(
                            targetKey: targetKey,
                            icon: Icons.calendar_month_outlined,
                            title: '分组步骤',
                            body: '显示跨页面连续进度。',
                          ),
                        ],
                      );
                    },
                    child: const Text('打开分组引导'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开分组引导'));
    await tester.pump();
    await tester.pump();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('退出教程'), findsOneWidget);
    expect(find.text('跳过本节'), findsOneWidget);

    await tester.tap(find.text('退出教程'));
    await tester.pumpAndSettle();
  });



  testWidgets('single-step spotlight does not show 1 / 1', (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  SpotlightTarget(
                    targetKey: targetKey,
                    child: const SizedBox(width: 160, height: 48),
                  ),
                  FilledButton(
                    onPressed: () {
                      showSpotlightGuide(
                        context,
                        steps: [
                          SpotlightGuideStep(
                            targetKey: targetKey,
                            icon: Icons.info_outline,
                            title: '单步介绍',
                            body: '单步不需要显示 1 / 1。',
                          ),
                        ],
                      );
                    },
                    child: const Text('打开单步引导'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开单步引导'));
    await tester.pump();
    await tester.pump();

    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('退出教程'), findsOneWidget);

    await tester.tap(find.text('退出教程'));
    await tester.pumpAndSettle();
  });



  testWidgets('skip section completes current spotlight without exiting flow',
      (tester) async {
    final targetKey = GlobalKey();
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  SpotlightTarget(
                    targetKey: targetKey,
                    child: const SizedBox(width: 160, height: 48),
                  ),
                  FilledButton(
                    onPressed: () async {
                      result = await showSpotlightGuide(
                        context,
                        steps: [
                          SpotlightGuideStep(
                            targetKey: targetKey,
                            icon: Icons.info_outline,
                            title: '当前小节',
                            body: '用于测试跳过本节。',
                          ),
                        ],
                      );
                    },
                    child: const Text('打开可跳过小节'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开可跳过小节'));
    await tester.pump();
    await tester.pump();

    expect(find.text('跳过本节'), findsOneWidget);
    expect(find.text('退出教程'), findsOneWidget);

    await tester.tap(find.text('跳过本节'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

}
