import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.compactWhenTargetRouteCovered = false,
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

  /// When a transient route such as a dropdown popup covers the target route,
  /// keep only the guide controls visible at the nearest safe screen edge.
  /// This leaves the popup options unobstructed while still allowing the user
  /// to move/skip/exit; those actions already dismiss the transient route.
  final bool compactWhenTargetRouteCovered;
}

Future<void> _revealSpotlightTarget(GlobalKey targetKey) async {
  final targetContext = targetKey.currentContext;
  if (targetContext == null) return;

  final media = MediaQuery.maybeOf(targetContext);
  final box = targetContext.findRenderObject();
  if (media != null && box is RenderBox && box.attached && box.hasSize) {
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    final visibleTop = media.padding.top + 12;
    final visibleBottom = media.size.height - media.padding.bottom - 12;
    if (rect.top >= visibleTop && rect.bottom <= visibleBottom) return;
  }

  await Scrollable.ensureVisible(
    targetContext,
    alignment: .5,
    duration: Duration.zero,
  );
  await WidgetsBinding.instance.endOfFrame;
}

bool _spotlightTargetHasLayout(GlobalKey targetKey) {
  final context = targetKey.currentContext;
  final box = context?.findRenderObject();
  return box is RenderBox &&
      box.attached &&
      box.hasSize &&
      box.size.width > 0 &&
      box.size.height > 0;
}

