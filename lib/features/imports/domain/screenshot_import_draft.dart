import '../../orders/domain/queue_order.dart';
import '../../products/domain/finished_product.dart';
import 'screenshot_import_rules.dart';
import 'screenshot_layout_parser.dart';

/// A mutable item held only by the import preview; no writes happen until
/// validate-and-commit. Separate cards retain their own stable preview IDs.
class ScreenshotImportDraft {
  ScreenshotImportDraft({
    required this.id,
    required this.sourceImageId,
    this.sourceFingerprint,
    required this.title,
    required this.clientName,
    required this.price,
    required this.platform,
    required this.detectedDate,
    required this.recognizedPercent,
    this.sourceHasClock = false,
    this.sourceImagePath,
    this.sourceStartY,
    this.sourceEndY,
    this.sourceImageWidth,
    this.sourceImageHeight,
    this.titleBox,
    this.clientBox,
    this.priceBox,
    this.deadlineBox,
    required this.presetId,
    required this.nodeId,
    this.deadline,
    this.relativeDeadline,
    this.deadlineConfirmed = false,
    this.feeEnabled = false,
    this.tags = const <String>[],
    this.saleType = ProductSaleType.single,
  });

  final String id;
  final String sourceImageId;
  final String? sourceFingerprint;
  final String? sourceImagePath;
  final double? sourceStartY;
  final double? sourceEndY;
  final double? sourceImageWidth;
  final double? sourceImageHeight;
  final ScreenshotTextLine? titleBox;
  final ScreenshotTextLine? clientBox;
  final ScreenshotTextLine? priceBox;
  final ScreenshotTextLine? deadlineBox;
  String title;
  String clientName;
  double? price;
  /// Increment only when another UI action replaces a field programmatically.
  /// Ordinary keyboard edits must keep a stable widget key and input focus.
  int titleInputRevision = 0;
  int clientInputRevision = 0;
  CommissionPlatform? platform;
  final DateTime? detectedDate;
  /// Whether the actual screenshot contained HH:mm, not a user guess.
  final bool sourceHasClock;
  final int? recognizedPercent;
  final String? relativeDeadline;
  DateTime? deadline;
  bool deadlineConfirmed;
  bool feeEnabled;
  List<String> tags;
  ProductSaleType saleType;
  bool selected = true;
  /// Explicitly reselected a suspected duplicate; never auto-uncheck again.
  bool duplicateReviewed = false;
  bool duplicateAutoSkipped = false;
  bool presetManuallyChanged = false;
  bool nodeManuallyChanged = false;
  String presetId;
  String nodeId;
  String? duplicateWarning;

  String? validate({required bool importingProducts}) {
    if (!selected) return null;
    if (title.trim().isEmpty) return '请补充图名';
    if (platform == null) return '请确认平台';
    if (price == null || !price!.isFinite || price! < 0) {
      return '请填写有效稿价';
    }
    if (!importingProducts) {
      if (clientName.trim().isEmpty) return '请确认单主';
      if (!deadlineConfirmed) return '请确认截稿时间或主动选择未设置';
    }
    return null;
  }
}


int screenshotImportInformationScore(ScreenshotImportDraft row) {
  var score = 0;
  if (row.title.trim().isNotEmpty) score += 2;
  if (row.clientName.trim().isNotEmpty) score += 3;
  if (row.price != null) score += 2;
  if (row.detectedDate != null) score += 2;
  // Exact HH:mm visible in the source is substantially more informative
  // than a day-only deadline and should win a duplicate tie by default.
  if (row.sourceHasClock) score += 4;
  if (row.recognizedPercent != null) score += 2;
  if (row.relativeDeadline?.trim().isNotEmpty ?? false) score += 1;
  if (row.tags.isNotEmpty) score += 1;
  return score;
}

/// When two screenshots probably show the same order, keep the richer OCR
/// result selected by default. Ties are stable: the earlier row still wins.
/// This never merges fields because "possible duplicate" is intentionally
/// conservative and may still represent two distinct transactions.
ScreenshotImportDraft preferredScreenshotDuplicate(
  ScreenshotImportDraft earlier,
  ScreenshotImportDraft later,
) {
  final earlierScore = screenshotImportInformationScore(earlier);
  final laterScore = screenshotImportInformationScore(later);
  return laterScore > earlierScore ? later : earlier;
}

/// Apply a manual preset choice to ALL matching preview rows, not only
/// those visually below the edited row. Other manual overrides win.
void cascadeScreenshotPreset({
  required ScreenshotImportDraft changed,
  required Iterable<ScreenshotImportDraft> rows,
  required NodePreset selectedPreset,
}) {
  final platform = changed.platform;
  if (platform == null) return;
  final key = orderPresetMemoryKey(platform, changed.title);
  for (final row in rows) {
    if (row.id != changed.id &&
        (row.platform != platform ||
            orderPresetMemoryKey(platform, row.title) != key ||
            row.presetManuallyChanged ||
            row.nodeManuallyChanged)) {
      continue;
    }
    row.presetId = selectedPreset.id;
    row.nodeId = resolveImportNode(
      preset: selectedPreset,
      recognizedPercent: row.recognizedPercent,
    ).id;
    if (row.id == changed.id) {
      row.presetManuallyChanged = true;
      row.nodeManuallyChanged = false;
    }
  }
}
