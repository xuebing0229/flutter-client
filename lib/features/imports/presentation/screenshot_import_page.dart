// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/portability/data_portability_file_bridge.dart';
import '../../orders/data/node_presets.dart';
import '../../orders/domain/queue_order.dart';
import '../../orders/state/order_store.dart';
import '../../products/domain/finished_product.dart';
import '../../products/state/product_store.dart';
import '../data/screenshot_ocr_service.dart';
import '../data/screenshot_ocr_diagnostic.dart';
import '../data/screenshot_import_history.dart';
import '../domain/screenshot_duplicate_review.dart';
import '../domain/screenshot_import_draft.dart';
import '../domain/screenshot_import_rules.dart';
import '../domain/screenshot_layout_parser.dart';
import '../domain/screenshot_mihuashi_badge.dart';
import '../domain/screenshot_huajia_detail_parser.dart';
import '../domain/screenshot_title_reconciliation.dart';
import '../domain/screenshot_product_layout_parser.dart';

enum ScreenshotImportKind { orders, products }

/// One preview across many images. The OCR engine never writes business data.
/// Every record is validated before one atomic store replacement.
class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({
    required this.kind,
    required this.accountId,
    required this.orderStore,
    required this.productStore,
    required this.presetStore,
    super.key,
  });

  final ScreenshotImportKind kind;
  final String accountId;
  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore presetStore;

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _ocr = const ScreenshotOcrService();
  final _history = const ScreenshotImportHistory();
  Set<String> _importedFingerprints = <String>{};
  final _pick = const DataPortabilityFileBridge();
  final _ordersParser = const ScreenshotLayoutParser();
  final _productsParser = const ScreenshotProductLayoutParser();
  final List<ScreenshotImportDraft> _rows = [];
  // Transient diagnostics only; nothing is uploaded or persisted.
  final List<String> _ocrDiagnostics = [];
  int _imageSerial = 0;
  int _rowSerial = 0;
  bool _working = false;
  String _recognitionStep = '准备识别';
  ProductSaleType _defaultSaleType = ProductSaleType.single;

  bool get _products => widget.kind == ScreenshotImportKind.products;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resumeOrSelectScreenshot());
    });
  }

  Future<void> _resumeOrSelectScreenshot() async {
    if (Platform.isAndroid) {
      try {
        final previous = await _ocr.lastNativeCrashReport();
        if (!mounted) return;
        if (previous != null && previous.isNotEmpty) {
          // Keep the one-time system exit record available behind the
          // diagnostics button, but never interrupt ordinary importing with
          // a stale crash snackbar or an extra tap.
          setState(() {
            _ocrDiagnostics.add(previous);
          });
        }
      } catch (error) {
        // Reporting should never block ordinary screenshot selection.
        _ocrDiagnostics.add('读取 Android 退出信息失败：$error');
      }
    }
    if (mounted) await _pickAndRecognize();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _copyOcrDiagnostic() async {
    if (_ocrDiagnostics.isEmpty) {
      _message('请先选择截图并等待识别结束');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('复制本机 OCR 诊断？'),
        content: const Text(
          '报告包含截图里识别到的文字及位置，包括图名、单主、价格、日期。'
          '不包含原始图片、文件路径或账号凭据，也不会自动上传。'
          '复制后文字会进入系统剪贴板，请确认愿意分享这些信息。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('复制诊断文字'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final output = StringBuffer()
      ..writeln('冒险者公会 · 截图 OCR 本机诊断')
      ..writeln('类型：' + (_products ? '成品' : '排单'))
      ..writeln('以下为手机实际 OCR 输出，不是原始截图。')
      ..writeln();
    for (final item in _ocrDiagnostics) {
      output.writeln(item);
    }
    output.writeln('--- 当前识别预览（可能经过人工编辑） ---');
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      output.writeln(
        '${i + 1}. ${row.sourceImageId} | 图名=${row.title} '
        '| 单主=${row.clientName} | 平台=${row.platform?.label ?? "待选择"} '
        '| 稿价=${row.price?.toString() ?? "未识别"} '
        '| 截稿日期=${row.detectedDate?.toIso8601String() ?? "未识别"} '
        '| 已确认截稿=${row.deadline?.toIso8601String() ?? "未设置"}',
      );
    }
    try {
      await Clipboard.setData(ClipboardData(text: output.toString()));
      _message('OCR 诊断文字已复制，可粘贴到聊天中核对');
    } catch (error) {
      _message('复制 OCR 诊断失败：$error');
    }
  }

  Future<void> _pickAndRecognize() async {
    if (_working) return;
    if (!_ocr.supported) {
      _message('当前平台的离线 OCR 引擎仍在适配中；暂时请使用手动导入。');
      return;
    }

    try {
      final selected = await _pick.pickImages();
      if (selected.isEmpty) return;
      setState(() {
        _working = true;
        _recognitionStep = '准备读取截图';
      });
      _importedFingerprints =
          await _history.read(accountId: widget.accountId);

      final generated = <ScreenshotImportDraft>[];
      var unreadable = 0;
      String? firstError;
      for (final image in selected) {
        final imageId = 'shot-' + (++_imageSerial).toString();
        try {
          if (mounted) {
            setState(() => _recognitionStep =
                'PP-OCRv6：识别截图 $_imageSerial/${selected.length}');
          }
          final imageHash = await _history.hashImage(image.path);
          final ocrTimer = Stopwatch()..start();
          final recognized = await _ocr.recognize(image.path);
          ocrTimer.stop();
          final parsedForReport = <String>[];
          final guess = preselectImportPlatform(
            recognized.lines.map((line) => line.text),
          );
          // Detect the actual platform's detail layout before assigning an
          // order to any app. A detail page is not automatically MiHuashi:
          // Huajia also has a single-order page with attachment timestamps.
          final huajiaDetail = !_products &&
              isHuajiaOrderDetailScreenshot(
                lines: recognized.lines,
                imageWidth: recognized.width,
                imageHeight: recognized.height,
              );
          final mihuashiDetail = !_products && !huajiaDetail &&
              isMiHuashiOrderDetailScreenshot(
                lines: recognized.lines,
                imageWidth: recognized.width,
                imageHeight: recognized.height,
              );
          final platform = huajiaDetail
              ? CommissionPlatform.huajia
              : mihuashiDetail
                  ? CommissionPlatform.mihuashi
                  : guess.platform;
          if (_products) {
            final found = _productsParser.parse(
              lines: recognized.lines,
              imageHeight: recognized.height,
              platform: platform,
            );
            for (var cardIndex = 0; cardIndex < found.length; cardIndex++) {
              final candidate = found[cardIndex];
              parsedForReport.add(
                '成品 ${cardIndex + 1}: 图名=${candidate.title}'
                ' | 售价=${candidate.price?.toString() ?? "未识别"}',
              );
              generated.add(_draft(
                imageId: imageId,
                fingerprint: screenshotCardFingerprint(
                  imageSha256: imageHash,
                  cardIndex: cardIndex,
                  products: true,
                ),
                imagePath: image.path,
                title: candidate.title,
                client: '',
                price: candidate.price,
                platform: platform,
              ));
            }
          } else {
            final found = huajiaDetail
                ? const ScreenshotHuajiaDetailParser().parse(
                    lines: recognized.lines,
                    imageHeight: recognized.height,
                    imageWidth: recognized.width,
                  )
                : _ordersParser.parse(
                    lines: recognized.lines,
                    imageHeight: recognized.height,
                    imageWidth: recognized.width,
                  );
            if (mounted) {
              setState(() => _recognitionStep =
                  '整理识别结果 $_imageSerial/${selected.length}');
            }
            // MiHuashi list cards often contain the same work sold to
            // different buyers. Resolve tiny OCR spelling differences before
            // selecting the same-title workflow preset for each draft.
            final reconciledTitles = platform == CommissionPlatform.mihuashi
                ? reconcileMiHuashiScreenshotTitles(found)
                : [for (final candidate in found) candidate.title];
            for (var cardIndex = 0; cardIndex < found.length; cardIndex++) {
              final candidate = found[cardIndex];
              final directed = hasDirectedCommissionBadge(
                platform: platform,
                candidate: candidate,
              );
              final cleanTitle = directed
                  ? removeDirectedCommissionPrefix(reconciledTitles[cardIndex])
                  : reconciledTitles[cardIndex];
              parsedForReport.add(
                '排单 ${cardIndex + 1}: 原图名=${candidate.title}'
                ' | 校正图名=$cleanTitle'
                ' | 标签=${directed ? directedCommissionTag : "无"}'
                ' | 单主=${candidate.clientName}'
                ' | 稿价=${candidate.price?.toString() ?? "未识别"}'
                ' | 截稿=${candidate.detectedDate?.toIso8601String() ?? "未识别"}'
                ' | 时间明确=${candidate.deadlineHasTime}'
                ' | 进度=${candidate.progressPercent?.toString() ?? "未识别"}',
              );
              generated.add(_draft(
                imageId: imageId,
                fingerprint: screenshotCardFingerprint(
                  imageSha256: imageHash,
                  cardIndex: cardIndex,
                  products: false,
                ),
                imagePath: image.path,
                title: cleanTitle,
                tags: directed ? const <String>[directedCommissionTag] : const <String>[],
                client: candidate.clientName,
                price: candidate.price,
                platform: platform,
                date: candidate.detectedDate,
                hasTime: candidate.deadlineHasTime,
                percentage: candidate.progressPercent,
                relative: candidate.relativeDeadlineText,
                sourceStartY: candidate.sourceStartY,
                sourceEndY: candidate.sourceEndY,
                imageWidth: recognized.width,
                imageHeight: recognized.height,
                titleBox: candidate.titleBox,
                clientBox: candidate.clientBox,
                priceBox: candidate.priceBox,
                deadlineBox: candidate.deadlineBox,
              ));
            }
          }
          _ocrDiagnostics.add(
            '唯一 OCR 引擎：${Platform.isAndroid ? "官方 PaddleOCR PP-OCRv6 Small" : "RapidOCR ONNX Windows"}；'
            '耗时 ${ocrTimer.elapsedMilliseconds} ms\n' +
            formatScreenshotOcrDiagnostic(
              screenshotNumber: _imageSerial,
              ocr: recognized,
              route: _products
                  ? '成品橱窗'
                  : huajiaDetail
                      ? '画加详情页'
                      : mihuashiDetail
                          ? '米画师详情页'
                          : '排单列表或未识别详情页',
              platform: platform?.label ?? '待选择',
              parsedRows: parsedForReport,
            ),
          );
        } catch (error) {
          _ocrDiagnostics.add('截图 $_imageSerial 识别失败：$error\n');
          unreadable++;
          firstError ??= error.toString();
        }
      }

      // Reconcile titles across the ENTIRE multi-image selection as well as
      // within individual screenshots. Otherwise two matching cards in one
      // screenshot and an OCR-variant in another never share a preset.
      // Only newly recognized, unedited draft titles are eligible.
      if (!_products) {
        final miRows = generated.where(
          (row) => row.platform == CommissionPlatform.mihuashi,
        ).toList();
        final candidates = [
          for (final row in miRows)
            ScreenshotOrderCandidate(
              title: row.title,
              clientName: row.clientName,
              detectedDate: row.detectedDate,
              deadlineHasTime: row.sourceHasClock,
              relativeDeadlineText: row.relativeDeadline,
              price: row.price,
              progressPercent: row.recognizedPercent,
              sourceLines: const [],
              sourceStartY: 0,
              sourceEndY: 0,
            ),
        ];
        final titles = reconcileMiHuashiScreenshotTitles(candidates);
        for (var index = 0; index < miRows.length; index++) {
          final row = miRows[index];
          if (row.title == titles[index]) continue;
          row.title = titles[index];
          // The OCR correction must happen before a same-title preset is
          // resolved; merely changing the preview label leaves the wrong
          // workflow bound to the record.
          var preset = resolveImportPreset(
            platform: CommissionPlatform.mihuashi,
            title: row.title,
            presets: widget.presetStore.presets,
            existingOrders: widget.orderStore.orders,
          );
          final key = orderPresetMemoryKey(CommissionPlatform.mihuashi, row.title);
          for (final previous in _rows.reversed) {
            if (previous.platform == CommissionPlatform.mihuashi &&
                previous.presetManuallyChanged &&
                orderPresetMemoryKey(CommissionPlatform.mihuashi, previous.title) == key) {
              preset = widget.presetStore.byId(previous.presetId);
              break;
            }
          }
          row.presetId = preset.id;
          row.nodeId = resolveImportNode(
            preset: preset,
            recognizedPercent: row.recognizedPercent,
          ).id;
        }
      }

      if (!mounted) return;
      setState(() {
        _rows.addAll(generated);
        _refreshDuplicateWarnings();
      });
      if (generated.isEmpty) {
        _message(firstError == null
            ? '没有识别到订单卡片，可以补充漏识别条目或换张完整截图。'
            : '离线识别失败：$firstError');
      } else if (unreadable > 0) {
        _message('有 ' + unreadable.toString() + ' 张截图识别失败，其余已保留。');
      }
    } catch (error) {
      if (!mounted) return;
      _message('读取截图失败：' + error.toString());
    } finally {
      // One ONNX session for all screenshots in THIS selection. Release it
      // before the next selection; draft editing does not retain the model.
      try {
        await _ocr.release();
      } catch (error) {
        _ocrDiagnostics.add('OCR 模型资源释放失败：$error');
      }
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  ScreenshotImportDraft _draft({
    required String imageId,
    String? fingerprint,
    String? imagePath,
    double? sourceStartY,
    double? sourceEndY,
    double? imageWidth,
    double? imageHeight,
    ScreenshotTextLine? titleBox,
    ScreenshotTextLine? clientBox,
    ScreenshotTextLine? priceBox,
    ScreenshotTextLine? deadlineBox,
    required String title,
    required String client,
    required double? price,
    required CommissionPlatform? platform,
    List<String> tags = const <String>[],
    DateTime? date,
    bool hasTime = false,
    int? percentage,
    String? relative,
  }) {
    final suggestedPreset = platform == null
        ? widget.presetStore.presets.first
        : resolveImportPreset(
            platform: platform,
            title: title,
            presets: widget.presetStore.presets,
            existingOrders: widget.orderStore.orders,
          );
    // An unsaved preset choice in this preview should also apply to
    // screenshots selected *after* the user edited an earlier batch row.
    var presetForRow = suggestedPreset;
    if (platform != null) {
      final key = orderPresetMemoryKey(platform, title);
      for (final existingDraft in _rows.reversed) {
        if (existingDraft.presetManuallyChanged &&
            existingDraft.platform == platform &&
            orderPresetMemoryKey(platform, existingDraft.title) == key) {
          presetForRow = widget.presetStore.byId(existingDraft.presetId);
          break;
        }
      }
    }
    final selectedNode = resolveImportNode(
      preset: presetForRow,
      recognizedPercent: percentage,
    );
    return ScreenshotImportDraft(
      id: 'preview-' + DateTime.now().microsecondsSinceEpoch.toString() +
          '-' + (++_rowSerial).toString(),
      sourceImageId: imageId,
      sourceFingerprint: fingerprint,
      sourceImagePath: imagePath,
      sourceStartY: sourceStartY,
      sourceEndY: sourceEndY,
      sourceImageWidth: imageWidth,
      sourceImageHeight: imageHeight,
      titleBox: titleBox,
      clientBox: clientBox,
      priceBox: priceBox,
      deadlineBox: deadlineBox,
      title: title,
      clientName: client,
      price: price,
      platform: platform,
      tags: normalizeOrderTags(tags),
      detectedDate: date,
      sourceHasClock: hasTime,
      recognizedPercent: percentage,
      relativeDeadline: relative,
      deadline: hasTime ? date : null,
      deadlineConfirmed: hasTime,
      feeEnabled: platform?.defaultFeeEnabled ?? false,
      saleType: _defaultSaleType,
      presetId: presetForRow.id,
      nodeId: selectedNode.id,
    );
  }

  void _refreshDuplicateWarnings() {
    for (final row in _rows) {
      row.duplicateWarning = null;
      if (row.duplicateAutoSkipped) {
        row.selected = true;
        row.duplicateAutoSkipped = false;
      }
    }
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      // Exact same screenshot + same card, including a repeated import
      // after relaunch. Never hide other distinct cards in that screenshot.
      final fingerprint = row.sourceFingerprint;
      final wasImported = fingerprint != null &&
          _importedFingerprints.contains(fingerprint);
      final inThisBatch = fingerprint != null &&
          _rows.take(index).any(
            (previous) => previous.sourceFingerprint == fingerprint,
          );
      if (wasImported || inThisBatch) {
        row.duplicateWarning = wasImported
            ? '这张截图的这一条已导入过，默认跳过'
            : '本批次重复选择了相同截图，默认跳过';
        if (!row.duplicateReviewed) {
          row.selected = false;
          row.duplicateAutoSkipped = true;
        }
        continue;
      }
      final platform = row.platform;
      if (platform == null || row.title.trim().isEmpty) continue;
      if (_products) {
        final duplicateInStore = widget.productStore.products.any(
          (existing) => existing.platform == platform &&
              normalizedImportTitle(existing.title) ==
                  normalizedImportTitle(row.title),
        );
        final duplicateInPreview = _rows.take(index).any(
          (other) => other.platform == platform &&
              normalizedImportTitle(other.title) ==
                  normalizedImportTitle(row.title),
        );
        if (duplicateInStore || duplicateInPreview) {
          row.duplicateWarning = duplicateInStore
              ? '已有同名成品，默认跳过' : '本批次同名橱窗，默认跳过';
          if (!row.duplicateReviewed) {
            row.selected = false;
            row.duplicateAutoSkipped = true;
          }
        }
        continue;
      }
      final comparisonDate = row.deadline ?? row.detectedDate;
      // The image may omit a deadline, or the imported record may have one
      // manually filled later. Same buyer+title+platform still merits REVIEW,
      // never silently merging two genuinely independent purchases.
      final existing = widget.orderStore.orders.any((order) =>
          order.platform == platform &&
          normalizedImportTitle(order.title) ==
              normalizedImportTitle(row.title) &&
          normalizedImportTitle(order.clientName) ==
              normalizedImportTitle(row.clientName) &&
          row.clientName.trim().isNotEmpty &&
          (comparisonDate == null || order.deadline == null ||
              (row.sourceHasClock
                  ? _sameMinute(order.deadline!, comparisonDate)
                  : _sameDay(order.deadline!, comparisonDate))));
      ScreenshotImportDraft? duplicatePeer;
      for (final other in _rows.take(index)) {
        if (other.platform == null || other.platform != platform) continue;
        final otherComparisonDate = other.deadline ?? other.detectedDate;
        final comparison = reviewScreenshotDuplicate(
          ScreenshotImportIdentity(
            platform: platform,
            title: row.title,
            clientName: row.clientName,
            imageInstanceId: row.sourceImageId,
            cardInstanceId: row.id,
            sourceDate: comparisonDate,
            datePrecision: row.sourceHasClock
                ? ScreenshotDatePrecision.minute
                : ScreenshotDatePrecision.day,
          ),
          ScreenshotImportIdentity(
            platform: other.platform!,
            title: other.title,
            clientName: other.clientName,
            imageInstanceId: other.sourceImageId,
            cardInstanceId: other.id,
            sourceDate: otherComparisonDate,
            datePrecision: other.sourceHasClock
                ? ScreenshotDatePrecision.minute
                : ScreenshotDatePrecision.day,
          ),
        );
        if (comparison == ScreenshotDuplicateReview.possibleDuplicate ||
            comparison == ScreenshotDuplicateReview.insufficientEvidence) {
          duplicatePeer = other;
          break;
        }
      }

      if (existing) {
        row.duplicateWarning = '与已有排单疑似重复';
        if (!row.duplicateReviewed) {
          row.selected = false;
          row.duplicateAutoSkipped = true;
        }
        continue;
      }

      if (duplicatePeer != null) {
        final other = duplicatePeer;
        final preferred = preferredScreenshotDuplicate(other, row);
        final keepCurrent = identical(preferred, row);

        if (!row.duplicateReviewed && !other.duplicateReviewed) {
          if (keepCurrent) {
            // A later screenshot can contain a more precise deadline or more
            // recognized fields. In that case swap the default selection
            // instead of blindly keeping the first imported screenshot.
            other.selected = false;
            other.duplicateAutoSkipped = true;
            row.selected = true;
            row.duplicateAutoSkipped = false;
          } else {
            row.selected = false;
            row.duplicateAutoSkipped = true;
          }
        }

        if (keepCurrent) {
          row.duplicateWarning = '与其他截图的排单疑似重复；默认保留信息更完整的这一条';
          if (other.duplicateWarning == null ||
              other.duplicateAutoSkipped) {
            other.duplicateWarning = '与其他截图的排单疑似重复；默认跳过较少信息版本';
          }
        } else {
          row.duplicateWarning = '与其他截图的排单疑似重复；默认跳过较少信息版本';
          other.duplicateWarning ??=
              '与其他截图的排单疑似重复；默认保留信息更完整的这一条';
        }
      }
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameMinute(DateTime a, DateTime b) =>
      _sameDay(a, b) && a.hour == b.hour && a.minute == b.minute;

  Future<void> _bulkCompleteMissingTimes() async {
    final targets = _rows.where((row) =>
        row.selected && !row.deadlineConfirmed &&
        row.detectedDate != null &&
        row.relativeDeadline == null).toList();
    if (targets.isEmpty) {
      _message('当前没有可批量补充时间的排单');
      return;
    }
    final choice = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
      helpText: '批量设定截稿时分（仅补未确认的排单）',
    );
    if (!mounted || choice == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量补全截稿时间'),
        content: Text(
          '将为 ${targets.length} 条仅识别到日期的排单设置 '
          '${choice.format(context)}。快速橱窗可能不是按日截稿，'
          '请确认这些订单适用你选定的时分。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('应用并确认'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() {
      for (final row in targets) {
        final date = row.detectedDate!;
        row.deadline = DateTime(
          date.year, date.month, date.day, choice.hour, choice.minute,
        );
        row.deadlineConfirmed = true;
      }
    });
  }


  Future<void> _inspectScreenshot(
    ScreenshotImportDraft row, {
    ScreenshotTextLine? highlight,
  }) async {
    final path = row.sourceImagePath;
    if (path == null) return;
    final imageWidth = row.sourceImageWidth;
    final imageHeight = row.sourceImageHeight;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(dialogContext).width * 0.93, 740),
          height: math.min(MediaQuery.sizeOf(dialogContext).height * 0.84, 820),
          child: Column(
            children: [
              ListTile(
                title: const Text('OCR 原始截图'),
                subtitle: Text(row.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    if (imageWidth == null || imageHeight == null ||
                        imageWidth <= 0 || imageHeight <= 0) {
                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        child: Image.file(File(path), fit: BoxFit.contain),
                      );
                    }
                    final scale = math.min(
                      constraints.maxWidth / imageWidth,
                      constraints.maxHeight / imageHeight,
                    );
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 6,
                      child: Center(
                        child: SizedBox(
                          width: imageWidth * scale,
                          height: imageHeight * scale,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.file(File(path),
                                    fit: BoxFit.fill),
                              ),
                              if (highlight != null)
                                Positioned(
                                  left: highlight.left * scale,
                                  top: highlight.top * scale,
                                  width: math.max(1,
                                      (highlight.right - highlight.left) * scale),
                                  height: math.max(1,
                                      (highlight.bottom - highlight.top) * scale),
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(dialogContext)
                                            .colorScheme.primary
                                            .withValues(alpha: 0.16),
                                        border: Border.all(
                                          color: Theme.of(dialogContext)
                                              .colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('已框选 OCR 来源文字，可双指缩放核对'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addManualPreviewRow() {
    setState(() {
      _rows.add(_draft(
        imageId: 'manual',
        title: '',
        client: '',
        price: null,
        platform: null,
      ));
    });
  }

  Future<void> _editDeadline(ScreenshotImportDraft row) async {
    final basis = row.deadline ?? row.detectedDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: basis,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(basis),
    );
    if (!mounted || time == null) return;
    setState(() {
      row.deadline = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
      row.deadlineConfirmed = true;
    });
  }

  void _changePlatform(ScreenshotImportDraft row, CommissionPlatform value) {
    setState(() {
      row.platform = value;
      row.feeEnabled = value.defaultFeeEnabled;
      if (!_products && !row.presetManuallyChanged) {
        final preset = resolveImportPreset(
          platform: value,
          title: row.title,
          presets: widget.presetStore.presets,
          existingOrders: widget.orderStore.orders,
        );
        row.presetId = preset.id;
        row.nodeId = resolveImportNode(
          preset: preset,
          recognizedPercent: row.recognizedPercent,
        ).id;
      }
      _refreshDuplicateWarnings();
    });
  }

  Future<void> _confirm() async {
    // Titles and buyers can change in the editable preview. Recheck against
    // both local records and all other screenshot rows just before writing.
    final previouslySelected = _rows.where((row) => row.selected).length;
    setState(_refreshDuplicateWarnings);
    final selected = _rows.where((row) => row.selected).toList();
    if (selected.length < previouslySelected) {
      _message('发现新的疑似重复项，已标注并默认取消勾选，请检查后再次确认。');
      return;
    }
    if (selected.isEmpty) {
      _message('没有选中要导入的记录');
      return;
    }
    for (final row in selected) {
      final issue = row.validate(importingProducts: _products);
      if (issue != null) {
        _message('「' + row.title + '」：' + issue);
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认批量导入？'),
        content: Text('将新增 ' + selected.length.toString() +
            ' 条' + (_products ? '成品' : '排单') +
            '。重复项只有手动勾选才会导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    if (_products) {
      final created = <FinishedProduct>[];
      final keys = <String>{};
      for (var i = 0; i < selected.length; i++) {
        final row = selected[i];
        final key = orderPresetMemoryKey(row.platform!, row.title);
        if (!keys.add(key)) continue; // one product per storefront
        created.add(FinishedProduct(
          id: 'product-import-' + (now + i).toString(),
          title: row.title.trim(),
          platform: row.platform!,
          saleType: row.saleType,
          price: row.price!,
          feeEnabled: row.feeEnabled,
          supplementFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          deductionFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          defaultOrder: now + i,
          // A storefront screenshot is NOT an individual sale.
          soldCount: 0,
          saleRecords: const [],
        ));
      }
      widget.productStore.replaceAll([
        ...widget.productStore.products,
        ...created,
      ]);
    } else {
      final created = <QueueOrder>[];
      for (var i = 0; i < selected.length; i++) {
        final row = selected[i];
        final preset = widget.presetStore.byId(row.presetId);
        created.add(QueueOrder(
          id: 'order-import-' + (now + i).toString(),
          title: row.title.trim(),
          clientName: row.clientName.trim(),
          platform: row.platform!,
          tags: normalizeOrderTags(row.tags),
          deadline: row.deadline,
          nodePresetId: preset.id,
          nodePresetSnapshot: preset.snapshot(),
          currentNodeId: row.nodeId,
          price: row.price!,
          feeEnabled: row.feeEnabled,
          supplementFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          deductionFeeEnabled: row.platform!.defaultAdjustmentFeeEnabled,
          defaultOrder: now + i,
        ));
      }
      widget.orderStore.replaceAll([
        ...widget.orderStore.orders,
        ...created,
      ]);
    }
    // The business write has succeeded. A failed provenance write must not
    // lose an already imported order or pretend it was not committed.
    try {
      final fingerprints = selected
          .map((row) => row.sourceFingerprint)
          .whereType<String>();
      await _history.markImported(
        accountId: widget.accountId,
        fingerprints: fingerprints,
      );
    } catch (_) {
      if (mounted) {
        _message('导入成功，但本机截图去重记录保存失败；下次请检查疑似重复提示。');
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final count = _rows.where((r) => r.selected).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_products ? '截图导入成品' : '截图导入排单'),
        actions: [
          IconButton(
            tooltip: '复制 OCR 诊断（不会上传原图）',
            onPressed: _working || _ocrDiagnostics.isEmpty
                ? null
                : () => unawaited(_copyOcrDiagnostic()),
            icon: const Icon(Icons.bug_report_outlined),
          ),
          TextButton.icon(
            onPressed: _working ? null : () => unawaited(_pickAndRecognize()),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('选择截图'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_working) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(_recognitionStep, textAlign: TextAlign.center),
            ),
          ],
          if (_products)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<ProductSaleType>(
                segments: const [
                  ButtonSegment(
                    value: ProductSaleType.single,
                    label: Text('单次售卖'),
                  ),
                  ButtonSegment(
                    value: ProductSaleType.multiple,
                    label: Text('多次售卖'),
                  ),
                ],
                selected: {_defaultSaleType},
                onSelectionChanged: (selection) => setState(() {
                  _defaultSaleType = selection.first;
                  for (final row in _rows) {
                    row.saleType = _defaultSaleType;
                  }
                }),
              ),
            ),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已识别 ' + _rows.length.toString() +
                          ' 条，选中 ' + count.toString() + ' 条',
                    ),
                  ),
                  if (!_products)
                    TextButton(
                      onPressed: () => unawaited(_bulkCompleteMissingTimes()),
                      child: const Text('批量补时间'),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '批量修改平台、预设和手续费',
                    onSelected: (value) => setState(() {
                      if (value.startsWith('platform:')) {
                        final p = CommissionPlatform.values.firstWhere(
                          (candidate) => candidate.name ==
                              value.substring('platform:'.length),
                        );
                        for (final row in _rows) {
                          row.platform = p;
                          row.feeEnabled = p.defaultFeeEnabled;
                          if (!_products && !row.presetManuallyChanged &&
                              !row.nodeManuallyChanged) {
                            final preset = resolveImportPreset(
                              platform: p,
                              title: row.title,
                              presets: widget.presetStore.presets,
                              existingOrders: widget.orderStore.orders,
                            );
                            row.presetId = preset.id;
                            row.nodeId = resolveImportNode(
                              preset: preset,
                              recognizedPercent: row.recognizedPercent,
                            ).id;
                          }
                        }
                        _refreshDuplicateWarnings();
                      } else if (value.startsWith('preset:')) {
                        final preset = widget.presetStore.byId(
                          value.substring('preset:'.length),
                        );
                        for (final row in _rows) {
                          if (!row.selected) continue;
                          row.presetId = preset.id;
                          row.nodeId = resolveImportNode(
                            preset: preset,
                            recognizedPercent: row.recognizedPercent,
                          ).id;
                          row.presetManuallyChanged = true;
                          row.nodeManuallyChanged = false;
                        }
                      } else if (value == 'fee:on' || value == 'fee:off') {
                        for (final row in _rows) {
                          if (row.selected) {
                            row.feeEnabled = value == 'fee:on';
                          }
                        }
                      }
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem<String>(
                        enabled: false, child: Text('批量选择平台'),
                      ),
                      for (final p in CommissionPlatform.values)
                        PopupMenuItem(
                          value: 'platform:${p.name}',
                          child: Text(p.label),
                        ),
                      if (!_products) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          enabled: false, child: Text('批量选择节点预设'),
                        ),
                        for (final preset in widget.presetStore.presets)
                          PopupMenuItem(
                            value: 'preset:${preset.id}',
                            child: Text(preset.name),
                          ),
                      ],
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'fee:on', child: Text('已选项：开启手续费'),
                      ),
                      const PopupMenuItem(
                        value: 'fee:off', child: Text('已选项：关闭手续费'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('批量设置 ▾'),
                    ),
                  ),
                ],
              ),
            ),
          if (!_working && _rows.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addManualPreviewRow,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('补充漏识别的条目'),
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _working
                            ? '正在本机识别截图…'
                            : '选择一张或多张平台订单截图，先识别并检查，确认后才会写入。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) =>
                        _buildRow(_rows[index], index),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: FilledButton.icon(
          onPressed: _working || count == 0 ? null : _confirm,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text('确认导入（' + count.toString() + '）'),
        ),
      ),
    );
  }

  Widget _buildRow(ScreenshotImportDraft row, int index) {
    final theme = Theme.of(context);
    final preset = widget.presetStore.byId(row.presetId);
    final dateValue = row.deadline;
    final dateLabel = dateValue == null
        ? (row.detectedDate == null ? '截稿时间待补充'
            : '已识别日期，时间待确认')
        : dateValue.year.toString() + '-' +
            dateValue.month.toString().padLeft(2, '0') + '-' +
            dateValue.day.toString().padLeft(2, '0') + ' ' +
            dateValue.hour.toString().padLeft(2, '0') + ':' +
            dateValue.minute.toString().padLeft(2, '0');

    return Card(
      key: ValueKey(row.id),
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        leading: Checkbox(
          value: row.selected,
          visualDensity: VisualDensity.compact,
          onChanged: (value) =>
              setState(() {
                row.selected = value ?? false;
                row.duplicateReviewed = true;
                row.duplicateAutoSkipped = false;
              }),
        ),
        title: Text(
          row.title.isEmpty ? '未识别图名' : row.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _products
                  ? '${row.platform?.label ?? '待选平台'} · ${row.price == null ? '待填价格' : '¥${row.price}'} · ${row.saleType.label}'
                  : '${row.clientName.isEmpty ? '待填单主' : row.clientName} · ${row.platform?.label ?? '待选平台'} · ${row.price == null ? '待填稿价' : '¥${row.price}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (!_products)
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            if (!_products && row.tags.isNotEmpty)
              Text(
                '标签：' + row.tags.join('、'),
                style: theme.textTheme.labelSmall,
              ),
            if (row.duplicateWarning != null)
              Text(
                row.duplicateWarning!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          tooltip: '删除这条识别结果',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 19),
          onPressed: () => setState(() {
            _rows.remove(row);
            _refreshDuplicateWarnings();
          }),
        ),
        children: [
            if (row.sourceImagePath != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => unawaited(_inspectScreenshot(row)),
                  icon: const Icon(Icons.image_search_rounded),
                  label: const Text('核对原始截图'),
                ),
              ),
            if (row.duplicateWarning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  row.duplicateWarning! + '（勾选可仍然导入）',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            if (!_products && row.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in row.tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() {
                          row.tags = [
                            for (final existing in row.tags)
                              if (existing != tag) existing,
                          ];
                        }),
                      ),
                  ],
                ),
              ),
            TextFormField(
              key: ValueKey('${row.id}-title-${row.titleInputRevision}'),
              initialValue: row.title,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: '图名',
                isDense: true,
                suffixIcon: row.titleBox == null ? null : IconButton(
                  tooltip: '在原图定位图名',
                  icon: const Icon(Icons.image_search_rounded),
                  onPressed: () => unawaited(_inspectScreenshot(
                    row, highlight: row.titleBox,
                  )),
                ),
              ),
              onChanged: (value) => setState(() {
                row.title = value;
                _refreshDuplicateWarnings();
              }),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (!_products) ...[
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: ValueKey('${row.id}-client-${row.clientInputRevision}'),
                      initialValue: row.clientName,
                      decoration: InputDecoration(
                        labelText: '单主',
                        isDense: true,
                        suffixIcon: row.clientBox == null ? null : IconButton(
                          tooltip: '在原图定位单主',
                          icon: const Icon(Icons.image_search_rounded),
                          onPressed: () => unawaited(_inspectScreenshot(
                            row, highlight: row.clientBox,
                          )),
                        ),
                      ),
                      onChanged: (value) => setState(() {
                        row.clientName = value;
                        _refreshDuplicateWarnings();
                      }),
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: TextFormField(
                    key: ValueKey(row.id + '-price'),
                    initialValue: row.price?.toString() ?? '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '稿价 ¥',
                      isDense: true,
                      suffixIcon: row.priceBox == null ? null : IconButton(
                        tooltip: '在原图定位稿价',
                        icon: const Icon(Icons.image_search_rounded),
                        onPressed: () => unawaited(_inspectScreenshot(
                          row, highlight: row.priceBox,
                        )),
                      ),
                    ),
                    onChanged: (value) => setState(() {
                      row.price = double.tryParse(value.trim());
                      _refreshDuplicateWarnings();
                    }),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<CommissionPlatform>(
                    key: ValueKey(row.id + '-platform-' +
                        (row.platform?.name ?? 'unknown')),
                    initialValue: row.platform,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '平台', isDense: true,
                    ),
                    hint: const Text('请选择'),
                    items: [
                      for (final p in CommissionPlatform.values)
                        DropdownMenuItem(
                          value: p, child: Text(p.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _changePlatform(row, value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_products)
              Row(
                children: [
                  Expanded(
                    child: Text('成品不自动记录售出次数',
                        style: theme.textTheme.bodySmall),
                  ),
                  DropdownButton<ProductSaleType>(
                    value: row.saleType,
                    isDense: true,
                    items: [
                      for (final type in ProductSaleType.values)
                        DropdownMenuItem(
                          value: type, child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => row.saleType = value);
                      }
                    },
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_editDeadline(row)),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(dateLabel),
                  ),
                  if (row.deadlineBox != null)
                    IconButton(
                      tooltip: '在原图定位截稿日期',
                      icon: const Icon(Icons.image_search_rounded),
                      onPressed: () => unawaited(_inspectScreenshot(
                        row, highlight: row.deadlineBox,
                      )),
                    ),
                  if (!row.deadlineConfirmed &&
                      row.detectedDate != null &&
                      row.relativeDeadline == null &&
                      row.platform == CommissionPlatform.mihuashi)
                    TextButton(
                      onPressed: () => setState(() {
                        final d = row.detectedDate!;
                        row.deadline = DateTime(d.year, d.month, d.day, 23, 59);
                        row.deadlineConfirmed = true;
                      }),
                      child: const Text('确认普通按日 23:59'),
                    ),
                  if (!row.deadlineConfirmed)
                    TextButton(
                      onPressed: () => setState(() {
                        row.deadline = null;
                        row.deadlineConfirmed = true;
                      }),
                      child: const Text('主动设为未设置'),
                    ),
                  if (row.relativeDeadline != null)
                    Text(
                      row.relativeDeadline!,
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(row.id + '-preset-' + row.presetId),
                      initialValue: row.presetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '节点预设', isDense: true,
                      ),
                      items: [
                        for (final choice in widget.presetStore.presets)
                          DropdownMenuItem(
                            value: choice.id, child: Text(choice.name),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() => cascadeScreenshotPreset(
                          changed: row,
                          rows: _rows,
                          selectedPreset: widget.presetStore.byId(id),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(row.id + '-node-' + row.nodeId),
                      initialValue: row.nodeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '当前节点', isDense: true,
                      ),
                      items: [
                        for (final node in preset.nodes)
                          DropdownMenuItem(
                            value: node.id,
                            child: Text(node.name + ' ' +
                                node.progressPercent.toString() + '%'),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          row.nodeId = id;
                          row.nodeManuallyChanged = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
            Row(
              children: [
                const Text('收取平台手续费', style: TextStyle(fontSize: 12)),
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: row.feeEnabled,
                  onChanged: (value) =>
                      setState(() => row.feeEnabled = value ?? false),
                ),
                const Spacer(),
                if (row.recognizedPercent != null && !_products)
                  Text('截图进度 ' +
                      row.recognizedPercent.toString() + '%',
                      style: theme.textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}
