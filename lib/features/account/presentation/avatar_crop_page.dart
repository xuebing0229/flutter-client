import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({
    required this.pickImage,
    super.key,
  });

  final Future<String?> Function() pickImage;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final CropController _controller = CropController();

  Uint8List? _image;
  String? _loadError;
  bool _ready = false;
  bool _cropping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectAndPrepareImage();
    });
  }

  Future<void> _selectAndPrepareImage() async {
    try {
      final path = await widget.pickImage();
      if (!mounted) return;
      if (path == null) {
        Navigator.of(context).pop();
        return;
      }
      await _prepareImage(path);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '图片选择失败：$error');
    }
  }

  Future<void> _prepareImage(String path) async {
    try {
      final source = await File(path).readAsBytes();
      final decoded = img.decodeImage(source);
      if (decoded == null) {
        throw const FormatException('无法识别这张图片。');
      }

      var editorImage = img.bakeOrientation(decoded);
      if (editorImage.width > 2048 || editorImage.height > 2048) {
        editorImage = editorImage.width >= editorImage.height
            ? img.copyResize(editorImage, width: 2048)
            : img.copyResize(editorImage, height: 2048);
      }

      final prepared = Uint8List.fromList(
        img.encodeJpg(editorImage, quality: 94),
      );
      if (!mounted) return;
      setState(() => _image = prepared);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '图片加载失败：$error');
    } finally {
      if (Platform.isAndroid) {
        try {
          final temp = File(path);
          if (await temp.exists()) await temp.delete();
        } catch (_) {
          // Selected Android images are temporary cache files.
        }
      }
    }
  }

  void _confirm() {
    if (!_ready || _cropping) return;
    setState(() => _cropping = true);
    _controller.crop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = _image;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '调整头像',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 44,
                      color: colors.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回重新选择'),
                    ),
                  ],
                ),
              ),
            )
          : image == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        '正在载入图片并准备裁剪…',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                      child: Text(
                        '拖动图片调整位置，双指缩放。圆框里的部分会作为头像。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: Crop(
                          image: image,
                          controller: _controller,
                          withCircleUi: true,
                          interactive: true,
                          fixCropRect: true,
                          baseColor: Colors.black,
                          maskColor: Colors.black.withValues(alpha: 0.58),
                          progressIndicator: const Center(
                            child: CircularProgressIndicator(),
                          ),
                          willUpdateScale: (newScale) => newScale <= 10,
                          initialRectBuilder: InitialRectBuilder.withBuilder(
                            (viewportRect, imageRect) {
                              final side = math.min(
                                    viewportRect.width,
                                    viewportRect.height,
                                  ) *
                                  0.76;
                              return Rect.fromCenter(
                                center: viewportRect.center,
                                width: side,
                                height: side,
                              );
                            },
                          ),
                          onStatusChanged: (status) {
                            final ready = status == CropStatus.ready;
                            final cropping = status == CropStatus.cropping;
                            if (!mounted ||
                                (_ready == ready && _cropping == cropping)) {
                              return;
                            }
                            setState(() {
                              _ready = ready;
                              _cropping = cropping;
                            });
                          },
                          onCropped: (result) {
                            if (!mounted) return;
                            switch (result) {
                              case CropSuccess(:final croppedImage):
                                Navigator.of(context).pop(croppedImage);
                              case CropFailure(:final cause):
                                setState(() => _cropping = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('裁剪失败：$cause')),
                                );
                            }
                          },
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _ready && !_cropping ? _confirm : null,
                          icon: _cropping
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(_cropping ? '处理中…' : '使用此头像'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
