import 'dart:math' as math;

import '../../orders/domain/queue_order.dart';
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
    required this.relativeDeadlineText,
    required this.price,
    required this.progressPercent,
    required this.sourceLines,
    required this.sourceStartY,
    required this.sourceEndY,
    this.titleBox,
    this.clientBox,
    this.priceBox,
    this.deadlineBox,
  });

  final String title;
  final String clientName;

  /// Date-only OCR is not a midnight deadline; null also represents a quick
  /// order showing only an acceptance-relative duration.
  final DateTime? detectedDate;
  final bool deadlineHasTime;

  /// A raw, visible relative deadline (e.g. 接单后3天). Never transform it
  /// into a concrete timestamp without the actual acceptance time.
  final String? relativeDeadlineText;

  bool get hasRelativeDeadline => relativeDeadlineText != null;
  bool get needsDeadlineDateConfirmation => detectedDate == null;

  bool get needsDeadlineTimeConfirmation => !deadlineHasTime;

  /// Safe field for a future batch writer: null until a missing time is
  /// explicitly supplied by the user. The current queue order model stores
  /// a complete DateTime and cannot represent date-only deadlines.
  DateTime? get importReadyDeadline =>
      deadlineHasTime ? detectedDate : null;

  /// Date-only 米画师 listings usually use 23:59 for ordinary day-based
  /// deadlines. This is a visible, editable suggestion only; it is NOT an
  /// OCR-confirmed deadline and cannot be written without user approval.
  ///
  /// Only known ordinary day-based commissions get this suggestion. The
  /// screenshot may belong to a quick/relative-after-acceptance listing, and
  /// an "X days remaining" label is not enough to recover its exact time.
  /// null = not determined; true = relative/quick; false = confirmed ordinary.
  DateTime? suggestedDeadline({
    required CommissionPlatform platform,
    bool? isQuickCommission,
  }) {
    if (deadlineHasTime) return detectedDate;
    if (detectedDate == null ||
        hasRelativeDeadline ||
        platform != CommissionPlatform.mihuashi ||
        isQuickCommission != false) {
      return null;
    }
    return deadlineWithChosenTime(hour: 23, minute: 59);
  }

  /// Allows per-card or explicitly chosen batch time input while retaining
  /// the date read from the image. Invalid clock values cannot be imported.
  DateTime deadlineWithChosenTime({
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw RangeError('截稿时间超出有效范围');
    }
    final date = detectedDate;
    if (date == null) {
      throw StateError('截图未提供截稿日期，请手动选择完整日期时间');
    }
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
  }
  final double? price;
  final int? progressPercent;
  final List<ScreenshotTextLine> sourceLines;
  final double sourceStartY;
  final double sourceEndY;
  final ScreenshotTextLine? titleBox;
  final ScreenshotTextLine? clientBox;
  final ScreenshotTextLine? priceBox;
  final ScreenshotTextLine? deadlineBox;
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
  static final RegExp _clock = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
  static final RegExp _money = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  static final RegExp _percent = RegExp(r'(\d{1,3})\s*%');
  static final RegExp _detailTab = RegExp(
      r'稿件夹|进程动态|参考信息|联系企划方|上传稿件|共\s*\d+\s*个文件');
  static final RegExp _detailPayment = RegExp(
      r'稿酬|全额支付|约稿完成|已支付|已结算');


  // Identifies ONLY an acceptance-relative quick deadline, not labels like
  // "还有 23 天" which can appear on ordinary fixed-date commissions.
  static final RegExp _relativeDeadline = RegExp(
    r'(?:接单|接稿|成交|付款|支付|下单)\s*后\s*\d+\s*(?:天|日|小时|时)'
    r'|\d+\s*(?:天|日|小时|时)\s*(?:内交稿|内截稿|速约)',
  );

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
      var hour = int.tryParse(match.group(4) ?? '') ?? 0;
      var minute = int.tryParse(match.group(5) ?? '') ?? 0;
      var hasTime = match.group(4) != null;
      if (!hasTime) {
        // OCR may split the screenshot's date and clock into nearby text boxes.
        // A distant phone status bar clock must not fill an order deadline.
        final clocks = prepared.where((candidate) =>
            !identical(candidate, line) &&
            // A node/icon line below the date is not the deadline clock.
            // Split date+clock belongs on the SAME horizontal text row.
            (candidate.centerY - line.centerY).abs() <= 20 &&
            candidate.left >= line.left + 60 &&
            candidate.left <= line.right + 100 &&
            _clock.hasMatch(candidate.text.trim())).toList()
          ..sort((a, b) => (a.centerY - line.centerY).abs()
              .compareTo((b.centerY - line.centerY).abs()));
        if (clocks.isNotEmpty) {
          final matchedClock = _clock.firstMatch(clocks.first.text.trim())!;
          hour = int.parse(matchedClock.group(1)!);
          minute = int.parse(matchedClock.group(2)!);
          hasTime = true;
        }
      }
      if (month < 1 || month > 12 || day < 1 || day > 31 ||
          hour > 23 || minute > 59) {
        continue;
      }
      final value = DateTime(year, month, day, hour, minute);
      if (value.month != month || value.day != day) continue;
      dates.add((line, value, hasTime));
    }

    // A MiHuashi order detail page is one business record even when its
    // attachment list contains more timestamps than the deadline section.
    // Detect layout first; do not let generic date-based card splitting run.
    if (isMiHuashiOrderDetailScreenshot(
      lines: prepared,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    )) {
      return [
        _parseOrderDetail(
          prepared: prepared,
          dates: dates,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
      ];
    }

    // A card with only "接单后X天" has no calendar date. Preserve it as an
    // editable candidate, rather than silently dropping it from the import.
    // Explicit date anchors take precedence if a quick label belongs to the
    // very same card.
    final anchors = <_ScreenshotDeadlineAnchor>[
      for (final record in dates)
        _ScreenshotDeadlineAnchor(
          line: record.$1,
          date: record.$2,
          hasTime: record.$3,
        ),
    ];
    for (final line in prepared) {
      if (!_relativeDeadline.hasMatch(line.text)) continue;
      final nearbyDateIndex = anchors.indexWhere((item) =>
          item.date != null &&
          (item.line.centerY - line.centerY).abs() < 90);
      if (nearbyDateIndex != -1) {
        final dateAnchor = anchors[nearbyDateIndex];
        anchors[nearbyDateIndex] = _ScreenshotDeadlineAnchor(
          line: dateAnchor.line,
          date: dateAnchor.date,
          hasTime: dateAnchor.hasTime,
          relativeText: line.text.trim(),
        );
        continue;
      }
      anchors.add(_ScreenshotDeadlineAnchor(
        line: line,
        relativeText: line.text.trim(),
      ));
    }

    // A screenshot can omit deadlines entirely. Conservatively detect
    // artwork-title-shaped lines when no date/relative anchor follows the
    // title in its own card. They still require a human-filled deadline.
    for (final line in prepared) {
      final title = line.text.trim();
      final hasNearbyOrderField = line.left > imageWidth * 0.26 &&
          prepared.any((field) =>
              field.centerY > line.centerY &&
              field.centerY - line.centerY < 165 &&
              field.left > imageWidth * 0.24 &&
              (_money.hasMatch(field.text) ||
                  _percent.hasMatch(field.text)));
      final looksLikeCardTitle =
          title.startsWith('【') ||
          title.startsWith('定向企划 ') ||
          hasNearbyOrderField;
      if (!looksLikeCardTitle || !_plausibleTitle(title)) continue;
      if (anchors.any((anchor) =>
          anchor.line.centerY >= line.centerY &&
          anchor.line.centerY - line.centerY < 290)) {
        continue;
      }
      anchors.add(_ScreenshotDeadlineAnchor(line: line, isTitleAnchor: true));
    }
    anchors.sort((a, b) => a.line.centerY.compareTo(b.line.centerY));

    final result = <ScreenshotOrderCandidate>[];
    for (var i = 0; i < anchors.length; i++) {
      final deadlineAnchor = anchors[i];
      final anchor = deadlineAnchor.line;

      // A previous order's deadline cannot become this card's title/client.
      // Keep some headroom for cards with a large portrait area.
      final previousDateY =
          i == 0 ? 0.0 : anchors[i - 1].line.centerY;
      final startY = (anchor.centerY - 370).clamp(
        previousDateY + (i == 0 ? 0 : 24), anchor.centerY).toDouble();
      final nextDateY = i + 1 < anchors.length
          ? anchors[i + 1].line.centerY
          : imageHeight;
      // Huajia's price is bottom-right and can be more than 115 OCR
      // pixels below the deadline. Include the space until the next card.
      final maximumEnd = i + 1 < anchors.length
          ? (anchor.centerY + nextDateY) / 2
          : imageHeight;
      final endY = (anchor.centerY +
              (deadlineAnchor.isTitleAnchor ? 270 : 260))
          .clamp(anchor.centerY, maximumEnd)
          .toDouble();

      final preceding = prepared.where((line) =>
          line.centerY >= startY &&
          line.centerY < anchor.centerY - 7).toList();
      final titles = preceding.where((line) =>
          line.centerY > anchor.centerY - 260 &&
          _plausibleTitle(line.text) &&
          (line.left >= imageWidth * 0.20 ||
              line.text.trim().startsWith('【') ||
              line.text.trim().startsWith('定向企划'))).toList();
      if (!deadlineAnchor.isTitleAnchor && titles.isEmpty) continue;

      // With no date anchor the header itself is the title; otherwise select
      // the nearest plausible title before the deadline field.
      titles.sort((a, b) => b.centerY.compareTo(a.centerY));
      final titleLine =
          deadlineAnchor.isTitleAnchor ? anchor : titles.first;
      final title = _stripKnownUiLabel(titleLine.text);
      if (title.isEmpty) continue;

      final buyers = preceding.where((line) =>
          line.centerY < titleLine.centerY - 10 &&
          line.centerY >= titleLine.centerY - 210 &&
          line.left < imageWidth * 0.65 &&
          _plausibleBuyer(line.text)).toList()
        ..sort((a, b) => b.centerY.compareTo(a.centerY));
      final buyer = buyers.isEmpty ? '' :
          _cleanBuyerName(buyers.first.text);

      final cardArea = prepared.where((line) =>
          line.centerY >= titleLine.centerY - 12 &&
          line.centerY <= endY).toList();
      final amount = _findCardPrice(
        cardArea, titleLine: titleLine,
        deadlineLine: anchor, imageWidth: imageWidth,
      );
      final price = amount?.$1;
      final priceBox = amount?.$2;
      int? progress;
      for (final line in cardArea) {
        final matched = _percent.firstMatch(line.text);
        if (matched != null && progress == null) {
          progress = int.tryParse(matched.group(1)!);
          if (progress != null && progress > 100) progress = null;
        }
      }

      result.add(ScreenshotOrderCandidate(
        title: title,
        clientName: buyer,
        detectedDate: deadlineAnchor.date,
        deadlineHasTime: deadlineAnchor.hasTime,
        relativeDeadlineText: deadlineAnchor.relativeText,
        price: price,
        progressPercent: progress,
        sourceLines: List.unmodifiable(cardArea),
        sourceStartY: startY,
        sourceEndY: endY,
        titleBox: titleLine,
        clientBox: buyers.isEmpty ? null : buyers.first,
        priceBox: priceBox,
        deadlineBox: deadlineAnchor.isTitleAnchor ? null : anchor,
      ));
    }
    return List.unmodifiable(result);
  }

  ScreenshotOrderCandidate _parseOrderDetail({
    required List<ScreenshotTextLine> prepared,
    required List<(ScreenshotTextLine, DateTime, bool)> dates,
    required double imageWidth,
    required double imageHeight,
  }) {
    // A date in the attachment section is an UPLOAD date, not an order
    // deadline. Only inspect the header above the first attachment/tab area.
    final tabs = prepared.where((line) =>
        _detailTab.hasMatch(line.text.trim()) &&
        line.centerY > imageHeight * 0.24 &&
        line.centerY < imageHeight * 0.68).toList();
    final tabY = tabs.isEmpty
        ? imageHeight * 0.53
        : tabs.map((line) => line.centerY).reduce(math.min);
    final latestDeadlineY = math.min(tabY - 14, imageHeight * 0.41);

    final eligibleDates = dates.where((r) =>
        r.$1.centerY < latestDeadlineY &&
        r.$1.centerY > imageHeight * 0.09).toList();
    int priority(ScreenshotTextLine line) {
      if (line.text.contains('截稿')) {
        return 0;
      }
      if (prepared.any((label) =>
          label.text.contains('截稿') &&
          (label.centerY - line.centerY).abs() < 42 &&
          label.centerY < tabY)) {
        return 1;
      }
      return 2;
    }
    eligibleDates.sort((a, b) {
      final prioritized = priority(a.$1).compareTo(priority(b.$1));
      return prioritized != 0
          ? prioritized : a.$1.centerY.compareTo(b.$1.centerY);
    });
    final deadline = eligibleDates.isEmpty ? null : eligibleDates.first;
    final deadlineLine = deadline?.$1;
    final deadlineY = deadlineLine?.centerY ?? imageHeight * 0.19;

    // The actual work title is to the RIGHT of the artwork thumbnail, above
    // its deadline. The page navigation "订单" must never be a buyer/title.
    final titles = prepared.where((line) =>
        line.centerY > imageHeight * 0.08 &&
        line.centerY < math.min(deadlineY - 8, imageHeight * 0.32) &&
        line.left >= imageWidth * 0.22 &&
        _plausibleDetailTitle(line.text)).toList()
      ..sort((a, b) => b.centerY.compareTo(a.centerY));
    final titleLine = titles.isEmpty ? null : titles.first;

    // Buyer sits in its own row BETWEEN deadline and payment status.
    // The upload filename/KB/date below 稿件夹 is never buyer information.
    final payment = prepared.where((line) =>
        line.centerY > deadlineY + 25 &&
        line.centerY < tabY &&
        _detailPayment.hasMatch(line.text)).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final paymentY = payment.isEmpty
        ? math.min(tabY - 12, deadlineY + imageHeight * 0.19)
        : payment.first.centerY;
    final buyers = prepared.where((line) =>
        line.centerY > deadlineY + 22 &&
        line.centerY < math.min(paymentY - 18, deadlineY + imageHeight * 0.16) &&
        line.left < imageWidth * 0.75 &&
        _plausibleDetailBuyer(line.text)).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final buyerLine = buyers.isEmpty ? null : buyers.first;

    final cardLines = prepared.where((line) =>
        line.centerY >= (titleLine?.centerY ?? imageHeight * 0.1) - 14 &&
        line.centerY < tabY).toList();
    final amount = _findDetailPrice(cardLines, paymentY: paymentY);
    final progress = cardLines
        .map((line) => _percent.firstMatch(line.text))
        .whereType<RegExpMatch>()
        .map((match) => int.tryParse(match.group(1)!))
        .whereType<int>()
        .where((value) => value <= 100)
        .firstOrNull;
    // A completed commission page may not show a separate progress widget;
    // the status "约稿完成" itself explicitly means the final 100% node.
    final isFinished = payment.any((line) =>
        line.text.contains('约稿完成'));
    return ScreenshotOrderCandidate(
      title: titleLine == null ? '' : _stripKnownUiLabel(titleLine.text),
      clientName: buyerLine == null ? '' : _cleanBuyerName(buyerLine.text),
      detectedDate: deadline?.$2,
      deadlineHasTime: deadline?.$3 ?? false,
      relativeDeadlineText: null,
      price: amount?.$1,
      progressPercent: progress ?? (isFinished ? 100 : null),
      // Preserve the full screenshot for preview inspection, but never turn
      // upload metadata below the tabs into a second commission.
      sourceLines: List.unmodifiable(prepared),
      sourceStartY: 0,
      sourceEndY: imageHeight,
      titleBox: titleLine,
      clientBox: buyerLine,
      priceBox: amount?.$2,
      deadlineBox: deadlineLine,
    );
  }

  static (double, ScreenshotTextLine)? _findDetailPrice(
    List<ScreenshotTextLine> lines, {required double paymentY}) {
    // Prefer a currency token in the payment/status row, not a number from
    // the thumbnail or file-size line. Some OCR runs separate ¥ and 88.
    final nearby = lines.where((line) =>
        (line.centerY - paymentY).abs() < 40).toList();
    for (final line in nearby) {
      final matched = _money.firstMatch(line.text);
      if (matched != null) {
        final value = double.tryParse(matched.group(1)!);
        if (value != null) return (value, line);
      }
    }
    final currencyMarks = nearby.where(
      (line) => RegExp(r'^[¥￥]$').hasMatch(line.text.trim()),
    ).toList();
    for (final line in nearby) {
      final value = double.tryParse(line.text.trim());
      if (value == null || value < 0 || value > 10000000) continue;
      final paired = currencyMarks.any((symbol) =>
          (symbol.centerY - line.centerY).abs() < 27 &&
          (line.left - symbol.right).abs() < 90);
      // OCR can drop the currency glyph but preserve the fee number.
      final feeLabel = nearby.any((label) =>
          _detailPayment.hasMatch(label.text) &&
          (label.centerY - line.centerY).abs() < 25 &&
          label.left <= line.left);
      if (paired || feeLabel) return (value, line);
    }
    return null;
  }

  static bool _plausibleDetailTitle(String text) {
    if (!_plausibleTitle(text)) return false;
    final name = text.trim();
    if (_detailTab.hasMatch(name) || _detailPayment.hasMatch(name) ||
        name.contains('截稿') || name.contains('上传') ||
        name == '订单' || name.contains('文件')) {
      return false;
    }
    return true;
  }

  static bool _plausibleDetailBuyer(String text) {
    final name = text.trim();
    if (!_plausibleBuyer(name) || _detailTab.hasMatch(name) ||
        _detailPayment.hasMatch(name) || name.contains('截稿') ||
        name == '订单' || name.contains('文件') ||
        name.contains('.png') || name.contains('.jpg') ||
        name.contains('KB') || name.contains('GB')) {
      return false;
    }
    return true;
  }

  /// Find amounts even when OCR separates the currency glyph from its digits.
  /// Standalone digits are trusted only in a known price location.
  static (double, ScreenshotTextLine)? _findCardPrice(
    List<ScreenshotTextLine> lines, {
    required ScreenshotTextLine titleLine,
    required ScreenshotTextLine deadlineLine,
    required double imageWidth,
    bool detail = false,
  }) {
    // Full-image OCR may return ¥30, a zoomed crop may return ¥ and 30.
    // Both are valid, but only inside the current card.
    final currency = lines.where((line) =>
        RegExp(r'^[¥￥]$').hasMatch(line.text.trim())).toList();
    final candidates = <(double, ScreenshotTextLine, int)>[];
    for (final line in lines) {
      final cleaned = line.text.trim();
      final explicit = _money.firstMatch(cleaned);
      final bare = RegExp(r'^\d{1,7}(?:\.\d{1,2})?$')
          .firstMatch(cleaned);
      final value = double.tryParse(
        explicit != null ? explicit.group(1)! : (bare?.group(0) ?? ''),
      );
      if (value == null || value < 0) continue;
      final adjacentYen = currency.any((symbol) =>
          (symbol.centerY - line.centerY).abs() < 28 &&
          (line.left - symbol.right).abs() < 90);
      // Never mistake a cropped right-end fragment of 16:48 for a fee.
      final belowDeadline = line.centerY > deadlineLine.centerY + 12;
      final huajiaPricePosition = belowDeadline &&
          line.left >= imageWidth * 0.69;
      final mihuashiPricePosition =
          line.centerY > titleLine.centerY + 10 &&
          line.centerY < deadlineLine.centerY - 8 &&
          (line.left - titleLine.left).abs() < imageWidth * 0.19 &&
          cleaned.length >= 2;
      final detailFee = detail && lines.any((label) =>
          (label.text.contains('稿酬') || label.text.contains('支付')) &&
          (label.centerY - line.centerY).abs() < 30);
      if (explicit == null && !adjacentYen &&
          !huajiaPricePosition && !mihuashiPricePosition && !detailFee) {
        continue;
      }
      final strength = explicit != null ? 3 : adjacentYen ? 2 : 1;
      candidates.add((value, line, strength));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byStrength = b.$3.compareTo(a.$3);
      if (byStrength != 0) return byStrength;
      return a.$2.centerY.compareTo(b.$2.centerY);
    });
    final best = candidates.first;
    return (best.$1, best.$2);
  }

  static bool _plausibleTitle(String source) {
    final text = source.trim();
    if (text.length < 2 || _date.hasMatch(text) ||
        _money.hasMatch(text) || _percent.hasMatch(text) ||
        RegExp(r'^[¥￥]?\d+(?:\.\d+)?$').hasMatch(text)) {
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

  static String _cleanBuyerName(String source) {
    // Huajia renders a chevron after the customer name; its glyph is not
    // part of the person's username.
    return source.trim().replaceFirst(RegExp(r'\s*[›＞>]\s*$'), '').trim();
  }

  static bool _plausibleBuyer(String source) {
    final text = source.trim();
    if (text.isEmpty || _date.hasMatch(text) ||
        _money.hasMatch(text) || _percent.hasMatch(text) ||
        RegExp(r'^[¥￥]?\d+(?:\.\d+)?$').hasMatch(text)) {
      return false;
    }
    if (<String>{
      '进行中', '已完成', '我卖出的', '待交稿', '添加备注',
      '全部', '默认', '返回', '全额支付', '定向企划', '订单',
      '稿件夹', '进程动态', '参考信息', '联系企划方', '上传稿件',
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



/// An order detail is a SINGLE transaction; its lower half can contain many
/// file timestamps. Use geometry plus page-specific landmarks, not an exact
/// list of OCR spellings (small tab captions are frequently omitted by ML Kit).
bool isMiHuashiOrderDetailScreenshot({
  required Iterable<ScreenshotTextLine> lines,
  required double imageWidth,
  required double imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return false;
  final prepared = lines.toList();
  final combined = prepared.map((line) => line.text).join(' ');
  if (combined.contains('我卖出的')) return false;
  final centeredHeader = prepared.any((line) =>
      line.centerY < imageHeight * 0.135 &&
      line.centerY > imageHeight * 0.025 &&
      line.left >= imageWidth * 0.3 &&
      line.right <= imageWidth * 0.78 &&
      line.text.trim() == '订单');
  final deadlineTop = prepared.any((line) =>
      line.centerY > imageHeight * 0.115 &&
      line.centerY < imageHeight * 0.42 &&
      ScreenshotLayoutParser._date.hasMatch(line.text));
  final strongTab = prepared.any((line) =>
      line.centerY > imageHeight * 0.30 &&
      line.centerY < imageHeight * 0.72 &&
      ScreenshotLayoutParser._detailTab.hasMatch(line.text));
  final paymentRow = prepared.any((line) =>
      line.centerY > imageHeight * 0.23 &&
      line.centerY < imageHeight * 0.60 &&
      ScreenshotLayoutParser._detailPayment.hasMatch(line.text));
  final attachment = prepared.any((line) =>
      line.centerY > imageHeight * 0.36 &&
      (RegExp(r'\.(png|jpe?g|webp)\b', caseSensitive: false)
          .hasMatch(line.text) ||
       line.text.contains('企划方已下载')));
  // Header + order date + one independent confirmation suffices. If the
  // "订单" glyph is lost, require BOTH the payment line and attachment/tab.
  if (centeredHeader && deadlineTop &&
      (strongTab || paymentRow || attachment)) {
    return true;
  }
  if (deadlineTop && strongTab && paymentRow && attachment) return true;
  // If the deadline was not recognized at all, still preserve this page as
  // one editable order rather than manufacturing orders from upload times.
  return centeredHeader && paymentRow && strongTab && attachment;
}

/// One screenshot-level deadline anchor. The date can be absent; an explicit
/// acceptance-relative phrase is retained verbatim for the preview.
class _ScreenshotDeadlineAnchor {
  const _ScreenshotDeadlineAnchor({
    required this.line,
    this.date,
    this.hasTime = false,
    this.relativeText,
    this.isTitleAnchor = false,
  });

  final ScreenshotTextLine line;
  final DateTime? date;
  final bool hasTime;
  final String? relativeText;
  final bool isTitleAnchor;
}
