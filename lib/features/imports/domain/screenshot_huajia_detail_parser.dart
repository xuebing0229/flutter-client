import 'dart:math' as math;

import 'screenshot_layout_parser.dart';

/// Huajia's order detail layout is different from MiHuashi's: a dark header
/// shows seller/client, a cover card shows title, fee and the real deadline,
/// and the lower "稿件 / 订单动态 / 改价历史 / 参考信息" tabs contain
/// attachment timestamps which must NEVER create extra orders.
///
/// Generic labels ("订单", "稿件", "参考信息") are not platform signals.
bool isHuajiaOrderDetailScreenshot({
  required Iterable<ScreenshotTextLine> lines,
  required double imageWidth,
  required double imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return false;
  final visible = lines.toList();
  final text = visible.map((line) => line.text).join(' ');
  if (text.contains('我卖出的') ||
      text.contains('稿件夹') ||
      text.contains('联系企划方') ||
      text.contains('上传稿件') ||
      text.contains('进程动态')) {
    return false;
  }
  final status = visible.any((line) =>
      line.centerY < imageHeight * 0.17 &&
      (line.text.contains('订单已完成') ||
          line.text.contains('订单进行中') ||
          line.text.contains('订单已取消') ||
          line.text.contains('订单已中断')));
  final history = text.contains('改价历史');
  final movement = text.contains('订单动态');
  final huajiaBadge = text.contains('真爱永恒');
  final tabs = visible.any((line) =>
      line.centerY > imageHeight * 0.26 &&
      line.centerY < imageHeight * 0.64 &&
      RegExp(r'稿件\s*\d+|稿件[0-9]+').hasMatch(line.text));
  // Two distinctive Huajia detail traits + the order status, or both
  // platform-specific tabs together with the files tab.
  return (status && (history || movement || huajiaBadge) &&
          (history || movement || tabs || huajiaBadge)) ||
      (history && movement && tabs);
}

class ScreenshotHuajiaDetailParser {
  const ScreenshotHuajiaDetailParser();

  static final _date = RegExp(
      r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?'
      r'(?:\s+(\d{1,2}):(\d{2}))?');
  static final _money = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  static final _node = RegExp(r'(\d{1,3})\s*%');
  static final _image = RegExp(r'\.(?:png|jpe?g|webp)\b', caseSensitive: false);

  List<ScreenshotOrderCandidate> parse({
    required List<ScreenshotTextLine> lines,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (!isHuajiaOrderDetailScreenshot(
      lines: lines, imageWidth: imageWidth, imageHeight: imageHeight,
    )) {
      return const [];
    }
    final prepared = [...lines]
      ..sort((a, b) {
        final y = a.centerY.compareTo(b.centerY);
        return y != 0 ? y : a.left.compareTo(b.left);
      });
    final tabs = prepared.where((line) =>
        line.centerY > imageHeight * 0.26 &&
        line.centerY < imageHeight * 0.68 &&
        RegExp(r'订单动态|改价历史|参考信息|稿件\s*\d+')
            .hasMatch(line.text)).toList();
    final tabY = tabs.isEmpty
        ? imageHeight * 0.47
        : tabs.map((line) => line.centerY).reduce(math.min);
    final contentBottom = math.min(tabY - 12, imageHeight * 0.48);

    // Only a date in the cover card can be a deadline. Upload timestamps
    // from the files tab below tabY are deliberately invisible to this step.
    final dates = <(ScreenshotTextLine, DateTime, bool)>[];
    for (final line in prepared) {
      if (line.centerY <= imageHeight * 0.19 ||
          line.centerY >= contentBottom) continue;
      final match = _date.firstMatch(line.text);
      if (match == null) continue;
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.tryParse(match.group(4) ?? '') ?? 0;
      final minute = int.tryParse(match.group(5) ?? '') ?? 0;
      if (month < 1 || month > 12 || day < 1 || day > 31 ||
          hour > 23 || minute > 59) continue;
      final date = DateTime(year, month, day, hour, minute);
      if (date.year != year || date.month != month || date.day != day) {
        continue;
      }
      dates.add((line, date, match.group(4) != null));
    }
    dates.sort((a, b) {
      final aScore = a.$1.text.contains('截稿') ? 0 : 1;
      final bScore = b.$1.text.contains('截稿') ? 0 : 1;
      final status = aScore.compareTo(bScore);
      return status != 0 ? status : b.$1.centerY.compareTo(a.$1.centerY);
    });
    final deadline = dates.isEmpty ? null : dates.first;
    final dateY = deadline?.$1.centerY ?? contentBottom;

    final candidates = prepared.where((line) {
      final text = line.text.trim();
      return line.centerY > imageHeight * 0.18 &&
          line.centerY < dateY - 11 &&
          line.left > imageWidth * 0.23 &&
          text.length >= 2 &&
          !_money.hasMatch(text) &&
          !_date.hasMatch(text) &&
          !_node.hasMatch(text) &&
          !_image.hasMatch(text) &&
          !text.contains('截稿') &&
          !text.contains('真爱永恒') &&
          !text.contains('已实名') &&
          !text.contains('订单') &&
          !text.contains('稿件') &&
          !text.contains('历史') &&
          !text.contains('参考信息') &&
          !text.contains('Lv1') &&
          !RegExp(r'^[¥￥]?\d+(?:\.\d+)?$').hasMatch(text);
    }).toList()
      ..sort((a, b) => b.centerY.compareTo(a.centerY));
    final title = candidates.isEmpty ? null : candidates.first;

    // Buyer is on the seller row, above the artwork card. The identity
    // badge and the "真爱永恒 Lv1" perk aren't customer names.
    final titleY = title?.centerY ?? imageHeight * 0.24;
    final buyers = prepared.where((line) {
      final text = line.text.trim();
      return line.centerY > imageHeight * 0.12 &&
          line.centerY < math.min(titleY - 25, imageHeight * 0.255) &&
          line.left < imageWidth * 0.37 &&
          text.length >= 2 &&
          !text.contains('订单') &&
          !text.contains('实名') &&
          !text.contains('真爱') &&
          !text.contains('Lv') &&
          !text.contains('稿件') &&
          !_money.hasMatch(text) &&
          !_date.hasMatch(text);
    }).toList()
      ..sort((a, b) => b.centerY.compareTo(a.centerY));
    final buyer = buyers.isEmpty ? null : buyers.first;

    final amountLines = prepared.where((line) =>
        line.centerY >= titleY + 10 &&
        line.centerY < contentBottom).toList();
    (double, ScreenshotTextLine)? fee;
    for (final line in amountLines) {
      final match = _money.firstMatch(line.text);
      if (match == null) continue;
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        fee = (value, line);
        break;
      }
    }
    if (fee == null) {
      final currency = amountLines.where((line) =>
          RegExp(r'^[¥￥]$').hasMatch(line.text.trim())).toList();
      for (final line in amountLines) {
        final number = double.tryParse(line.text.trim());
        if (number == null) continue;
        if (currency.any((y) =>
            (y.centerY - line.centerY).abs() < 27 &&
            ((line.left - y.right).abs() < 85 ||
                (line.left - y.left).abs() < 85))) {
          fee = (number, line);
          break;
        }
      }
    }
    final finished = prepared.any((line) =>
        line.centerY < imageHeight * 0.17 &&
        line.text.contains('订单已完成'));
    final percentage = prepared.where((line) =>
        line.centerY < contentBottom &&
        line.text.contains('当前交付节点')).map((line) =>
        _node.firstMatch(line.text)).whereType<RegExpMatch>()
        .map((m) => int.tryParse(m.group(1)!))
        .whereType<int>().where((p) => p <= 100).firstOrNull;

    return [
      ScreenshotOrderCandidate(
        title: title?.text.trim() ?? '',
        clientName: buyer?.text.trim() ?? '',
        detectedDate: deadline?.$2,
        deadlineHasTime: deadline?.$3 ?? false,
        relativeDeadlineText: null,
        price: fee?.$1,
        progressPercent: percentage ?? (finished ? 100 : null),
        sourceLines: List.unmodifiable(prepared),
        sourceStartY: 0,
        sourceEndY: imageHeight,
        titleBox: title,
        clientBox: buyer,
        priceBox: fee?.$2,
        deadlineBox: deadline?.$1,
      ),
    ];
  }
}
