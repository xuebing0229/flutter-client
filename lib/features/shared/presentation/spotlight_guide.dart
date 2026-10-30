import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class QuickStartGuideTargets {
  QuickStartGuideTargets();

  final GlobalKey menuKey = GlobalKey(debugLabel: 'guide-menu');
  final GlobalKey searchKey = GlobalKey(debugLabel: 'guide-search');
  final GlobalKey toolbarKey = GlobalKey(debugLabel: 'guide-toolbar');
  final GlobalKey addOrderKey = GlobalKey(debugLabel: 'guide-add-order');
  final GlobalKey addOrderTitleKey = GlobalKey(debugLabel: 'guide-add-order-title');
  final GlobalKey addOrderClientKey = GlobalKey(debugLabel: 'guide-add-order-client');
  final GlobalKey addOrderPlatformKey = GlobalKey(debugLabel: 'guide-add-order-platform');
  final GlobalKey addOrderPriceKey = GlobalKey(debugLabel: 'guide-add-order-price');
  final GlobalKey addOrderSaveKey = GlobalKey(debugLabel: 'guide-add-order-save');
  final GlobalKey firstOrderCardKey = GlobalKey(debugLabel: 'guide-first-order-card');
  final GlobalKey firstOrderProgressKey =
      GlobalKey(debugLabel: 'guide-first-order-progress');
  final GlobalKey firstOrderConfirmNodeKey =
      GlobalKey(debugLabel: 'guide-first-order-confirm-node');
  final GlobalKey archivedOrderKey = GlobalKey(debugLabel: 'guide-archived-order');
  final GlobalKey screenshotImportKey = GlobalKey(debugLabel: 'guide-screenshot-import');
  final GlobalKey addProductKey = GlobalKey(debugLabel: 'guide-add-product');
  final GlobalKey productsTabKey = GlobalKey(debugLabel: 'guide-tab-products');
  final GlobalKey scheduleTabKey = GlobalKey(debugLabel: 'guide-tab-schedule');
  final GlobalKey statisticsTabKey = GlobalKey(debugLabel: 'guide-tab-statistics');
  final GlobalKey presetCenterKey = GlobalKey(debugLabel: 'guide-preset-center');
  final GlobalKey receiptCenterKey = GlobalKey(debugLabel: 'guide-receipt-center');
  final GlobalKey syncKey = GlobalKey(debugLabel: 'guide-sync');
  final GlobalKey accountDevicesKey = GlobalKey(debugLabel: 'guide-account-devices');
  final GlobalKey accountTitleKey = GlobalKey(debugLabel: 'guide-account-title');
  final GlobalKey settingsBackupKey = GlobalKey(debugLabel: 'guide-settings-backup');
  final GlobalKey featureToggleKey = GlobalKey(debugLabel: 'guide-feature-toggle');
  final GlobalKey featureToggleTitleKey =
      GlobalKey(debugLabel: 'guide-feature-toggle-title');
  final GlobalKey pwaInstallKey = GlobalKey(debugLabel: 'guide-pwa-install');

  GlobalKey? tabKey(String id) => switch (id) {
        'products' => productsTabKey,
        'schedule' => scheduleTabKey,
        'statistics' => statisticsTabKey,
        _ => null,
      };
}

class SpotlightTarget extends SingleChildRenderObjectWidget {
  const SpotlightTarget({
    GlobalKey? targetKey,
    required Widget child,
  }) : super(key: targetKey, child: child);

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderSpotlightTarget();
}

class _RenderSpotlightTarget extends RenderProxyBox {}

class SpotlightGuideStep {
  const SpotlightGuideStep({
    required this.targetKey,
    required this.icon,
    required this.title,
    required this.body,
    this.targetShape,
    this.targetPadding = 4,
    this.borderRadius = 12,
    this.preferCardAbove = false,
    this.allowOutsideTargetInteraction = false,
  });

  final GlobalKey targetKey;
  final IconData icon;
  final String title;
  final String body;
  final ShapeBorder? targetShape;
  final double targetPadding;
  final double borderRadius;
  final bool preferCardAbove;
  final bool allowOutsideTargetInteraction;
}

Future<bool> showSpotlightGuide(
  BuildContext context, {
  required List<SpotlightGuideStep> steps,
  String finalLabel = '开始使用',
  int progressStart = 0,
  int? progressTotal,
}) async {
  if (steps.isEmpty) return false;

  final overlay = Overlay.of(context);
  final completer = Completer<bool>();
  late final OverlayEntry entry;

  void complete(bool value) {
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: _SpotlightGuideOverlay(
        steps: steps,
        finalLabel: finalLabel,
        progressStart: progressStart,
        progressTotal: progressTotal,
        onComplete: complete,
      ),
    ),
  );
  overlay.insert(entry);

  return completer.future;
}

