import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_ui_style.dart';

enum GuildEffectRole { content, chrome, inset, emphasized }

class GuildSurfaceEffect extends StatelessWidget {
  const GuildSurfaceEffect({
    required this.style,
    required this.role,
    required this.primary,
    required this.accent2,
    required this.accent3,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.foreground,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.shadows,
    required this.glassBlur,
    required this.glassOpacity,
    required this.backdropAvailable,
    required this.child,
    super.key,
  });

  final AppUiStyle style;
  final GuildEffectRole role;
  final Color primary;
  final Color accent2;
  final Color accent3;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color foreground;
  final Color borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;
  final double glassBlur;
  final double glassOpacity;
  final bool backdropAvailable;
  final Widget child;

  bool get _inset => role == GuildEffectRole.inset;

  @override
  Widget build(BuildContext context) {
    final outerShadows = _surfaceShadows();
    final decoration = _surfaceDecoration();

    Widget inner = CustomPaint(
      foregroundPainter: _SurfaceFinishPainter(
        style: style,
        role: role,
        primary: primary,
        accent2: accent2,
        accent3: accent3,
        background: background,
        foreground: foreground,
        borderRadius: borderRadius,
      ),
      child: child,
    );

    inner = DecoratedBox(decoration: decoration, child: inner);

    if (style == AppUiStyle.glass && backdropAvailable && glassBlur > 0) {
      // The supplied Liquid Glass reference does not blur every component at
      // the same strength: panels use 12/16px while controls and inputs use
      // 8px. Keep content itself sharp; only the backdrop is filtered.
      final effectiveBlur = _inset || role == GuildEffectRole.emphasized
          ? math.min(glassBlur, 8.0)
          : glassBlur;
      inner = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: inner,
      );
    }