Future<bool> _waitForSpotlightTarget(
  GlobalKey targetKey, {
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  if (_spotlightTargetHasLayout(targetKey)) return true;

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await WidgetsBinding.instance.endOfFrame;
    if (_spotlightTargetHasLayout(targetKey)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  return _spotlightTargetHasLayout(targetKey);
}

Future<List<SpotlightGuideStep>> _resolveSpotlightSteps(
  List<SpotlightGuideStep> steps,
) async {
  if (steps.isEmpty) return const <SpotlightGuideStep>[];

  List<SpotlightGuideStep> ready() => steps
      .where((step) => _spotlightTargetHasLayout(step.targetKey))
      .toList(growable: false);

  var resolved = ready();
  if (resolved.length == steps.length) return resolved;

  // A pushed route takes more than a few frames to settle on Web, and a
  // lazy scrollable may attach its guide target only after the next layout.
  // Wait for the actual RenderBox instead of silently dropping the step.
  final deadline = DateTime.now().add(const Duration(milliseconds: 900));
  while (DateTime.now().isBefore(deadline)) {
    await WidgetsBinding.instance.endOfFrame;
    resolved = ready();
    if (resolved.length == steps.length) break;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  return resolved;
}

Future<bool> showSpotlightGuide(
  BuildContext context, {
  required List<SpotlightGuideStep> steps,
  String finalLabel = '开始使用',
  int progressStart = 0,
  int? progressTotal,
}) async {
  final resolvedSteps = await _resolveSpotlightSteps(steps);
  if (resolvedSteps.isEmpty) return false;

  final firstReady =
      await _waitForSpotlightTarget(resolvedSteps.first.targetKey);
  if (!context.mounted || !firstReady) return false;

  await _revealSpotlightTarget(resolvedSteps.first.targetKey);
  if (!context.mounted) return false;

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
        steps: resolvedSteps,
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
  final GlobalKey _overlayKey = GlobalKey(debugLabel: 'spotlight-guide-overlay');
  final GlobalKey _cardKey = GlobalKey(debugLabel: 'spotlight-guide-card');

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

    final targetContext = _step.targetKey.currentContext;
    final targetRoute =
        targetContext == null ? null : ModalRoute.of(targetContext);
    final targetRouteCovered = targetRoute != null && !targetRoute.isCurrent;
    final box = targetContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      if (_targetRect == null &&
          _targetRouteCovered == targetRouteCovered) {
        return;
      }
      setState(() {
        _targetRect = null;
        _targetRouteCovered = targetRouteCovered;
      });
      return;
    }
    final overlayRenderObject =
        _overlayKey.currentContext?.findRenderObject();
    final rect = overlayRenderObject is RenderBox &&
            overlayRenderObject.attached &&
            overlayRenderObject.hasSize
        ? Rect.fromPoints(
            overlayRenderObject.globalToLocal(
              box.localToGlobal(Offset.zero),
            ),
            overlayRenderObject.globalToLocal(
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            ),
          ).inflate(_step.targetPadding)
        : (box.localToGlobal(Offset.zero) & box.size)
            .inflate(_step.targetPadding);
    if (_targetRect == rect &&
        _targetRouteCovered == targetRouteCovered) {
      return;
    }
    setState(() {
      _targetRect = rect;
      _targetRouteCovered = targetRouteCovered;
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

    final targetReady =
        await _waitForSpotlightTarget(widget.steps[next].targetKey);
    if (!mounted || !targetReady) return;

    await _revealSpotlightTarget(widget.steps[next].targetKey);
    if (!mounted) return;

    setState(() {
      _index = next;
      _targetRect = null;
      _targetRouteCovered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final overlayRenderObject =
        _overlayKey.currentContext?.findRenderObject();
    final size = overlayRenderObject is RenderBox &&
            overlayRenderObject.attached &&
            overlayRenderObject.hasSize
        ? overlayRenderObject.size
        : media.size;
    final safeTop = media.padding.top + 12;
    final safeBottom =
        media.padding.bottom + media.viewInsets.bottom + 12;
    final colors = Theme.of(context).colorScheme;
    final rect = _targetRect;
    final isLast = _index == widget.steps.length - 1;
    final compactForTransientRoute =
        _targetRouteCovered && _step.compactWhenTargetRouteCovered;
    final compactAtTop =
        rect != null && rect.center.dy <= size.height / 2;

    const targetGap = 16.0;
    const comfortableCardHeight = 220.0;
    final cardWidth =
        (size.width - 32).clamp(260.0, 420.0).toDouble();
    final spaceAbove = rect == null
        ? 0.0
        : (rect.top - safeTop - targetGap).clamp(0.0, size.height).toDouble();
    final spaceBelow = rect == null
        ? 0.0
        : (size.height - safeBottom - rect.bottom - targetGap)
            .clamp(0.0, size.height)
            .toDouble();

    // Card placement is a hard non-overlap rule. Pick one safe region around
    // the highlighted target, then constrain the whole card to that region.
    // If the natural card is taller, its content scrolls inside the card
    // instead of allowing the card to cross the highlight boundary.
    final placeAbove = rect != null &&
        ((_step.preferCardAbove && spaceAbove >= comfortableCardHeight) ||
            (!_step.preferCardAbove && spaceAbove >= spaceBelow));
    final cardRegionTop = rect == null
        ? safeTop
        : placeAbove
            ? safeTop
            : rect.bottom + targetGap;
    final cardRegionBottom = rect == null
        ? size.height - safeBottom
        : placeAbove
            ? rect.top - targetGap
            : size.height - safeBottom;
    final cardRegionHeight =
        (cardRegionBottom - cardRegionTop).clamp(0.0, size.height).toDouble();

    return Stack(
      key: _overlayKey,
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
                  emphasizeTarget: kIsWeb,
                  highlightColor: colors.primary,
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
        if (compactForTransientRoute)
          Positioned(
            left: 16,
            right: 16,
            top: compactAtTop ? 0 : null,
            bottom: compactAtTop ? null : 0,
            child: SafeArea(
              child: Card(
                elevation: 12,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _step.icon,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _step.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if ((widget.progressTotal ?? widget.steps.length) > 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '${widget.progressStart + _index + 1} / ${widget.progressTotal ?? widget.steps.length}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: () => unawaited(_finish(false)),
                            child: const Text('退出教程'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => unawaited(_finish(true)),
                            child: const Text('跳过本节'),
                          ),
                          const Spacer(),
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
        if (!compactForTransientRoute)
          Positioned(
            left: (size.width - cardWidth) / 2,
            top: cardRegionTop,
            width: cardWidth,
            height: cardRegionHeight,
            child: Align(
              alignment: rect == null
                  ? Alignment.center
                  : placeAbove
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
              child: _SpotlightGuideCard(
                cardKey: _cardKey,
                maxHeight: cardRegionHeight,
                step: _step,
                progressText:
                    (widget.progressTotal ?? widget.steps.length) > 1
                        ? '${widget.progressStart + _index + 1} / ${widget.progressTotal ?? widget.steps.length}'
                        : null,
                showPrevious: _index > 0,
                finalLabel: isLast ? widget.finalLabel : '下一步',
                onExit: () => unawaited(_finish(false)),
                onSkip: () => unawaited(_finish(true)),
                onPrevious: () => unawaited(_move(-1)),
                onNext: () {
                  if (isLast) {
                    unawaited(_finish(true));
                  } else {
                    unawaited(_move(1));
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}


class _SpotlightGuideCard extends StatelessWidget {
  const _SpotlightGuideCard({
    required this.cardKey,
    required this.maxHeight,
    required this.step,
    required this.progressText,
    required this.showPrevious,
    required this.finalLabel,
    required this.onExit,
    required this.onSkip,
    required this.onPrevious,
    required this.onNext,
  });

  final GlobalKey cardKey;
  final double maxHeight;
  final SpotlightGuideStep step;
  final String? progressText;
  final bool showPrevious;
  final String finalLabel;
  final VoidCallback onExit;
  final VoidCallback onSkip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Card(
        key: cardKey,
        elevation: 12,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Row(
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
                          step.icon,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 5),
                            Text(step.body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (progressText != null)
                    Text(
                      progressText!,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: onExit,
                    child: const Text('退出教程'),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('跳过本节'),
                  ),
                  const Spacer(),
                  if (showPrevious)
                    TextButton(
                      onPressed: onPrevious,
                      child: const Text('上一步'),
                    ),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(finalLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    required this.emphasizeTarget,
    required this.highlightColor,
  });

  final Rect? targetRect;
  final ShapeBorder? targetShape;
  final double borderRadius;
  final bool emphasizeTarget;
  final Color highlightColor;

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

    // Transparent TextFields/ListTiles can look almost identical to the dimmed
    // background in a browser. On Web only, reinforce the *actual measured
    // target path* instead of drawing a guessed decorative rectangle.
    if (emphasizeTarget) {
      canvas.drawPath(
        hole,
        Paint()
          ..color = highlightColor.withValues(alpha: .08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        hole,
        Paint()
          ..color = highlightColor.withValues(alpha: .58)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightMaskPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.targetShape != targetShape ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.emphasizeTarget != emphasizeTarget ||
        oldDelegate.highlightColor != highlightColor;
  }
}