class _SpotlightGuideOverlay extends StatefulWidget {
  const _SpotlightGuideOverlay({
    required this.steps,
    required this.finalLabel,
    required this.progressStart,
    required this.progressTotal,
    required this.onComplete,
  });

  final List<SpotlightGuideStep> steps;
  final String finalLabel;
  final int progressStart;
  final int? progressTotal;
  final ValueChanged<bool> onComplete;

  @override
  State<_SpotlightGuideOverlay> createState() => _SpotlightGuideOverlayState();
}

class _SpotlightGuideOverlayState extends State<_SpotlightGuideOverlay> {
  int _index = 0;
  Rect? _targetRect;
  bool _targetRouteCovered = false;
  final GlobalKey _cardKey = GlobalKey(debugLabel: 'spotlight-guide-card');
  double _cardHeight = 196;

  SpotlightGuideStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_trackTarget);
  }

  void _trackTarget(Duration _) {
    if (!mounted) return;
    _refreshTarget();
    WidgetsBinding.instance.addPostFrameCallback(_trackTarget);
  }

  void _refreshTarget() {
    if (!mounted) return;
    final cardRenderObject = _cardKey.currentContext?.findRenderObject();
    final measuredCardHeight =
        cardRenderObject is RenderBox &&
                cardRenderObject.attached &&
                cardRenderObject.hasSize
            ? cardRenderObject.size.height
            : _cardHeight;

    final targetContext = _step.targetKey.currentContext;
    final targetRoute =
        targetContext == null ? null : ModalRoute.of(targetContext);
    final targetRouteCovered = targetRoute != null && !targetRoute.isCurrent;
    final box = targetContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      if (_targetRect == null &&
          _targetRouteCovered == targetRouteCovered &&
          (measuredCardHeight - _cardHeight).abs() < .5) {
        return;
      }
      setState(() {
        _targetRect = null;
        _targetRouteCovered = targetRouteCovered;
        _cardHeight = measuredCardHeight;
      });
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    final rect = (origin & box.size).inflate(_step.targetPadding);
    if (_targetRect == rect &&
        _targetRouteCovered == targetRouteCovered &&
        (measuredCardHeight - _cardHeight).abs() < .5) {
      return;
    }
    setState(() {
      _targetRect = rect;
      _targetRouteCovered = targetRouteCovered;
      _cardHeight = measuredCardHeight;
    });
  }

  Future<void> _dismissTransientRouteAboveTarget() async {
    final targetContext = _step.targetKey.currentContext;
    if (targetContext == null) return;
    final targetRoute = ModalRoute.of(targetContext);
    if (targetRoute == null || targetRoute.isCurrent) return;

    final navigator = Navigator.maybeOf(targetContext);
    if (navigator == null) return;
    await navigator.maybePop();
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _finish(bool value) async {
    await _dismissTransientRouteAboveTarget();
    if (!mounted) return;
    widget.onComplete(value);
  }

  Future<void> _move(int delta) async {
    await _dismissTransientRouteAboveTarget();
    if (!mounted) return;
    final next =
        (_index + delta).clamp(0, widget.steps.length - 1).toInt();
    if (next == _index) return;
    setState(() {
      _index = next;
      _targetRect = null;
      _targetRouteCovered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safeTop = media.padding.top + 12;
    final safeBottom =
        media.padding.bottom + media.viewInsets.bottom + 12;
    final colors = Theme.of(context).colorScheme;
    final rect = _targetRect;
    final isLast = _index == widget.steps.length - 1;

    final cardWidth =
        (size.width - 32).clamp(260.0, 420.0).toDouble();
    final cardHeight = _cardHeight;
    final spaceAbove =
        rect == null ? 0.0 : rect.top - safeTop - 16;
    final spaceBelow = rect == null
        ? 0.0
        : size.height - safeBottom - rect.bottom - 16;
    final preferBelow =
        rect == null || rect.bottom + cardHeight + 24 < size.height - safeBottom;
    final preferAbove =
        rect != null && _step.preferCardAbove && spaceAbove >= cardHeight;
    final cardTop = rect == null
        ? (size.height - cardHeight) / 2
        : preferAbove
            ? (rect.top - cardHeight - 16)
            : _targetRouteCovered
                ? (spaceAbove >= cardHeight && spaceBelow >= cardHeight
                    ? (spaceAbove <= spaceBelow
                        ? rect.top - cardHeight - 16
                        : rect.bottom + 16)
                    : spaceAbove >= cardHeight
                        ? rect.top - cardHeight - 16
                        : rect.bottom + 16)
                : preferBelow
                    ? (rect.bottom + 16)
                    : (rect.top - cardHeight - 16);
    final clampedTop = cardTop
        .clamp(safeTop, size.height - safeBottom - cardHeight)
        .toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_targetRouteCovered)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SpotlightMaskPainter(
                  targetRect: rect,
                  targetShape: _step.targetShape,
                  borderRadius: _step.borderRadius,
                ),
              ),
            ),
          ),
        if (!_targetRouteCovered && !_step.allowOutsideTargetInteraction)
          Positioned.fill(
            child: _SpotlightPointerBarrier(
              targetRect: rect,
              targetShape: _step.targetShape,
              borderRadius: _step.borderRadius,
            ),
          ),
          Positioned(
            left: (size.width - cardWidth) / 2,
            top: clampedTop,
            width: cardWidth,
            child: SafeArea(
              child: Card(
                key: _cardKey,
                elevation: 12,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _step.icon,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _step.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 5),
                                Text(_step.body),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if ((widget.progressTotal ?? widget.steps.length) > 1)
                            Text(
                              '${widget.progressStart + _index + 1} / ${widget.progressTotal ?? widget.steps.length}',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => unawaited(_finish(false)),
                            child: const Text('退出教程'),
                          ),
                          if (_index > 0)
                            TextButton(
                              onPressed: () => unawaited(_move(-1)),
                              child: const Text('上一步'),
                            ),
                          FilledButton(
                            onPressed: () {
                              if (isLast) {
                                unawaited(_finish(true));
                              } else {
                                unawaited(_move(1));
                              }
                            },
                            child: Text(isLast ? widget.finalLabel : '下一步'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ),
      ],
    );
  }
}


