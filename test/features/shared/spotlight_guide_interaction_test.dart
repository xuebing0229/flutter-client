import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/shared/presentation/spotlight_guide.dart';

void main() {
  testWidgets(
      'guide waits for target that mounts on the next frame instead of dropping it',
      (tester) async {
    final targetKey = GlobalKey();
    var showTarget = false;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return Column(
                    children: [
                      if (showTarget)
                        SpotlightTarget(
                          targetKey: targetKey,
                          child: const SizedBox(
                            width: 220,
                            height: 56,
                            child: ColoredBox(color: Colors.white),
                          ),
                        ),
                      FilledButton(
                        onPressed: () {
                          setHostState(() => showTarget = true);
                          showSpotlightGuide(
                            context,
                            steps: [
                              SpotlightGuideStep(
                                targetKey: targetKey,
                                icon: Icons.web_rounded,
                                title: '晚一帧出现的目标',
                                body: 'Web 路由或懒布局晚挂载时也不能丢掉这一步。',
                              ),
                            ],
                          );
                        },
                        child: const Text('打开延迟目标引导'),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开延迟目标引导'));
    // The resolver may wait a few frames for a Web route/lazy child to attach,
    // then the overlay itself needs one more frame to build.
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
    }

    expect(find.text('晚一帧出现的目标'), findsOneWidget);
    expect(find.byKey(targetKey), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
  });

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
                                  compactWhenTargetRouteCovered: true,
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

    final compactGuideCard = find
        .ancestor(
          of: find.text('选择平台'),
          matching: find.byType(Card),
        )
        .first;
    final compactGuideRect = tester.getRect(compactGuideCard);
    final optionRect = tester.getRect(find.text('画加').last);
    expect(compactGuideRect.overlaps(optionRect), isFalse);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('退出教程'), findsOneWidget);

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




  testWidgets('guide card never overlaps highlighted target when space is tight',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 330),
                  SpotlightTarget(
                    targetKey: targetKey,
                    child: const SizedBox(
                      width: 280,
                      height: 56,
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
                            targetKey: targetKey,
                            icon: Icons.account_tree_outlined,
                            title: '很长的教程说明',
                            body:
                                '这是一段故意写得很长的教程正文，用来模拟小屏幕上教程卡片高度超过高亮上方安全区域的情况。'
                                '教程卡片必须被限制在高亮区域之外，正文装不下时只能在卡片内部滚动，不能压住当前高亮。'
                                '这是一段故意写得很长的教程正文，用来继续撑高卡片，确保测试真的覆盖空间不足的情况。'
                                '即使按钮、进度和说明一起变得很高，也必须继续遵守不覆盖高亮区域的规则。',
                            targetPadding: 0,
                            borderRadius: 0,
                          ),
                        ],
                      );
                    },
                    child: const Text('打开长教程'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开长教程'));
    await tester.pump();
    await tester.pump();

    final targetRect = tester.getRect(find.byKey(targetKey));
    final guideCard = find
        .ancestor(
          of: find.text('很长的教程说明'),
          matching: find.byType(Card),
        )
        .first;
    final guideRect = tester.getRect(guideCard);

    expect(guideRect.overlaps(targetRect), isFalse);
    expect(guideRect.bottom, lessThanOrEqualTo(targetRect.top - 15));

    final exitRect = tester.getRect(find.text('退出教程'));
    final nextRect = tester.getRect(find.text('开始使用'));
    expect(exitRect.top, greaterThanOrEqualTo(guideRect.top));
    expect(exitRect.bottom, lessThanOrEqualTo(guideRect.bottom));
    expect(nextRect.top, greaterThanOrEqualTo(guideRect.top));
    expect(nextRect.bottom, lessThanOrEqualTo(guideRect.bottom));

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
  });


  testWidgets(
      'nested desktop overlay uses local coordinates instead of window coordinates',
      (tester) async {
    final targetKey = GlobalKey();
    final paneKey = GlobalKey();
    var targetTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 220),
              Expanded(
                key: paneKey,
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (context) {
                      return Scaffold(
                        body: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SpotlightTarget(
                                targetKey: targetKey,
                                child: SizedBox(
                                  width: 320,
                                  height: 56,
                                  child: FilledButton(
                                    onPressed: () => targetTapCount += 1,
                                    child: const Text('桌面目标'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                              FilledButton(
                                onPressed: () {
                                  showSpotlightGuide(
                                    context,
                                    steps: [
                                      SpotlightGuideStep(
                                        targetKey: targetKey,
                                        icon: Icons.title_rounded,
                                        title: '桌面坐标测试',
                                        body: '高亮必须和右侧工作区里的真实控件完全对齐。',
                                        targetPadding: 0,
                                        borderRadius: 0,
                                      ),
                                    ],
                                  );
                                },
                                child: const Text('打开桌面引导'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开桌面引导'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('桌面目标'));
    await tester.pump();
    expect(targetTapCount, 1);

    final paneRect = tester.getRect(find.byKey(paneKey));
    final guideCard = find
        .ancestor(
          of: find.text('桌面坐标测试'),
          matching: find.byType(Card),
        )
        .first;
    final guideRect = tester.getRect(guideCard);
    expect(guideRect.left, greaterThanOrEqualTo(paneRect.left));
    expect(guideRect.right, lessThanOrEqualTo(paneRect.right));

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
  });


  testWidgets('offscreen spotlight target is revealed before guide is shown',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 900),
                    SpotlightTarget(
                      targetKey: targetKey,
                      child: const SizedBox(
                        width: 300,
                        height: 120,
                        child: ColoredBox(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 500),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () {
                  showSpotlightGuide(
                    context,
                    steps: [
                      SpotlightGuideStep(
                        targetKey: targetKey,
                        icon: Icons.inventory_2_outlined,
                        title: '屏幕外的备份卡',
                        body: '开始介绍前应先把目标自动滚进屏幕。',
                        targetPadding: 0,
                      ),
                    ],
                  );
                },
                child: const Icon(Icons.play_arrow_rounded),
              ),
            );
          },
        ),
      ),
    );

    expect(tester.getRect(find.byKey(targetKey)).top, greaterThan(600));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final targetRect = tester.getRect(find.byKey(targetKey));
    expect(targetRect.top, greaterThanOrEqualTo(0));
    expect(targetRect.bottom, lessThanOrEqualTo(600));

    final guideCard = find
        .ancestor(
          of: find.text('屏幕外的备份卡'),
          matching: find.byType(Card),
        )
        .first;
    expect(tester.getRect(guideCard).overlaps(targetRect), isFalse);

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
