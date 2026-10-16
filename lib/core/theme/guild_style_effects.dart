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
        foreground: foreground,
        borderRadius: borderRadius,
      ),
      child: child,
    );

    inner = DecoratedBox(decoration: decoration, child: inner);

    if (style == AppUiStyle.glass && backdropAvailable && glassBlur > 0) {
      inner = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: glassBlur,
          sigmaY: glassBlur,
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
    final gradient = switch (style) {
      AppUiStyle.relief => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _inset
              ? <Color>[
                  _mix(surfaceAlt, Colors.black, 0.04),
                  surfaceAlt,
                  _mix(surfaceAlt, Colors.white, 0.05),
                ]
              : <Color>[
                  _mix(surface, Colors.white, 0.025),
                  surface,
                ],
        ),
      AppUiStyle.retroLight => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _mix(surface, primary, 0.025),
            surface,
            _mix(surface, accent2, 0.018),
          ],
        ),
      AppUiStyle.retroDark => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _mix(surface, primary, 0.10),
            surface,
            _mix(surface, accent2, 0.06),
          ],
        ),
      AppUiStyle.fluorescent => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withValues(alpha: 0.025),
            surface,
          ],
        ),
      AppUiStyle.collage => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _mix(surface, accent2, 0.025),
            surface,
            _mix(surface, primary, 0.025),
          ],
        ),
      AppUiStyle.clay => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _mix(surface, Colors.white, 0.075),
            surface,
            _mix(surface, primary, 0.025),
          ],
        ),
      AppUiStyle.glass => RadialGradient(
          center: const Alignment(-0.2, -1.0),
          radius: 1.45,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.13),
            Colors.white.withValues(alpha: 0.04),
            primary.withValues(alpha: 0.045),
            surface.withValues(alpha: glassOpacity),
          ],
          stops: const <double>[0, 0.25, 0.58, 1],
        ),
      _ => null,
    };

    final color = gradient == null
        ? (_inset ? surfaceAlt : surface)
        : null;

    return BoxDecoration(
      color: style == AppUiStyle.glass && gradient == null
          ? surface.withValues(alpha: glassOpacity)
          : color,
      gradient: gradient,
      borderRadius: borderRadius,
      border: _baseBorder(),
    );
  }

  Border? _baseBorder() {
    switch (style) {
      case AppUiStyle.relief:
        return null;
      case AppUiStyle.glass:
        return Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.50),
            width: 1.1,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.42),
            width: 1.0,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1.0,
          ),
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.0,
          ),
        );
      case AppUiStyle.fluorescent:
        return Border.all(
          color: primary.withValues(alpha: 0.42),
          width: math.max(borderWidth, 1.0),
        );
      case AppUiStyle.retroDark:
        return Border.all(
          color: accent2.withValues(alpha: 0.28),
          width: math.max(borderWidth, 1),
        );
      case AppUiStyle.collage:
        return Border.all(
          color: foreground,
          width: math.max(borderWidth, 2),
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
      AppUiStyle.geometric => <BoxShadow>[
          BoxShadow(
            color: foreground.withValues(alpha: 0.90),
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      AppUiStyle.retroLight => <BoxShadow>[
          BoxShadow(
            color: borderColor.withValues(alpha: 0.32),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      AppUiStyle.retroDark => <BoxShadow>[
          BoxShadow(
            color: accent2.withValues(alpha: 0.34),
            blurRadius: 11,
          ),
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 24,
          ),
        ],
      AppUiStyle.fluorescent => <BoxShadow>[
          BoxShadow(
            color: primary.withValues(alpha: 0.34),
            blurRadius: 12,
          ),
          BoxShadow(
            color: primary.withValues(alpha: 0.12),
            blurRadius: 30,
          ),
        ],
      AppUiStyle.collage => <BoxShadow>[
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
        ],
      AppUiStyle.clay => <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            offset: const Offset(4, 6),
            blurRadius: 0,
          ),
        ],
      AppUiStyle.glass => <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 4),
            blurRadius: 16,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            spreadRadius: 1,
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
    required this.foreground,
    required this.borderRadius,
  });

  final AppUiStyle style;
  final GuildEffectRole role;
  final Color primary;
  final Color accent2;
  final Color accent3;
  final Color foreground;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    switch (style) {
      case AppUiStyle.relief:
        if (role == GuildEffectRole.inset) {
          _paintInsetBevel(
            canvas,
            rrect,
            dark: const Color(0xFFA3B1C6).withValues(alpha: 0.64),
            light: Colors.white.withValues(alpha: 0.86),
            width: 6,
          );
        } else {
          _paintSoftTopHighlight(canvas, rrect, 0.12);
        }
        break;
      case AppUiStyle.minimal:
        if (role == GuildEffectRole.content) {
          canvas.drawLine(
            Offset(0.5, size.height * 0.22),
            Offset(0.5, size.height * 0.78),
            Paint()
              ..color = foreground.withValues(alpha: 0.78)
              ..strokeWidth = 1.2,
          );
        }
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
        _paintNeonInnerGlow(canvas, rrect);
        break;
      case AppUiStyle.collage:
        _paintCollageMarks(canvas, rect);
        break;
      case AppUiStyle.monochrome:
        break;
      case AppUiStyle.clay:
        if (role == GuildEffectRole.inset) {
          _paintInsetBevel(
            canvas,
            rrect,
            dark: Colors.black.withValues(alpha: 0.14),
            light: Colors.white.withValues(alpha: 0.56),
            width: 5,
          );
        } else {
          _paintSoftTopHighlight(canvas, rrect, 0.18);
        }
        break;
      case AppUiStyle.glass:
        _paintGlassHighlights(canvas, rect, rrect);
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
    final rect = rrect.outerRect;
    final topLeft = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        <Color>[dark, Colors.transparent, Colors.transparent],
        const <double>[0, 0.42, 1],
      );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, width),
      topLeft,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, width, rect.height),
      topLeft,
    );

    final bottomRight = Paint()
      ..shader = ui.Gradient.linear(
        rect.bottomRight,
        rect.topLeft,
        <Color>[light, Colors.transparent, Colors.transparent],
        const <double>[0, 0.42, 1],
      );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - width,
        rect.width,
        width,
      ),
      bottomRight,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.right - width,
        rect.top,
        width,
        rect.height,
      ),
      bottomRight,
    );
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
    paint.color = primary;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, 5, rect.height),
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
        rect.longestSide * 0.65,
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

  void _paintGlassHighlights(Canvas canvas, Rect rect, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);

    final topGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.left + rect.width * 0.28, rect.top + rect.height * 0.10),
        rect.width * 0.36,
        <Color>[
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        const <double>[0, 0.42, 1],
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          rect.left + rect.width * 0.26,
          rect.top + rect.height * 0.10,
        ),
        width: rect.width * 0.40,
        height: rect.height * 0.34,
      ),
      topGlow,
    );

    final lowerGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.right - rect.width * 0.17, rect.bottom - rect.height * 0.10),
        rect.width * 0.22,
        <Color>[
          Colors.white.withValues(alpha: 0.09),
          Colors.transparent,
        ],
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          rect.right - rect.width * 0.14,
          rect.bottom - rect.height * 0.10,
        ),
        width: rect.width * 0.26,
        height: rect.height * 0.20,
      ),
      lowerGlow,
    );

    final innerTop = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final topPath = Path()
      ..moveTo(rect.left + rect.width * 0.10, rect.top + 2)
      ..quadraticBezierTo(
        rect.center.dx,
        rect.top - 1,
        rect.right - rect.width * 0.12,
        rect.top + 3,
      );
    canvas.drawPath(topPath, innerTop);

    final colorSheen = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        <Color>[
          primary.withValues(alpha: 0.04),
          Colors.transparent,
          accent2.withValues(alpha: 0.035),
        ],
      );
    canvas.drawRect(rect, colorSheen);
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
        rect.longestSide * 0.62,
        <Color>[
          Colors.transparent,
          Colors.black.withValues(alpha: 0.46),
        ],
        const <double>[0.50, 1],
      );
    canvas.drawRect(rect, vignette);
  }

  void _paintAcid(Canvas canvas, Rect rect) {
    final dot = Paint()
      ..color = primary.withValues(alpha: 0.065)
      ..style = PaintingStyle.fill;
    const step = 20.0;
    for (double y = 10; y < rect.height; y += step) {
      for (double x = 10; x < rect.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }

    final corner = Paint()
      ..color = primary.withValues(alpha: 0.72)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const d = 42.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(d, 0), corner);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, d), corner);
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(d, 0),
      corner,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(0, d),
      corner,
    );

    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(
          rect.width * (0.18 + 0.06 * math.sin(phase * math.pi * 2)),
          rect.height * 0.12,
        ),
        rect.width * 0.72,
        <Color>[
          primary.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, glow);
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
    final p1 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.30 + shift, rect.height * 0.10),
        rect.width * 0.72,
        <Color>[
          primary.withValues(alpha: 0.22),
          primary.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        const <double>[0, 0.42, 1],
      );
    canvas.drawRect(rect, p1);

    final p2 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.78 - shift * 0.45, rect.height * 0.76),
        rect.width * 0.58,
        <Color>[
          accent2.withValues(alpha: 0.13),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, p2);

    final p3 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(rect.width * 0.50, rect.height * 0.48),
        rect.width * 0.68,
        <Color>[
          accent3.withValues(alpha: 0.07),
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
