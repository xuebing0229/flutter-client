import '../../orders/domain/queue_order.dart';
import 'screenshot_import_rules.dart';

/// Resolution of a screenshot import comparison. None of these decisions
/// performs a write, sale increment, or automatic merge.
enum ScreenshotDuplicateReview {
  independent,
  duplicateOcrCard,
  possibleDuplicate,
  insufficientEvidence,
}

enum ScreenshotDatePrecision { day, minute, second }

/// A unique image instance is one screenshot selected in the CURRENT import
/// session (not a file hash). Cards inside it are independent transactions
/// even when their visible data happens to be identical.
class ScreenshotImportIdentity {
  const ScreenshotImportIdentity({
    required this.platform,
    required this.title,
    required this.clientName,
    required this.imageInstanceId,
    required this.cardInstanceId,
    this.sourceDate,
    this.datePrecision = ScreenshotDatePrecision.day,
  });

  final CommissionPlatform platform;
  final String title;
  final String clientName;
  final DateTime? sourceDate;
  final ScreenshotDatePrecision datePrecision;
  final String imageInstanceId;
  final String cardInstanceId;
}

/// Separately located cards in one screenshot remain independent. Across
/// images (including overlapping screenshots) comparisons are conservative:
/// matching title, buyer, platform and displayed date are only a prompt for
/// the user, not permission to merge/delete or change soldCount.
///
/// When comparing to already-saved orders, use the cross-image branch (never
/// assign the historical record the current screenshot's imageInstanceId).
ScreenshotDuplicateReview reviewScreenshotDuplicate(
  ScreenshotImportIdentity left,
  ScreenshotImportIdentity right,
) {
  if (left.imageInstanceId == right.imageInstanceId) {
    return left.cardInstanceId == right.cardInstanceId
        ? ScreenshotDuplicateReview.duplicateOcrCard
        : ScreenshotDuplicateReview.independent;
  }

  if (left.platform != right.platform ||
      normalizedImportTitle(left.title) !=
          normalizedImportTitle(right.title) ||
      left.title.trim().isEmpty || right.title.trim().isEmpty) {
    return ScreenshotDuplicateReview.independent;
  }

  final leftClient = normalizedImportTitle(left.clientName);
  final rightClient = normalizedImportTitle(right.clientName);
  if (leftClient.isNotEmpty &&
      rightClient.isNotEmpty &&
      leftClient != rightClient) {
    return ScreenshotDuplicateReview.independent;
  }

  final a = left.sourceDate;
  final b = right.sourceDate;
  if (a != null && b != null &&
      !_sameDisplayedTime(a, left.datePrecision, b, right.datePrecision)) {
    return ScreenshotDuplicateReview.independent;
  }

  // Buyer/date gaps warrant review, but cannot prove a transaction match.
  if (leftClient.isEmpty || rightClient.isEmpty || a == null || b == null) {
    return ScreenshotDuplicateReview.insufficientEvidence;
  }

  // Huajia's example shows deadline precision to the MINUTE, not seconds;
  // even matching exact times is only a potential duplicate.
  return ScreenshotDuplicateReview.possibleDuplicate;
}

bool _sameDisplayedTime(
  DateTime a,
  ScreenshotDatePrecision aPrecision,
  DateTime b,
  ScreenshotDatePrecision bPrecision,
) {
  // Use the coarser source precision. Never infer invisible seconds.
  if (a.year != b.year || a.month != b.month || a.day != b.day) {
    return false;
  }
  if (aPrecision == ScreenshotDatePrecision.day ||
      bPrecision == ScreenshotDatePrecision.day) {
    return true;
  }
  if (a.hour != b.hour || a.minute != b.minute) return false;
  if (aPrecision == ScreenshotDatePrecision.minute ||
      bPrecision == ScreenshotDatePrecision.minute) {
    return true;
  }
  return a.second == b.second;
}
