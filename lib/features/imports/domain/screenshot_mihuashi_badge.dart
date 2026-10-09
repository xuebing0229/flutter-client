import '../../orders/domain/queue_order.dart';
import 'screenshot_layout_parser.dart';

/// A MiHuashi "定向企划" badge is platform chrome, not part of artwork title.
/// ML Kit may return the badge as its own line OR join it directly to title.
const directedCommissionTag = '定向企划';
final RegExp _mergedBadge = RegExp(r'^定向企划\s*[:：]?\s*');

/// Only strip a proven prefix, leaving the remainder of the artwork title
/// unchanged (including legitimate 【...】 user prefixes).
String removeDirectedCommissionPrefix(String raw) =>
    raw.trim().replaceFirst(_mergedBadge, '').trim();

bool hasDirectedCommissionBadge({
  required CommissionPlatform? platform,
  required ScreenshotOrderCandidate candidate,
}) {
  if (platform != CommissionPlatform.mihuashi) return false;
  final rawTitle = candidate.titleBox?.text.trim() ?? candidate.title.trim();
  if (_mergedBadge.hasMatch(rawTitle) && rawTitle.length > directedCommissionTag.length) {
    return true;
  }

  // If OCR returned the badge separately, it must share the title row and
  // lie to its left. Do not borrow "定向企划" from another order card.
  final title = candidate.titleBox;
  if (title == null) return false;
  return candidate.sourceLines.any((line) =>
      line.text.trim() == directedCommissionTag &&
      (line.centerY - title.centerY).abs() <= 30 &&
      line.left < title.left &&
      line.right <= title.right);
}
