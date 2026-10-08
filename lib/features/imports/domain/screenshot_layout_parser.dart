import 'screenshot_import_rules.dart';

/// Platform-neutral line geometry. Native OCR engines only need to convert
/// their text, confidence and rectangles into this lightweight shape.
class ScreenshotTextLine {
  const ScreenshotTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 1,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  double get centerY => (top + bottom) / 2;
}

class ScreenshotOrderCandidate {
  const ScreenshotOrderCandidate({
    required this.title,
    required this.clientName,
    required this.detectedDate,
    required this.deadlineHasTime,
    required this.price,
    required this.progressPercent,
    required this.sourceLines,
    required this.sourceStartY,
    required this.sourceEndY,
  });

  final String title;
  final String clientName;
  /// For date-only OCR this is a calendar date, NOT a real midnight deadline.
  /// Do not assign this value directly to QueueOrder.deadline.
  final DateTime detectedDate;
  final bool deadlineHasTime;

  bool get needsDeadlineTimeConfirmation => !deadlineHasTime;

  /// Safe field for a future batch writer: null until a missing time is
  /// explicitly supplied by the user. The current queue order model stores
  /// a complete DateTime and cannot represent date-only deadlines.
  DateTime? get importReadyDeadline =>
      deadlineHasTime ? detectedDate : null;

  /// Allows per-card or explicitly chosen batch time input while retaining
  /// the date read from the image. Invalid clock values cannot be imported.
  DateTime deadlineWithChosenTime({
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw RangeError('截稿时间超出有效范围');
    }
    return DateTime(
      detectedDate.year,
      detectedDate.month,
      detectedDate.day,
      hour,
      minute,
    );
  }
  final double? price;
  final int? progressPercent;
  final List<ScreenshotTextLine> sourceLines;
  final double sourceStartY;
  final double sourceEndY;
}

/// Early deterministic card extraction prototype for vertically stacked list
/// screenshots. The date anchor keeps one card's price/client separate from
/// the next one. Low-confidence extraction still needs human review.
class ScreenshotLayoutParser {
  const ScreenshotLayoutParser();

  static final RegExp _date = RegExp(
    r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?'
    r'(?:\s+(\d{1,2}):(\d{2}))?',
  );
  static final RegExp _money = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  static final RegExp _percent = RegExp(r'(\d{1,3})\s*%');

  List<ScreenshotOrderCandidate> parse({
    required List<ScreenshotTextLine> lines,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return const [];

    final prepared = lines.where((line) {
      return line.text.trim().isNotEmpty &&
          !isScreenshotChromeLine(
            text: line.text,
            centerY: line.centerY,
            imageHeight: imageHeight,
          );
    }).toList()
      ..sort((a, b) {
        final byY = a.centerY.compareTo(b.centerY);
        return byY == 0 ? a.left.compareTo(b.left) : byY;
      });

    final dates = <(ScreenshotTextLine, DateTime, bool)>[];
    for (final line in prepared) {
      final match = _date.firstMatch(line.text);
      if (match == null) continue;
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.tryParse(match.group(4) ?? '') ?? 0;
      final minute = int.tryParse(match.group(5) ?? '') ?? 0;
      if (month < 1 || month > 12 || day < 1 || day > 31 ||
          hour > 23 || minute > 59) {
        continue;
      }
      final value = DateTime(year, month, day, hour, minute);
      if (value.month != month || value.day != day) continue;
      dates.add((line, value, match.group(4) != null));
    }

    final result = <ScreenshotOrderCandidate>[];
    for (var i = 0; i < dates.length; i++) {
      final anchor = dates[i].$1;

      // A previous order's deadline cannot become this card's title/client.
      // Keep some headroom for cards with a large portrait area.
      final previousDateY = i == 0 ? 0.0 : dates[i - 1].$1.centerY;
      final startY = (anchor.centerY - 370).clamp(
        previousDateY + (i == 0 ? 0 : 24), anchor.centerY).toDouble();
      final nextDateY =
          i + 1 < dates.length ? dates[i + 1].$1.centerY : imageHeight;
      final endY = (anchor.centerY + 115).clamp(
        anchor.centerY, (anchor.centerY + nextDateY) / 2).toDouble();

      final preceding = prepared.where((line) =>
          line.centerY >= startY &&
          line.centerY < anchor.centerY - 7).toList();
      final titles = preceding.where((line) =>
          line.centerY > anchor.centerY - 260 &&
          _plausibleTitle(line.text)).toList();
      if (titles.isEmpty) continue;

      // Nearest reasonable title before the deadline; avoid treating a buyer
      // name as a title when one is further down the card.
      titles.sort((a, b) => b.centerY.compareTo(a.centerY));
      final titleLine = titles.first;
      final title = _stripKnownUiLabel(titleLine.text);
      if (title.isEmpty) continue;

      final buyers = preceding.where((line) =>
          line.centerY < titleLine.centerY - 10 &&
          line.centerY >= titleLine.centerY - 210 &&
          line.left < imageWidth * 0.65 &&
          _plausibleBuyer(line.text)).toList()
        ..sort((a, b) => b.centerY.compareTo(a.centerY));
      final buyer = buyers.isEmpty ? '' : buyers.first.text.trim();

      // Price can appear above the date (米画师) or below it (画加).
      final cardArea = prepared.where((line) =>
          line.centerY >= titleLine.centerY - 12 &&
          line.centerY <= endY).toList();
      double? price;
      int? progress;
      for (final line in cardArea) {
        final money = _money.firstMatch(line.text);
        if (money != null && price == null) {
          price = double.tryParse(money.group(1)!);
        }
        final matched = _percent.firstMatch(line.text);
        if (matched != null && progress == null) {
          progress = int.tryParse(matched.group(1)!);
          if (progress != null && progress > 100) progress = null;
        }
      }

      result.add(ScreenshotOrderCandidate(
        title: title,
        clientName: buyer,
        detectedDate: dates[i].$2,
        deadlineHasTime: dates[i].$3,
        price: price,
        progressPercent: progress,
        sourceLines: List.unmodifiable(cardArea),
        sourceStartY: startY,
        sourceEndY: endY,
      ));
    }
    return List.unmodifiable(result);
  }

  static bool _plausibleTitle(String source) {
    final text = source.trim();
    if (text.length < 2 || _date.hasMatch(text) ||
        _money.hasMatch(text) || _percent.hasMatch(text)) {
      return false;
    }
    const ignore = [
      '当前交付节点', '截稿时间', '购买时间', '添加备注',
      '全额支付', '定向企划', '待支付', '我卖出的', '已完成',
      '进行中', '待交稿', '等待对方收稿', '企划方名称',
    ];
    if (ignore.any((item) => text == item || text.startsWith('$item：'))) {
      return false;
    }
    return true;
  }

  static bool _plausibleBuyer(String source) {
    final text = source.trim();
    if (text.isEmpty || _date.hasMatch(text) ||
        _money.hasMatch(text) || _percent.hasMatch(text)) {
      return false;
    }
    if (<String>{
      '进行中', '已完成', '我卖出的', '待交稿', '添加备注',
      '全部', '默认', '返回', '全额支付', '定向企划',
    }.contains(text)) {
      return false;
    }
    if (text.startsWith('当前交付节点') || text.startsWith('截稿时间')) {
      return false;
    }
    return true;
  }

  static String _stripKnownUiLabel(String source) {
    var text = source.trim();
    // These are platform presentation badges, unlike real title prefixes
    // such as 【常驻】, which must remain untouched.
    if (text.startsWith('定向企划 ')) {
      text = text.substring('定向企划 '.length);
    }
    return text.trim();
  }
}