class _SpotlightPointerBarrier extends LeafRenderObjectWidget {
  const _SpotlightPointerBarrier({
    required this.targetRect,
    required this.targetShape,
    required this.borderRadius,
  });

  final Rect? targetRect;
  final ShapeBorder? targetShape;
  final double borderRadius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSpotlightPointerBarrier(
        targetRect: targetRect,
        targetShape: targetShape,
        borderRadius: borderRadius,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSpotlightPointerBarrier renderObject,
  ) {
    renderObject
      ..targetRect = targetRect
      ..targetShape = targetShape
      ..borderRadius = borderRadius;
  }
}

class _RenderSpotlightPointerBarrier extends RenderBox {
  _RenderSpotlightPointerBarrier({
    required Rect? targetRect,
    required ShapeBorder? targetShape,
    required double borderRadius,
  })  : _targetRect = targetRect,
        _targetShape = targetShape,
        _borderRadius = borderRadius;

  Rect? _targetRect;
  ShapeBorder? _targetShape;
  double _borderRadius;

  set targetRect(Rect? value) {
    if (_targetRect == value) return;
    _targetRect = value;
  }

  set targetShape(ShapeBorder? value) {
    if (_targetShape == value) return;
    _targetShape = value;
  }

  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  bool _insideTarget(Offset position) {
    final rect = _targetRect;
    if (rect == null) return false;
    final clipped = Rect.fromLTRB(
      rect.left.clamp(0.0, size.width),
      rect.top.clamp(0.0, size.height),
      rect.right.clamp(0.0, size.width),
      rect.bottom.clamp(0.0, size.height),
    );
    final path = _targetShape?.getOuterPath(clipped) ??
        (Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              clipped,
              Radius.circular(_borderRadius),
            ),
          ));
    return path.contains(position);
  }

  @override
  bool hitTestSelf(Offset position) => !_insideTarget(position);
}

class _SpotlightMaskPainter extends CustomPainter {
  const _SpotlightMaskPainter({
    required this.targetRect,
    required this.targetShape,
    required this.borderRadius,
  });

  final Rect? targetRect;
  final ShapeBorder? targetShape;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final target = targetRect;
    if (target == null) {
      canvas.drawPath(screen, Paint()..color = const Color(0xB8000000));
      return;
    }

    final clipped = Rect.fromLTRB(
      target.left.clamp(0.0, size.width),
      target.top.clamp(0.0, size.height),
      target.right.clamp(0.0, size.width),
      target.bottom.clamp(0.0, size.height),
    );

    final hole = targetShape?.getOuterPath(clipped) ??
        (Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              clipped,
              Radius.circular(borderRadius),
            ),
          ));

    final dimmed = Path.combine(PathOperation.difference, screen, hole);
    canvas.drawPath(dimmed, Paint()..color = const Color(0xB8000000));
  }

  @override
  bool shouldRepaint(covariant _SpotlightMaskPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.targetShape != targetShape ||
        oldDelegate.borderRadius != borderRadius;
  }
}