    inner = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: outerShadows,
      ),
      child: inner,
    );
  }

  BoxDecoration _surfaceDecoration() {
    final lightGlass = foreground.computeLuminance() < 0.35;
    final emphasized = role == GuildEffectRole.emphasized;
    final glassFill = emphasized
        ? primary.withValues(alpha: lightGlass ? 0.15 : 0.25)
        : lightGlass
            ? Colors.white.withValues(
                alpha: _inset
                    ? 0.50
                    : role == GuildEffectRole.chrome
                        ? 0.60
                        : 0.55,
              )
            : Colors.white.withValues(
                alpha: _inset
                    ? 0.05
                    : role == GuildEffectRole.chrome
                        ? 0.06
                        : 0.04,
              );

    final effectiveSurface = switch (style) {
      // The reference primary neumorphic button keeps the same base material
      // and changes only its foreground accent.
      AppUiStyle.relief when emphasized => background,
      // Minimal / retro / acid primary controls are outline-or-text controls,
      // not solid theme-colour blocks.
      AppUiStyle.minimal when emphasized => Colors.transparent,
      AppUiStyle.retroLight when emphasized => Colors.transparent,
      AppUiStyle.retroDark when emphasized => Colors.transparent,
      AppUiStyle.fluorescent when emphasized => Colors.transparent,
      // Brutalism primary is black/white rather than the app accent.
      AppUiStyle.monochrome when emphasized => foreground,
      _ => surface,
    };

    final gradient = switch (style) {
      AppUiStyle.relief => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _inset
              ? <Color>[
                  _mix(effectiveSurface, Colors.black, 0.04),
                  effectiveSurface,
                  _mix(effectiveSurface, Colors.white, 0.05),
                ]
              : <Color>[
                  _mix(effectiveSurface, Colors.white, 0.025),
                  effectiveSurface,
                ],
        ),
      AppUiStyle.retroLight => emphasized || _inset
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                _mix(effectiveSurface, primary, 0.025),
                effectiveSurface,
                _mix(effectiveSurface, accent2, 0.018),
              ],
            ),
      AppUiStyle.retroDark => emphasized || _inset
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                _mix(effectiveSurface, primary, 0.10),
                effectiveSurface,
                _mix(effectiveSurface, accent2, 0.06),
              ],
            ),
      AppUiStyle.fluorescent => emphasized || _inset
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                primary.withValues(alpha: 0.025),
                effectiveSurface,
              ],
            ),
      AppUiStyle.collage => emphasized || _inset
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                _mix(effectiveSurface, accent2, 0.025),
                effectiveSurface,
                _mix(effectiveSurface, primary, 0.025),
              ],
            ),
      AppUiStyle.clay => _inset
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                _mix(effectiveSurface, Colors.white, 0.075),
                effectiveSurface,
                _mix(effectiveSurface, primary, 0.025),
              ],
            ),
      // Liquid Glass uses a uniform translucent glass fill. The moving colour
      // belongs to the page backdrop and the primary control tint.
      AppUiStyle.glass => null,
      _ => null,
    };

    return BoxDecoration(
      color: style == AppUiStyle.glass
          ? glassFill
          : gradient == null
              ? effectiveSurface
              : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: _baseBorder(),
    );
  }

  Border? _baseBorder() {
    final emphasized = role == GuildEffectRole.emphasized;
    switch (style) {
      case AppUiStyle.relief:
      case AppUiStyle.minimal:
      case AppUiStyle.clay:
        return null;
      case AppUiStyle.glass:
        final lightGlass = foreground.computeLuminance() < 0.35;
        return Border.all(
          color: emphasized
              ? primary.withValues(alpha: lightGlass ? 0.25 : 0.35)
              : lightGlass
                  ? primary.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.10),
          width: 1,
        );
      case AppUiStyle.fluorescent:
        return Border.all(
          color: emphasized ? primary : borderColor,
          width: math.max(borderWidth, 1.0),
        );
      case AppUiStyle.retroDark:
        return Border.all(
          color: emphasized
              ? primary.withValues(alpha: 0.85)
              : accent2.withValues(alpha: 0.28),
          width: math.max(borderWidth, 1),
        );
      case AppUiStyle.retroLight:
        return Border.all(
          color: emphasized ? primary : borderColor,
          width: math.max(borderWidth, 2),
        );
      case AppUiStyle.collage:
        return Border.all(
          color: emphasized
              ? primary
              : _inset
                  ? borderColor
                  : foreground,
          width: math.max(borderWidth, 2),
        );
      case AppUiStyle.monochrome:
        if (_inset) {
          return Border.all(
            color: foreground.withValues(alpha: 0.62),
            width: 1,
          );
        }
        return Border.all(
          color: foreground,
          width: emphasized ? 1 : math.max(borderWidth, 2),
        );
      default:
        if (borderWidth <= 0) return null;
        return Border.all(color: borderColor, width: borderWidth);
    }
  }

  List<BoxShadow> _surfaceShadows() {
    if (_inset) return const <BoxShadow>[];
    return switch (style) {
      AppUiStyle.relief => shadows,
      AppUiStyle.bold => <BoxShadow>[
          BoxShadow(
            color: foreground,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      // Bauhaus and the light retro reference keep their component rows
      // flat. Their character comes from hard borders / geometry, not a drop
      // shadow on every panel.
      AppUiStyle.geometric => const <BoxShadow>[],
      AppUiStyle.retroLight => const <BoxShadow>[],
      AppUiStyle.retroDark => role == GuildEffectRole.emphasized
          ? <BoxShadow>[
              BoxShadow(
                color: primary.withValues(alpha: 0.42),
                blurRadius: 10,
              ),
              BoxShadow(
                color: primary.withValues(alpha: 0.22),
                blurRadius: 20,
              ),
            ]
          : <BoxShadow>[
              BoxShadow(
                color: accent2.withValues(alpha: 0.34),
                blurRadius: 11,
              ),
              BoxShadow(
                color: primary.withValues(alpha: 0.18),
                blurRadius: 24,
              ),
            ],
      AppUiStyle.fluorescent => background.computeLuminance() < 0.35
          ? switch (role) {
              // acid-graphics-components.html:
              // rows are only 0 0 8px / 5%, while the outer frame carries
              // the broader 20px + 60px glow. Do not halo every panel.
              GuildEffectRole.content => <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.05),
                    blurRadius: 8,
                  ),
                ],
              GuildEffectRole.chrome => <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                  ),
                  BoxShadow(
                    color: primary.withValues(alpha: 0.05),
                    blurRadius: 60,
                  ),
                ],
              GuildEffectRole.emphasized => <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                  ),
                ],
              GuildEffectRole.inset => const <BoxShadow>[],
            }
          : const <BoxShadow>[],
      // Anti-Design Lite uses flat white component rows. Reserve the
      // coloured offset shadow for larger chrome / frame-like surfaces.
      AppUiStyle.collage => role == GuildEffectRole.chrome
          ? <BoxShadow>[
              BoxShadow(
                color: primary,
                offset: const Offset(6, 6),
                blurRadius: 0,
              ),
              BoxShadow(
                color: accent2,
                offset: const Offset(-3, -3),
                blurRadius: 0,
              ),
            ]
          : const <BoxShadow>[],
      AppUiStyle.clay => <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            offset: const Offset(4, 6),
            blurRadius: 0,
          ),
        ],
      AppUiStyle.glass => role == GuildEffectRole.emphasized
          ? const <BoxShadow>[]
          : foreground.computeLuminance() < 0.35
              ? <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.08),
                    offset: const Offset(0, 4),
                    blurRadius: 16,
                  ),
                ]
              : <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.20),
                    blurRadius: 8,
                  ),
                ],
      _ => shadows,
    };
  }
}

