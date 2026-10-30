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

  test('130 向 129 用户补充桌宠布局与专注体验完善见闻', () {
    final picked = newsBetweenBuilds(129, 130);
    expect(picked.map((e) => e.title).toList(), ['桌宠布局与专注体验完善']);
  });

  test('131 向 130 用户补充桌宠定位与主题跟随修复见闻', () {
    final picked = newsBetweenBuilds(130, 131);
    expect(picked.map((e) => e.title).toList(), ['桌宠定位与主题跟随修复']);
  });

  test('132 向 131 用户补充竖排气泡排版修复见闻', () {
    final picked = newsBetweenBuilds(131, 132);
    expect(picked.map((e) => e.title).toList(), ['竖排气泡排版修复']);
  });

  test('133 向 132 用户补充本轮专注参考图与 Windows OCR 见闻', () {
    final picked = newsBetweenBuilds(132, 133);
    expect(
      picked.map((e) => e.title).toList(),
      ['专注、参考图与 Windows 截图识别升级'],
    );
  });

  test('135 包含内测前稳定性完善见闻', () {
    final picked = newsBetweenBuilds(134, 135);
    expect(picked.map((e) => e.title).toList(), ['内测前稳定性完善']);
  });

  test('142 包含本轮内测回归清理见闻', () {
    final picked = newsBetweenBuilds(141, 142);
    expect(picked.map((e) => e.title).toList(), ['内测回归继续清理']);
  });

  test('143 包含桌宠素材保护修复见闻', () {
    final picked = newsBetweenBuilds(142, 143);
    expect(picked.map((e) => e.title).toList(), ['桌宠素材保护修复']);
  });

  test('145 包含新设备加入状态修复见闻', () {
    final picked = newsBetweenBuilds(144, 145);
    expect(picked.map((e) => e.title).toList(), ['新设备加入状态修复']);
  });

  test('146 包含 UI 质感见闻', () {
    final picked = newsBetweenBuilds(145, 146);
    expect(picked.map((e) => e.title).toList(), ['UI 质感：毛玻璃与液态玻璃']);
  });

  test('147 包含 UI 质感重新打磨见闻', () {
    final picked = newsBetweenBuilds(146, 147);
    expect(picked.map((e) => e.title).toList(), ['UI 质感重新打磨']);
  });

  test('148 包含十二种 UI 风格见闻', () {
    final picked = newsBetweenBuilds(147, 148);
    expect(picked.map((e) => e.title).toList(), ['十二种 UI 风格']);
  });


  test('149 包含 UI 风格质感重做见闻', () {
    final picked = newsBetweenBuilds(148, 149);
    expect(picked.map((e) => e.title).toList(), ['UI 风格质感重做']);
  });


  test('150 包含 UI 风格明暗与组件统一修复见闻', () {
    final picked = newsBetweenBuilds(149, 150);
    expect(
      picked.map((e) => e.title).toList(),
      ['UI 风格明暗与组件统一修复'],
    );
  });

  test('182 包含电池优化设置修复见闻', () {
    final picked = newsBetweenBuilds(181, 182);
    expect(picked.map((e) => e.title).toList(), ['电池优化设置修复']);
  });

  test('183 包含网页版设备同步支持见闻', () {
    final picked = newsBetweenBuilds(182, 183);
    expect(picked.map((e) => e.title).toList(), ['网页版设备同步支持']);
  });

  test('191 包含重装后重新加入设备修复见闻', () {
    final picked = newsBetweenBuilds(190, 191);
    expect(picked.map((e) => e.title).toList(), ['重装后重新加入设备修复']);
  });

  test('192 包含新设备回应码显示修复见闻', () {
    final picked = newsBetweenBuilds(191, 192);
    expect(picked.map((e) => e.title).toList(), ['新设备回应码显示修复']);
  });

  test('193 包含电脑确认回应码卡死修复见闻', () {
    final picked = newsBetweenBuilds(192, 193);
    expect(picked.map((e) => e.title).toList(), ['电脑确认回应码卡死修复']);
  });

  test('195 包含卸载后重新加入设备修复见闻', () {
    final picked = newsBetweenBuilds(194, 195);
    expect(picked.map((e) => e.title).toList(), ['卸载后重新加入设备修复']);
  });

  test('196 包含临时账号目录卡死修复见闻', () {
    final picked = newsBetweenBuilds(195, 196);
    expect(picked.map((e) => e.title).toList(), ['临时账号目录卡死修复']);
  });

  test('197 包含 Windows 设备同步自愈见闻', () {
    final picked = newsBetweenBuilds(196, 197);
    expect(picked.map((e) => e.title).toList(), ['Windows 设备同步自愈']);
  });

  test('198 包含回应码确认前状态修复见闻', () {
    final picked = newsBetweenBuilds(197, 198);
    expect(picked.map((e) => e.title).toList(), ['回应码确认前状态修复']);
  });

  test('200 包含设备加入诊断版见闻', () {
    final picked = newsBetweenBuilds(199, 200);
    expect(picked.map((e) => e.title).toList(), ['设备加入诊断版']);
  });

  test('201 包含 Android 新设备加入后台切换修复见闻', () {
    final picked = newsBetweenBuilds(200, 201);
    expect(
      picked.map((e) => e.title).toList(),
      ['Android 新设备加入后台切换修复'],
    );
  });

  test('202 包含截图识别结构化回归修复见闻', () {
    final picked = newsBetweenBuilds(201, 202);
    expect(
      picked.map((e) => e.title).toList(),
      ['截图识别结构化回归修复'],
    );
  });

  test('203 包含截图导入类型误选保护见闻', () {
    final picked = newsBetweenBuilds(202, 203);
    expect(
      picked.map((e) => e.title).toList(),
      ['截图导入类型误选保护'],
    );
  });

  test('204 包含成品总概览与小票预设分享见闻', () {
    final picked = newsBetweenBuilds(203, 204);
    expect(
      picked.map((e) => e.title).toList(),
      ['成品总概览与小票预设分享'],
    );
  });

  test('211 包含快速上手引导与小票恢复完善见闻', () {
    final picked = newsBetweenBuilds(210, 211);
    expect(
      picked.map((e) => e.title).toList(),
      ['快速上手引导与小票恢复完善'],
    );
  });

  test('212 包含完整新手引导见闻', () {
    final picked = newsBetweenBuilds(211, 212);
    expect(
      picked.map((e) => e.title).toList(),
      ['完整新手引导'],
    );
  });
}
