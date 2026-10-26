import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<Color?> showThemeColorPicker({
  required BuildContext context,
  required Color initialColor,
  required String title,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ThemeColorPickerSheet(
      initialColor: initialColor,
      title: title,
    ),
  );
}

class _ThemeColorPickerSheet extends StatefulWidget {
  const _ThemeColorPickerSheet({
    required this.initialColor,
    required this.title,
  });

  final Color initialColor;
  final String title;

  @override
  State<_ThemeColorPickerSheet> createState() => _ThemeColorPickerSheetState();
}

class _ThemeColorPickerSheetState extends State<_ThemeColorPickerSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor).withAlpha(1);
    _hexController = TextEditingController(text: _hex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value, {bool refreshHex = true}) {
    setState(() {
      _hsv = value.withAlpha(1);
      if (refreshHex) _hexController.text = _hex(_color);
    });
  }

  void _setRgb({int? red, int? green, int? blue}) {
    final argb = _color.toARGB32();
    final currentRed = (argb >> 16) & 0xff;
    final currentGreen = (argb >> 8) & 0xff;
    final currentBlue = argb & 0xff;
    _setHsv(
      HSVColor.fromColor(
        Color.fromARGB(
          255,
          red ?? currentRed,
          green ?? currentGreen,
          blue ?? currentBlue,
        ),
      ),
    );
  }

  void _applyHex() {
    final raw = _hexController.text.trim().replaceAll('#', '');
    if (raw.length != 6) {
      _hexController.text = _hex(_color);
      return;
    }
    final value = int.tryParse(raw, radix: 16);
    if (value == null) {
      _hexController.text = _hex(_color);
      return;
    }
    _setHsv(HSVColor.fromColor(Color(0xff000000 | value)));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final pickerSize = math.min(media.size.width - 48, 330.0);
    final argb = _color.toARGB32();
    final red = (argb >> 16) & 0xff;
    final green = (argb >> 8) & 0xff;
    final blue = argb & 0xff;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + media.viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: pickerSize,
              height: pickerSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) =>
                        _updateHue(details.localPosition, pickerSize),
                    onPanUpdate: (details) =>
                        _updateHue(details.localPosition, pickerSize),
                    child: CustomPaint(
                      size: Size.square(pickerSize),
                      painter: _HueWheelPainter(hue: _hsv.hue),
                    ),
                  ),
                  SizedBox(
                    width: pickerSize * 0.52,
                    height: pickerSize * 0.52,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (details) => _updateSaturationValue(
                        details.localPosition,
                        pickerSize * 0.52,
                      ),
                      onPanUpdate: (details) => _updateSaturationValue(
                        details.localPosition,
                        pickerSize * 0.52,
                      ),
                      child: CustomPaint(
                        painter: _SaturationValuePainter(
                          hue: _hsv.hue,
                          saturation: _hsv.saturation,
                          value: _hsv.value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'HEX',
                      prefixText: '#',
                    ),
                    maxLength: 6,
                    onSubmitted: (_) => _applyHex(),
                    onEditingComplete: _applyHex,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _RgbSlider(
              label: 'R',
              value: red,
              activeColor: Colors.red,
              onChanged: (value) => _setRgb(red: value),
            ),
            _RgbSlider(
              label: 'G',
              value: green,
              activeColor: Colors.green,
              onChanged: (value) => _setRgb(green: value),
            ),
            _RgbSlider(
              label: 'B',
              value: blue,
              activeColor: Colors.blue,
              onChanged: (value) => _setRgb(blue: value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_color),
                icon: const Icon(Icons.check_rounded),
                label: const Text('使用这个颜色'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateHue(Offset position, double size) {
    final center = Offset(size / 2, size / 2);
    final delta = position - center;
    final distance = delta.distance;
    final outer = size / 2;
    final inner = outer - 38;
    if (distance < inner || distance > outer + 12) return;

    final angle = math.atan2(delta.dy, delta.dx);
    var degrees = angle * 180 / math.pi + 90;
    if (degrees < 0) degrees += 360;
    if (degrees >= 360) degrees -= 360;
    _setHsv(_hsv.withHue(degrees));
  }

  void _updateSaturationValue(Offset position, double size) {
    final saturation = (position.dx / size).clamp(0.0, 1.0);
    final value = (1 - position.dy / size).clamp(0.0, 1.0);
    _setHsv(
      _hsv
          .withSaturation(saturation.toDouble())
          .withValue(value.toDouble()),
    );
  }

  String _hex(Color color) {
    final rgb = color.toARGB32() & 0x00ffffff;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color activeColor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: activeColor,
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
      ],
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: <Color>[
          Color(0xffff0000),
          Color(0xffffff00),
          Color(0xff00ff00),
          Color(0xff00ffff),
          Color(0xff0000ff),
          Color(0xffff00ff),
          Color(0xffff0000),
        ],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30;
    canvas.drawCircle(center, radius, paint);

    final angle = (hue - 90) * math.pi / 180;
    final markerCenter = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(
      markerCenter,
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      markerCenter,
      12,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) =>
      oldDelegate.hue != hue;
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[Colors.white, hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    final point = Offset(
      saturation * size.width,
      (1 - value) * size.height,
    );
    canvas.drawCircle(
      point,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      point,
      9.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}