class GuildBackdropEffect extends StatefulWidget {
  const GuildBackdropEffect({
    required this.style,
    required this.primary,
    required this.accent2,
    required this.accent3,
    required this.background,
    required this.child,
    super.key,
  });

  final AppUiStyle style;
  final Color primary;
  final Color accent2;
  final Color accent3;
  final Color background;
  final Widget child;

  @override
  State<GuildBackdropEffect> createState() => _GuildBackdropEffectState();
}

class _GuildBackdropEffectState extends State<GuildBackdropEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _animated =>
      widget.style == AppUiStyle.glass ||
      widget.style == AppUiStyle.retroDark ||
      widget.style == AppUiStyle.fluorescent;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (_animated) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant GuildBackdropEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_animated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_animated && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _BackdropPainter(
            style: widget.style,
            primary: widget.primary,
            accent2: widget.accent2,
            accent3: widget.accent3,
            background: widget.background,
            phase: _controller.value,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SurfaceFinishPainter extends CustomPainter {
  const _SurfaceFinishPainter({
    required this.style,
    required this.role,
    required this.primary,
    required this.accent2,
    required this.accent3,
    required this.background,
    required this.foreground,
    required this.borderRadius,
  });

  final AppUiStyle style;
  final GuildEffectRole role;
  final Color primary;
  final Color accent2;
  final Color accent3;
  final Color background;
  final Color foreground;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // Inputs are their own component in the reference files. They should not
    // inherit the decorative corner marks / collage bars / card highlights
    // used by content panels.
    if (role == GuildEffectRole.inset) {
      switch (style) {
        case AppUiStyle.relief:
          _paintInsetBevel(
            canvas,
            rrect,
            dark: const Color(0xFFA3B1C6).withValues(alpha: 0.64),
            light: Colors.white.withValues(alpha: 0.86),
            width: 6,
          );
          break;
        case AppUiStyle.clay:
          _paintInsetBevel(
            canvas,
            rrect,
            dark: Colors.black.withValues(alpha: 0.14),
            light: Colors.white.withValues(alpha: 0.26),
            width: 4,
          );
          break;
        case AppUiStyle.fluorescent:
          if (background.computeLuminance() < 0.35) {
            _paintNeonInnerGlow(canvas, rrect);
          }
          break;
        case AppUiStyle.classic:
        case AppUiStyle.minimal:
        case AppUiStyle.bold:
        case AppUiStyle.geometric:
        case AppUiStyle.retroLight:
        case AppUiStyle.retroDark:
        case AppUiStyle.collage:
        case AppUiStyle.monochrome:
        case AppUiStyle.glass:
          break;
      }
      return;
    }

    switch (style) {
      case AppUiStyle.relief:
        _paintSoftTopHighlight(canvas, rrect, 0.12);
        break;
      case AppUiStyle.minimal:
        break;
      case AppUiStyle.bold:
        _paintCornerNotches(canvas, rect, foreground, 3);
        break;
      case AppUiStyle.geometric:
        _paintGeometricAccent(canvas, rect);
        break;
      case AppUiStyle.retroLight:
        _paintHairline(canvas, rect, accent2.withValues(alpha: 0.22));
        break;
      case AppUiStyle.retroDark:
        _paintHairline(canvas, rect, accent2.withValues(alpha: 0.58));
        break;
      case AppUiStyle.fluorescent:
        if (background.computeLuminance() < 0.35) {
          _paintNeonInnerGlow(canvas, rrect);
        }
        break;
      case AppUiStyle.collage:
        _paintCollageMarks(canvas, rect);
        break;
      case AppUiStyle.monochrome:
        break;
      case AppUiStyle.clay:
        _paintSoftTopHighlight(canvas, rrect, 0.18);
        break;
      case AppUiStyle.glass:
        // The supplied Liquid Glass components use translucent fill +
        // backdrop blur + a thin border. They do not place a permanent
        // milky highlight over every component.
        break;
      case AppUiStyle.classic:
        break;
    }
  }

  void _paintInsetBevel(
    Canvas canvas,
    RRect rrect, {
    required Color dark,
    required Color light,
    required double width,
  }) {
    // Keep the inset effect on the same rounded geometry as the field.
    // Horizontal/vertical edge strips read as a rectangular inner box inside
    // a rounded outer shell, which is especially obvious on search fields.
    final offset = width * 0.55;
    final strokeWidth = width * 1.05;

    final darkPaint = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, width * 0.28);
    final lightPaint = Paint()
      ..color = light
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, width * 0.28);

    canvas.save();
    canvas.clipRRect(rrect);
    // Positive shift leaves the top/left portion visible inside the clip.
    canvas.drawRRect(rrect.shift(Offset(offset, offset)), darkPaint);
    // Negative shift leaves the bottom/right portion visible inside the clip.
    canvas.drawRRect(rrect.shift(Offset(-offset, -offset)), lightPaint);
    canvas.restore();
  }

  void _paintSoftTopHighlight(Canvas canvas, RRect rrect, double alpha) {
    final rect = rrect.outerRect;
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        Offset(rect.center.dx, rect.top + rect.height * 0.32),
        <Color>[
          Colors.white.withValues(alpha: alpha),
          Colors.transparent,
        ],
      );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.35),
      paint,
    );
    canvas.restore();
  }

  void _paintCornerNotches(
    Canvas canvas,
    Rect rect,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    const d = 9.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(d, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, d), paint);
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(d, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(0, d),
      paint,
    );
  }

  void _paintGeometricAccent(Canvas canvas, Rect rect) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = primary.withValues(alpha: 0.82);
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 10, rect.top + 8, 16, 4),
      paint,
    );
    paint.color = accent2.withValues(alpha: 0.82);
    canvas.drawRect(
      Rect.fromLTWH(rect.right - 10, rect.top, 10, 10),
      paint,
    );
    paint.color = accent3.withValues(alpha: 0.78);
    canvas.drawCircle(
      Offset(rect.right - 8, rect.bottom - 8),
      4,
      paint,
    );
  }

  void _paintHairline(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        <Color>[Colors.transparent, color, Colors.transparent],
        const <double>[0, 0.5, 1],
      );
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 1), paint);
  }

  void _paintNeonInnerGlow(Canvas canvas, RRect rrect) {
    final rect = rrect.outerRect;
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        math.max(rect.width, rect.height) * 0.65,
        <Color>[
          Colors.transparent,
          primary.withValues(alpha: 0.025),
          primary.withValues(alpha: 0.075),
        ],
        const <double>[0, 0.72, 1],
      );
    canvas.drawRect(rect, paint);

    final line = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        <Color>[
          Colors.transparent,
          accent2.withValues(alpha: 0.34),
          primary.withValues(alpha: 0.28),
          Colors.transparent,
        ],
        const <double>[0, 0.34, 0.66, 1],
      );
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 1), line);
    canvas.restore();
  }

  void _paintCollageMarks(Canvas canvas, Rect rect) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = primary.withValues(alpha: 0.88);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.bottom - 5, rect.width * 0.24, 5),
      p,
    );
    p.color = accent2.withValues(alpha: 0.86);
    canvas.drawRect(
      Rect.fromLTWH(rect.right - 6, rect.top, 6, rect.height * 0.34),
      p,
    );
    p.color = accent3.withValues(alpha: 0.82);
    canvas.save();
    canvas.translate(rect.right - 20, rect.bottom - 10);
    canvas.rotate(-0.12);
    canvas.drawRect(const Rect.fromLTWH(-13, -3, 26, 6), p);
    canvas.restore();
  }


  @override
  bool shouldRepaint(covariant _SurfaceFinishPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.role != role ||
        oldDelegate.primary != primary ||
        oldDelegate.accent2 != accent2 ||
        oldDelegate.accent3 != accent3 ||
        oldDelegate.foreground != foreground ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.style,
    required this.primary,
    required this.accent2,
    required this.accent3,
    required this.background,
    required this.phase,
  });

  final AppUiStyle style;
  final Color primary;
  final Color accent2;
  final Color accent3;
  final Color background;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);

    switch (style) {
      case AppUiStyle.classic:
      case AppUiStyle.relief:
      case AppUiStyle.minimal:
      case AppUiStyle.bold:
      case AppUiStyle.monochrome:
      case AppUiStyle.clay:
        break;
      case AppUiStyle.geometric:
        _paintGeometricBackdrop(canvas, rect);
        break;
      case AppUiStyle.retroLight:
        _paintRetroLight(canvas, rect);
        break;
      case AppUiStyle.retroDark:
        _paintRetroDark(canvas, rect);
        break;
      case AppUiStyle.fluorescent:
        _paintAcid(canvas, rect);
        break;
      case AppUiStyle.collage:
        _paintCollage(canvas, rect);
        break;
      case AppUiStyle.glass:
        _paintGlass(canvas, rect);
        break;
    }
  }

  void _paintGeometricBackdrop(Canvas canvas, Rect rect) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = primary.withValues(alpha: 0.12);
    canvas.drawRect(const Rect.fromLTWH(18, 18, 22, 22), p);
    p.color = accent2.withValues(alpha: 0.12);
    canvas.drawCircle(Offset(rect.right - 28, 28), 13, p);
    p.color = accent3.withValues(alpha: 0.12);
    final tri = Path()
      ..moveTo(rect.center.dx, rect.bottom - 18)
      ..lineTo(rect.center.dx - 12, rect.bottom - 38)
      ..lineTo(rect.center.dx + 12, rect.bottom - 38)
      ..close();
    canvas.drawPath(tri, p);
  }

  void _paintRetroLight(Canvas canvas, Rect rect) {
    final thin = Paint()
      ..color = primary.withValues(alpha: 0.045)
      ..strokeWidth = 0.7;
    const spacing = 24.0;
    for (double y = 0; y <= rect.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), thin);
    }
    for (double x = 0; x <= rect.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, rect.height), thin);
    }
  }

  void _paintRetroDark(Canvas canvas, Rect rect) {
    final grid = Paint()
      ..color = accent2.withValues(alpha: 0.045)
      ..strokeWidth = 0.7;
    const gridSize = 60.0;
    for (double y = 0; y <= rect.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), grid);
    }
    for (double x = 0; x <= rect.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, rect.height), grid);
    }

    final scan = Paint()
      ..color = accent2.withValues(
        alpha: 0.022 + 0.008 * math.sin(phase * math.pi * 2).abs(),
      )
      ..strokeWidth = 1;
    for (double y = 2; y < rect.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), scan);
    }

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        math.max(rect.width, rect.height) * 0.62,
        <Color>[
          Colors.transparent,
          Colors.black.withValues(alpha: 0.46),
        ],
        const <double>[0.50, 1],
      );
    canvas.drawRect(rect, vignette);
  }

  void _paintAcid(Canvas canvas, Rect rect) {
    final dark = background.computeLuminance() < 0.35;

    // Both supplied Acid Graphics references use a 20px dot grid. The light
    // variant uses neutral black dots; the dark variant uses faint green.
    final dot = Paint()
      ..color = dark
          ? primary.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const step = 20.0;
    for (double y = 10; y < rect.height; y += step) {
      for (double x = 10; x < rect.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }

    // Match the reference scan-line opacity instead of adding a broad radial
    // glow, which made the whole screen look out of focus.
    final scan = Paint()
      ..color = dark
          ? primary.withValues(alpha: 0.009)
          : Colors.black.withValues(alpha: 0.0075)
      ..strokeWidth = 1;
    for (double y = 2; y < rect.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), scan);
    }

    final topLeft = Paint()
      ..color = primary.withValues(alpha: dark ? 0.72 : 1.0)
      ..strokeWidth = dark ? 2 : 3
      ..style = PaintingStyle.stroke;
    final bottomRight = Paint()
      ..color = (dark ? primary : accent2).withValues(
        alpha: dark ? 0.72 : 1.0,
      )
      ..strokeWidth = dark ? 2 : 3
      ..style = PaintingStyle.stroke;
    const d = 42.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(d, 0), topLeft);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, d), topLeft);
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(d, 0),
      bottomRight,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(0, d),
      bottomRight,
    );
  }

  void _paintCollage(Canvas canvas, Rect rect) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = accent2.withValues(alpha: 0.08);
    canvas.save();
    canvas.translate(rect.width * 0.18, rect.height * 0.12);
    canvas.rotate(-0.08);
    canvas.drawRect(const Rect.fromLTWH(-70, -8, 140, 16), p);
    canvas.restore();

    p.color = primary.withValues(alpha: 0.09);
    canvas.save();
    canvas.translate(rect.width * 0.82, rect.height * 0.22);
    canvas.rotate(0.10);
    canvas.drawRect(const Rect.fromLTWH(-55, -9, 110, 18), p);
    canvas.restore();

    p.color = accent3.withValues(alpha: 0.07);
    canvas.drawCircle(
      Offset(rect.width * 0.74, rect.height * 0.82),
      42,
      p,
    );
  }

  void _paintGlass(Canvas canvas, Rect rect) {
    final shift = math.sin(phase * math.pi * 2) * rect.width * 0.08;

    // Match liquid-glass-components(.light).html: the page backdrop carries
    // only very low-opacity colour fields (6% / 5% / 4%). The component
    // surfaces remain readable and translucent instead of looking bubbled.
    final p1 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.30 + shift, rect.height * 0.20),
        rect.width * 0.72,
        <Color>[
          primary.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, p1);

    final p2 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.70 - shift * 0.45, rect.height * 0.80),
        rect.width * 0.58,
        <Color>[
          accent2.withValues(alpha: 0.05),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, p2);

    final p3 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.50, rect.height * 0.50),
        rect.width * 0.68,
        <Color>[
          accent3.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, p3);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.primary != primary ||
        oldDelegate.accent2 != accent2 ||
        oldDelegate.accent3 != accent3 ||
        oldDelegate.background != background ||
        oldDelegate.phase != phase;
  }
}

Color _mix(Color a, Color b, double t) =>
    Color.lerp(a, b, t.clamp(0.0, 1.0).toDouble()) ?? a;
