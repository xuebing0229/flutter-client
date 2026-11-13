import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

Future<Uint8List?> showScreenAspectImageCropper({
  required BuildContext context,
  required Uint8List image,
  String title = '裁切背景图',
}) {
  final size = MediaQuery.sizeOf(context);
  final aspectRatio = size.width > 0 && size.height > 0
      ? size.width / size.height
      : 9 / 16;

  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(
      fullscreenDialog: true,
      builder: (_) => ScreenAspectImageCropPage(
        image: image,
        aspectRatio: aspectRatio,
        title: title,
      ),
    ),
  );
}

class ScreenAspectImageCropPage extends StatefulWidget {
  const ScreenAspectImageCropPage({
    required this.image,
    required this.aspectRatio,
    required this.title,
    super.key,
  });

  final Uint8List image;
  final double aspectRatio;
  final String title;

  @override
  State<ScreenAspectImageCropPage> createState() =>
      _ScreenAspectImageCropPageState();
}

class _ScreenAspectImageCropPageState
    extends State<ScreenAspectImageCropPage> {
  final CropController _controller = CropController();
  bool _cropping = false;

  void _crop() {
    if (_cropping) return;
    setState(() => _cropping = true);
    _controller.crop();
  }

  void _handleCropped(CropResult result) {
    if (!mounted) return;

    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('裁切失败：$cause'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF7C8FD6),
    );

    return Theme(
      data: editorTheme,
      child: PopScope(
        canPop: !_cropping,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(widget.title),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Text(
                    '裁切框就是当前设备的屏幕比例。拖动图片调整位置，双指缩放到合适构图。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Crop(
                        controller: _controller,
                        image: widget.image,
                        aspectRatio: widget.aspectRatio,
                        initialSize: 1,
                        interactive: true,
                        fixCropRect: true,
                        willUpdateScale: (scale) => scale <= 8,
                        baseColor: Colors.black,
                        maskColor: Colors.black.withValues(alpha: 0.58),
                        filterQuality: FilterQuality.high,
                        progressIndicator: const Center(
                          child: CircularProgressIndicator(),
                        ),
                        onCropped: _handleCropped,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cropping
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _cropping ? null : _crop,
                          icon: _cropping
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.crop_rounded),
                          label: Text(_cropping ? '处理中' : '使用这张'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
