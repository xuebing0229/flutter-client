import '../../orders/domain/queue_order.dart';

/// The artwork title is user data. Only normalize whitespace for comparisons;
/// never remove business prefixes such as 【常驻】.
String normalizedImportTitle(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Imported OCR can mention several apps, so require multiple distinguishing
/// signals before picking a platform. Uncertain cases stay user-selectable.
class PlatformGuess {
  const PlatformGuess(this.platform, this.confidence);

  final CommissionPlatform? platform;
  final double confidence;
}

PlatformGuess preselectImportPlatform(Iterable<String> recognizedLines) {
  final text = recognizedLines.join(' ');
  if (text.contains('米画师') && !text.contains('画加')) {
    return const PlatformGuess(CommissionPlatform.mihuashi, 1);
  }
  if (text.contains('画加') && !text.contains('米画师')) {
    return const PlatformGuess(CommissionPlatform.huajia, 1);
  }

  // Both platforms have order DETAILS. Shared words such as "订单",
  // "稿件" and "参考信息" never prove that a page is MiHuashi.
  final huajiaDetail = <String>['订单动态', '改价历史', '真爱永恒']
      .where(text.contains).length;
  if (huajiaDetail >= 2 &&
      (text.contains('订单已完成') || text.contains('稿件'))) {
    return const PlatformGuess(CommissionPlatform.huajia, 0.95);
  }
  final miSpecific = <String>['稿件夹', '进程动态',
    '联系企划方', '上传稿件', '约稿完成', '创作节点']
      .where(text.contains).length;
  if (miSpecific >= 2 && !text.contains('我卖出的') &&
      !text.contains('改价历史')) {
    return const PlatformGuess(CommissionPlatform.mihuashi, 0.95);
  }

  final huajia = <String>['我卖出的', '当前交付节点', '等待对方收稿', '待交稿']
      .where(text.contains).length;
  var mihuashi = <String>['企划方名称', '企划内容', '购买时间', '定向企划']
      .where(text.contains).length;
  // 米画师列表头可能只有“截稿时间 / 接单时间 / 购买时间”，
  // 不出现平台名字或企划文字。组合线索比只找单个词可靠。
  if (text.contains('购买时间') &&
      (text.contains('截稿时间') ||
          text.contains('接单时间') ||
          text.contains('默认'))) {
    mihuashi += 2;
  }

  if (huajia >= 2 && huajia > mihuashi) {
    return const PlatformGuess(CommissionPlatform.huajia, 0.85);
  }
  if (mihuashi >= 2 && mihuashi > huajia) {
    return const PlatformGuess(CommissionPlatform.mihuashi, 0.85);
  }
  return const PlatformGuess(null, 0);
}

/// Remember the user's previous template choice per platform + full order
/// name. Do not bind on buyer alone: the same artwork can have many clients.
String orderPresetMemoryKey(CommissionPlatform platform, String title) =>
    '${platform.name}|${normalizedImportTitle(title)}';

/// Prefer explicit previous user choices. Existing orders also serve as a
/// useful fallback when importing into an account without a saved hint.
NodePreset resolveImportPreset({
  required CommissionPlatform platform,
  required String title,
  required Iterable<NodePreset> presets,
  required Iterable<QueueOrder> existingOrders,
  Map<String, String> rememberedPresetIds = const <String, String>{},
}) {
  final available = {for (final preset in presets) preset.id: preset};
  if (available.isEmpty) {
    throw StateError('至少需要一个节点预设');
  }

  final key = orderPresetMemoryKey(platform, title);
  final remembered = available[rememberedPresetIds[key]];
  if (remembered != null) return remembered;

  final previous = existingOrders
      .where((order) =>
          order.platform == platform &&
          normalizedImportTitle(order.title) == normalizedImportTitle(title) &&
          available.containsKey(order.nodePresetId))
      .toList()
    ..sort((a, b) =>
        b.effectiveDefaultOrder.compareTo(a.effectiveDefaultOrder));
  if (previous.isNotEmpty) {
    return available[previous.first.nodePresetId]!;
  }
  return presets.first;
}

/// The app uses fixed percentages on node definitions. A recognized progress
/// value is never approximated to another node. An absent or ambiguous match
/// means the first node of the selected preset.
NodeDefinition resolveImportNode({
  required NodePreset preset,
  int? recognizedPercent,
  String? recognizedNodeName,
}) {
  if (preset.nodes.isEmpty) {
    throw StateError('节点预设不可为空');
  }

  // Percentage is the user's primary matching rule. A conflicting node name
  // must not override an exact percent, and no approximate jumps are allowed.
  final rawNodeName = recognizedNodeName?.trim();
  if (recognizedPercent != null) {
    final matches = preset.nodes
        .where((node) => node.progressPercent == recognizedPercent)
        .toList();
    if (matches.length == 1) return matches.single;
    if (matches.length > 1 && rawNodeName != null) {
      final named = matches
          .where((node) => node.name.trim() == rawNodeName)
          .toList();
      if (named.length == 1) return named.single;
    }
    return preset.nodes.first;
  }

  if (rawNodeName != null && rawNodeName.isNotEmpty) {
    final matches = preset.nodes
        .where((node) => node.name.trim() == rawNodeName)
        .toList();
    if (matches.length == 1) return matches.single;
  }
  return preset.nodes.first;
}

/// Screen status bars, navigation bars and platform UI prompts are not artwork
/// titles. Filtering only applies to surrounding OCR lines, not the extracted
/// order title. Keep the original full title verbatim.
bool isScreenshotChromeLine({
  required String text,
  required double centerY,
  required double imageHeight,
}) {
  if (imageHeight <= 0) return false;
  final value = text.trim();
  final ratio = centerY / imageHeight;
  if (ratio < 0.045 &&
      (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value) ||
          RegExp(r'^(?:[345]G|Wi-?Fi|\d{1,3}%|\d+(?:\.\d+)? ?K/s)$',
                  caseSensitive: false)
              .hasMatch(value))) {
    return true;
  }
  return value == '添加备注' || value == '搜索排单';
}

/// An existing order is a possible duplicate only when all three fields have
/// reliable data; missing fields must cause a manual-review state, never an
/// automatic merge or overwrite.
bool hasPotentialOrderDuplicate({
  required CommissionPlatform platform,
  required String title,
  required String clientName,
  required DateTime? deadline,
  required Iterable<QueueOrder> existingOrders,
}) {
  if (title.trim().isEmpty || clientName.trim().isEmpty || deadline == null) {
    return false;
  }

  bool sameDateTime(DateTime a, DateTime b) =>
      a.isAtSameMomentAs(b);
  final normalizedTitle = normalizedImportTitle(title);
  final normalizedClient = normalizedImportTitle(clientName);

  return existingOrders.any((order) =>
      order.platform == platform &&
      normalizedImportTitle(order.title) == normalizedTitle &&
      normalizedImportTitle(order.clientName) == normalizedClient &&
      order.deadline != null &&
      sameDateTime(order.deadline!, deadline));
}
