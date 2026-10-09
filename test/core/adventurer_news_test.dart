import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/changelog/adventurer_news.dart';

void main() {
  const entries = <AdventurerNewsEntry>[
    AdventurerNewsEntry(introducedBuild: 110, title: '功能 B', description: 'B'),
    AdventurerNewsEntry(introducedBuild: 107, title: '功能 A', description: 'A'),
    AdventurerNewsEntry(introducedBuild: 110, title: '110 修复', description: 'C'),
    AdventurerNewsEntry(introducedBuild: 112, title: '未来功能', description: 'D'),
  ];

  test('105 直升 110：应看到 A + B 和本版修复', () {
    final picked = newsBetweenBuilds(105, 110, catalog: entries);
    expect(picked.map((e) => e.title).toList(), ['功能 A', '功能 B', '110 修复']);
  });

  test('107 升到 110：不重复提示已经读过的 A', () {
    final picked = newsBetweenBuilds(107, 110, catalog: entries);
    expect(picked.map((e) => e.title).toList(), ['功能 B', '110 修复']);
  });

  test('105 升 107：只显示 A', () {
    final picked = newsBetweenBuilds(105, 107, catalog: entries);
    expect(picked.map((e) => e.title).toList(), ['功能 A']);
  });

  test('同版本重启或者回退版本不会重新弹出', () {
    expect(newsBetweenBuilds(110, 110, catalog: entries), isEmpty);
    expect(newsBetweenBuilds(110, 107, catalog: entries), isEmpty);
  });

  test('不会将未来的见闻提前透露，也不会漏掉同版多条', () {
    final picked = newsBetweenBuilds(107, 110, catalog: entries);
    expect(picked.length, 2);
    expect(picked.every((e) => e.introducedBuild == 110), isTrue);
  });

  test('106 的截图导入与 107 的新见闻按版本累加', () {
    expect(newsBetweenBuilds(105, 106).single.title, '截图识别批量导入');
    expect(newsBetweenBuilds(106, 107).single.title, '冒险者新见闻');
    expect(newsBetweenBuilds(105, 107).length, 2);
  });

  test('124 包含本轮截图识别导入优化', () {
    final picked = newsBetweenBuilds(121, 124);
    expect(picked.map((e) => e.title), contains('截图识别导入优化'));
  });

  test('125 向 124 用户补充同步恢复见闻', () {
    final picked = newsBetweenBuilds(124, 125);
    expect(picked.map((e) => e.title), contains('设备同步恢复与前台自动连接'));
  });

  test('126 向 125 用户补充 Windows 桌宠见闻', () {
    final picked = newsBetweenBuilds(125, 126);
    expect(picked.map((e) => e.title).toList(), ['Windows 桌宠']);
  });

  test('127 向 126 用户补充专注计时见闻', () {
    final picked = newsBetweenBuilds(126, 127);
    expect(picked.map((e) => e.title).toList(), ['专注计时']);
  });

  test('129 向 128 用户补充桌宠与专注整合见闻', () {
    final picked = newsBetweenBuilds(128, 129);
    expect(picked.map((e) => e.title).toList(), ['桌宠与专注整合完善']);
  });
}
