import 'screenshot_layout_parser.dart';

/// Reconcile OCR-only spelling variants of the SAME visible MiHuashi listing.
/// This never merges cards, buyers, payments, or deadlines. It only supplies
/// more consistent titles to the editable import preview.
///
/// A single similarly spelled title is NOT enough evidence: require two
/// independent cards with the same normalized title, amount and deadline,
/// then correct at most one missing/replaced character in other cards.
/// Users can still edit any title before committing.
List<String> reconcileMiHuashiScreenshotTitles(
  List<ScreenshotOrderCandidate> cards,
) {
  final titles = <String>[
    for (final card in cards) _repairKnownBadgeOcr(card.title),
  ];
  if (cards.length < 3) return List.unmodifiable(titles);

  final comparison = titles.map(_comparisonTitle).toList();
  final support = <List<int>>[];
  for (var i = 0; i < cards.length; i++) {
    support.add([
      for (var j = 0; j < cards.length; j++)
        if (comparison[i] == comparison[j] &&
            _sameListingEvidence(cards[i], cards[j]))
          j,
    ]);
  }

  // Prefer an exact repeated OCR reading over a one-off guess.
  final anchors = <int>[
    for (var i = 0; i < cards.length; i++)
      if (support[i].length >= 2 &&
          _badge(titles[i]).isNotEmpty)
        i,
  ]..sort((a, b) {
      final votes = support[b].length.compareTo(support[a].length);
      if (votes != 0) return votes;
      return _displayQuality(titles[b]).compareTo(_displayQuality(titles[a]));
    });

  final used = <int>{};
  for (final anchor in anchors) {
    if (used.contains(anchor)) continue;
    final votes = support[anchor];
    // Do not treat OCR splitting the same buyer/card as independent votes.
    final distinctBuyers = votes
        .map((index) => cards[index].clientName.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (distinctBuyers.length < 2) continue;

    final best = votes.reduce((a, b) =>
        _displayQuality(titles[a]) >= _displayQuality(titles[b]) ? a : b);
    final canonicalTitle = titles[best];
    final canonicalKey = comparison[best];
    final canonicalBadge = _badge(canonicalTitle);
    final canonicalNumbers = _numbers(canonicalKey);

    for (var k = 0; k < cards.length; k++) {
      if (used.contains(k) ||
          !_sameListingEvidence(cards[anchor], cards[k]) ||
          _badge(titles[k]) != canonicalBadge ||
          _numbers(comparison[k]) != canonicalNumbers ||
          !_atMostOneEdit(canonicalKey, comparison[k])) {
        continue;
      }
      titles[k] = canonicalTitle;
      used.add(k);
    }
  }
  return List.unmodifiable(titles);
}

String _repairKnownBadgeOcr(String raw) {
  var text = raw.trim();
  // In tiny screenshots ML Kit can read the closing bracket in 【常驻】 as
  // 1, l, I or a vertical stroke. Do not change real 【常驻1】 custom tags.
  if (RegExp(r'^【常驻[1lI丨|](?!】)').hasMatch(text)) {
    text = text.replaceFirst(
      RegExp(r'^【常驻[1lI丨|]'),
      '【常驻】',
    );
  }
  // Real phone OCR renders the closing bracket of 【这是】 as "1".
  // Only repair this specific known badge when there is no actual 】 before
  // the artwork title; do NOT globally replace numbers in people's titles.
  if (RegExp(r'^【这是[1lI丨|](?!】)').hasMatch(text) &&
      !text.substring(0, text.length < 8 ? text.length : 8).contains('】')) {
    text = text.replaceFirst(RegExp(r'^【这是[1lI丨|]'), '【这是】');
  }
  return text;
}

String _comparisonTitle(String text) =>
    _repairKnownBadgeOcr(text)
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();

String _badge(String title) =>
    RegExp(r'^【[^】]{1,12}】').firstMatch(title)?.group(0) ?? '';

String _numbers(String title) =>
    RegExp(r'\d+(?:\.\d+)?').allMatches(title).map((m) => m.group(0)).join('|');

int _displayQuality(String title) {
  // Prefer a properly closed badge, informative length and fewer OCR gaps.
  final bracket = title.startsWith('【') && title.contains('】') ? 100 : 0;
  return bracket + title.runes.length;
}

bool _sameListingEvidence(
  ScreenshotOrderCandidate a,
  ScreenshotOrderCandidate b,
) {
  if (a.price == null || b.price == null || a.price != b.price) {
    return false;
  }
  final first = a.detectedDate;
  final second = b.detectedDate;
  if (first == null || second == null) return false;
  if (first.year != second.year ||
      first.month != second.month ||
      first.day != second.day) {
    return false;
  }
  // Never silently join two distinct clock-specific listings.
  if (a.deadlineHasTime && b.deadlineHasTime &&
      (first.hour != second.hour || first.minute != second.minute)) {
    return false;
  }
  return true;
}

bool _atMostOneEdit(String left, String right) {
  if (left == right) return true;
  final a = left.runes.toList();
  final b = right.runes.toList();
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
    } else {
      edits++;
      if (edits > 1) return false;
      if (a.length >= b.length) i++;
      if (b.length >= a.length) j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}
