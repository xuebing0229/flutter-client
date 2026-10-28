import 'package:flutter/material.dart';

class QuickStartGuideTargets {
  QuickStartGuideTargets();

  final GlobalKey menuKey = GlobalKey(debugLabel: 'guide-menu');
  final GlobalKey searchKey = GlobalKey(debugLabel: 'guide-search');
  final GlobalKey toolbarKey = GlobalKey(debugLabel: 'guide-toolbar');
  final GlobalKey addOrderKey = GlobalKey(debugLabel: 'guide-add-order');
  final GlobalKey addOrderFormKey = GlobalKey(debugLabel: 'guide-add-order-form');
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
  final GlobalKey settingsBackupKey = GlobalKey(debugLabel: 'guide-settings-backup');
  final GlobalKey featureToggleKey = GlobalKey(debugLabel: 'guide-feature-toggle');

  GlobalKey? tabKey(String id) => switch (id) {
        'products' => productsTabKey,
        'schedule' => scheduleTabKey,
        'statistics' => statisticsTabKey,
        _ => null,
      };
}

class SpotlightGuideStep {
  const SpotlightGuideStep({
    required this.targetKey,
    required this.icon,
    required this.title,
    required this.body,
  });

  final GlobalKey targetKey;
  final IconData icon;
  final String title;
  final String body;
}

Future<bool> showSpotlightGuide(
  BuildContext context, {
  required List<SpotlightGuideStep> steps,
  String finalLabel = '开始使用',
}) async {
  if (steps.isEmpty) return false;

  final completed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '新手指引',
    barrierColor: Colors.transparent,
    pageBuilder: (dialogContext, _, __) {
      return _SpotlightGuideOverlay(
        steps: steps,
        finalLabel: finalLabel,
      );
    },
  );
  return completed ?? false;
}

class _SpotlightGuideOverlay extends StatefulWidget {
  const _SpotlightGuideOverlay({
    required this.steps,
    required this.finalLabel,
  });

  final List<SpotlightGuideStep> steps;
  final String finalLabel;

  @override
  State<_SpotlightGuideOverlay> createState() => _SpotlightGuideOverlayState();
}

class _SpotlightGuideOverlayState extends State<_SpotlightGuideOverlay> {
  int _index = 0;
  Rect? _targetRect;

  SpotlightGuideStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTarget());
  }

  void _refreshTarget() {
    if (!mounted) return;
    final targetContext = _step.targetKey.currentContext;
    final box = targetContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      setState(() => _targetRect = null);
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    setState(() {
      _targetRect = rect.inflate(8);
    });
  }

  void _move(int delta) {
    final next =
        (_index + delta).clamp(0, widget.steps.length - 1).toInt();
    if (next == _index) return;
    setState(() {
      _index = next;
      _targetRect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTarget());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safeTop = media.padding.top + 12;
    final safeBottom = media.padding.bottom + 12;
    final colors = Theme.of(context).colorScheme;
    final rect = _targetRect;
    final isLast = _index == widget.steps.length - 1;

    final cardWidth =
        (size.width - 32).clamp(260.0, 420.0).toDouble();
    final cardHeight = 196.0;
    final preferBelow =
        rect == null || rect.bottom + cardHeight + 24 < size.height - safeBottom;
    final cardTop = rect == null
        ? (size.height - cardHeight) / 2
        : preferBelow
            ? (rect.bottom + 16)
            : (rect.top - cardHeight - 16);
    final clampedTop = cardTop
        .clamp(safeTop, size.height - safeBottom - cardHeight)
        .toDouble();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (rect == null)
            const Positioned.fill(
              child: ColoredBox(color: Color(0xB8000000)),
            )
          else ...[
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: rect.top.clamp(0.0, size.height).toDouble(),
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
            Positioned(
              left: 0,
              top: rect.top.clamp(0.0, size.height).toDouble(),
              width: rect.left.clamp(0.0, size.width).toDouble(),
              height: rect.height.clamp(0.0, size.height).toDouble(),
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
            Positioned(
              left: rect.right.clamp(0.0, size.width).toDouble(),
              top: rect.top.clamp(0.0, size.height).toDouble(),
              right: 0,
              height: rect.height.clamp(0.0, size.height).toDouble(),
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
            Positioned(
              left: 0,
              top: rect.bottom.clamp(0.0, size.height).toDouble(),
              right: 0,
              bottom: 0,
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
          ],
          Positioned(
            left: (size.width - cardWidth) / 2,
            top: clampedTop,
            width: cardWidth,
            child: SafeArea(
              child: Card(
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
                          Text(
                            '${_index + 1} / ${widget.steps.length}',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('跳过'),
                          ),
                          if (_index > 0)
                            TextButton(
                              onPressed: () => _move(-1),
                              child: const Text('上一步'),
                            ),
                          FilledButton(
                            onPressed: () {
                              if (isLast) {
                                Navigator.of(context).pop(true);
                              } else {
                                _move(1);
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
      ),
    );
  }
}
