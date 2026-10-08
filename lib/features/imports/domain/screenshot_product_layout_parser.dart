import 'screenshot_layout_parser.dart';
import 'screenshot_import_rules.dart';

class ScreenshotProductTextCandidate {
  const ScreenshotProductTextCandidate({required this.title, this.price});
  final String title;
  final double? price;
}

/// Product screenshot cards have no mandatory deadline. Group around prices
/// and distinctive title lines, never around dates. Every candidate is
/// editable in preview and duplicate storefront titles are collapsed later.
class ScreenshotProductLayoutParser {
  const ScreenshotProductLayoutParser();

  static final _money = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  static final _date = RegExp(r'20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}');
  static const _ui = <String>{
    '进行中', '已完成', '已中断', '排序', '全部',
    '我卖出的', '待确认', '添加备注', '菜单',
    '搜索排单', '截稿时间', '当前交付节点',
    '稿件夹', '企划方已下载', '全额支付',
    '单次售卖', '多次售卖', '已售出', '未售出',
  };

  List<ScreenshotProductTextCandidate> parse({
    required Iterable<ScreenshotTextLine> lines,
    required double imageHeight,
  }) {
    final filtered = lines.where((line) =>
        line.text.trim().isNotEmpty &&
        !isScreenshotChromeLine(
          text: line.text,
          centerY: line.centerY,
          imageHeight: imageHeight,
        )).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));

    final titles = <ScreenshotTextLine>[];
    for (final line in filtered) {
      final s = line.text.trim();
      if (s.length < 3 || s.length > 85 ||
          _date.hasMatch(s) || _money.hasMatch(s) ||
          RegExp(r'^\d+(?:\.\d+)?%$').hasMatch(s) ||
          _ui.contains(s) || s.startsWith('剩余') ||
          s.startsWith('距截稿') || s.startsWith('截稿') ||
          s.startsWith('当前') || s.startsWith('已全额')) {
        continue;
      }

      // The screenshot's storefront name should look like a title, not a
      // timestamp, buyer username or button. Uncertain rows may be removed
      // in preview; never pretend these heuristics are certain.
      final looksLikeTitle = s.startsWith('【') ||
          s.startsWith('「') || s.startsWith('定向企划 ') ||
          s.contains('橱窗') || s.contains('摸鱼') ||
          s.contains('稿') || s.contains('画');
      if (looksLikeTitle) titles.add(line);
    }

    // Keep names without obvious title keywords when positioned above price.
    // The preview remains editable; no amount or title is silently trusted.
    for (final priceLine in filtered.where(
      (line) => _money.hasMatch(line.text),
    )) {
      final candidates = filtered.where((line) =>
          line.centerY < priceLine.centerY &&
          priceLine.centerY - line.centerY < 185 &&
          line.text.trim().length >= 3 &&
          line.text.trim().length <= 85 &&
          !_money.hasMatch(line.text) &&
          !_date.hasMatch(line.text) &&
          !_ui.contains(line.text.trim()) &&
          // A nearby metadata row is NOT a product title. In real storefront
          // screenshots it is often closer to the price than the actual title.
          !line.text.trim().startsWith('截稿时间') &&
          !line.text.trim().startsWith('距截稿') &&
          !line.text.trim().startsWith('当前交付') &&
          !line.text.trim().startsWith('剩余') &&
          !line.text.trim().startsWith('创作节点') &&
          !RegExp(r'^\d+(?:\.\d+)?%
      ).toList()
        ..sort((a, b) => b.centerY.compareTo(a.centerY));
      if (candidates.isNotEmpty && !titles.contains(candidates.first)) {
        titles.add(candidates.first);
      }
    }
    titles.sort((a, b) => a.centerY.compareTo(b.centerY));

    final results = <ScreenshotProductTextCandidate>[];
    for (final titleLine in titles) {
      final nextTitleY = titles.where(
        (line) => line.centerY > titleLine.centerY,
      ).map((line) => line.centerY).fold<double>(
        imageHeight,
        (minY, y) => y < minY ? y : minY,
      );
      final priceCandidates = filtered.where((line) =>
          line.centerY >= titleLine.centerY &&
          line.centerY < nextTitleY &&
          line.centerY - titleLine.centerY < 230 &&
          _money.hasMatch(line.text)).toList()
        ..sort((a, b) => a.centerY.compareTo(b.centerY));
      final priceMatch = priceCandidates.isEmpty
          ? null : _money.firstMatch(priceCandidates.first.text);
      final raw = titleLine.text.trim();
      final cleaned = raw.startsWith('定向企划 ')
          ? raw.substring('定向企划 '.length).trim() : raw;
      results.add(ScreenshotProductTextCandidate(
        title: cleaned,
        price: priceMatch == null
            ? null : double.tryParse(priceMatch.group(1)!),
      ));
    }
    return List.unmodifiable(results);
  }
}
).hasMatch(line.text.trim())
      ).toList()
        ..sort((a, b) => b.centerY.compareTo(a.centerY));
      if (candidates.isNotEmpty && !titles.contains(candidates.first)) {
        titles.add(candidates.first);
      }
    }
    titles.sort((a, b) => a.centerY.compareTo(b.centerY));

    final results = <ScreenshotProductTextCandidate>[];
    for (final titleLine in titles) {
      final nextTitleY = titles.where(
        (line) => line.centerY > titleLine.centerY,
      ).map((line) => line.centerY).fold<double>(
        imageHeight,
        (minY, y) => y < minY ? y : minY,
      );
      final priceCandidates = filtered.where((line) =>
          line.centerY >= titleLine.centerY &&
          line.centerY < nextTitleY &&
          line.centerY - titleLine.centerY < 230 &&
          _money.hasMatch(line.text)).toList()
        ..sort((a, b) => a.centerY.compareTo(b.centerY));
      final priceMatch = priceCandidates.isEmpty
          ? null : _money.firstMatch(priceCandidates.first.text);
      final raw = titleLine.text.trim();
      final cleaned = raw.startsWith('定向企划 ')
          ? raw.substring('定向企划 '.length).trim() : raw;
      results.add(ScreenshotProductTextCandidate(
        title: cleaned,
        price: priceMatch == null
            ? null : double.tryParse(priceMatch.group(1)!),
      ));
    }
    return List.unmodifiable(results);
  }
}
