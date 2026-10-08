import '../../orders/domain/queue_order.dart';
import '../../products/domain/finished_product.dart';
import 'screenshot_import_rules.dart';

/// A mutable item held only by the import preview; no writes happen until
/// validate-and-commit. Separate cards retain their own stable preview IDs.
class ScreenshotImportDraft {
  ScreenshotImportDraft({
    required this.id,
    required this.sourceImageId,
    required this.title,
    required this.clientName,
    required this.price,
    required this.platform,
    required this.detectedDate,
    required this.recognizedPercent,
    this.sourceHasClock = false,
    required this.presetId,
    required this.nodeId,
    this.deadline,
    this.relativeDeadline,
    this.deadlineConfirmed = false,
    this.feeEnabled = false,
    this.saleType = ProductSaleType.single,
  });

  final String id;
  final String sourceImageId;
  String title;
  String clientName;
  double? price;
  CommissionPlatform? platform;
  final DateTime? detectedDate;
  /// Whether the actual screenshot contained HH:mm, not a user guess.
  final bool sourceHasClock;
  final int? recognizedPercent;
  final String? relativeDeadline;
  DateTime? deadline;
  bool deadlineConfirmed;
  bool feeEnabled;
  ProductSaleType saleType;
  bool selected = true;
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
