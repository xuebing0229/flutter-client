import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/portability/data_portability_file_bridge.dart';

/// Public feedback form. This is a fixed, non-user-generated destination.
const feedbackFormUrl = 'https://v.wjx.cn/vm/YXtnlrL.aspx';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _externalLink = MethodChannel('app.feedback');
  final GlobalKey _posterKey = GlobalKey();
  final DataPortabilityFileBridge _fileBridge =
      const DataPortabilityFileBridge();
  bool _saving = false;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openForm() async {
    try {
      if (Platform.isAndroid) {
        await _externalLink.invokeMethod<void>(
          'openUrl',
          <String, String>{'url': feedbackFormUrl},
        );
      } else if (Platform.isWindows) {
        await Process.start(
          'explorer.exe',
          <String>[feedbackFormUrl],
          mode: ProcessStartMode.detached,
        );
      } else {
        throw UnsupportedError('暂不支持在当前设备打开浏览器');
      }
    } catch (error) {
      _message('无法打开反馈链接：$error');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: feedbackFormUrl));
    _message('反馈链接已复制');
  }

  Future<void> _savePoster() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _posterKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('反馈图片尚未准备好');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('无法生成反馈图片');
      final saved = await _fileBridge.exportImage(
        fileName: '冒险者公会问题反馈.png',
        bytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
      );
      if (saved) _message('反馈图片已保存');
    } catch (error) {
      _message('保存图片失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPoster() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('反馈图片')),
          body: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: FeedbackPoster(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('问题反馈')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '使用中遇到 Bug、显示异常，或有新功能建议？欢迎通过问卷告诉我们。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: InkWell(
                onTap: _showPoster,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RepaintBoundary(
                        key: _posterKey,
                        child: const FeedbackPoster(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '点击图片可放大；也可以保存后用其他设备扫码',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openForm,
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('打开反馈问卷'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _saving ? null : _savePoster,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_saving ? '正在保存…' : '保存反馈图片'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _copyLink,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制反馈链接'),
          ),
        ],
      ),
    );
  }
}

/// Offline rendition of the supplied blue feedback poster, with a live,
/// scannable QR code so its destination always matches the direct-open button.
class FeedbackPoster extends StatelessWidget {
  const FeedbackPoster({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2C4AFF);
    final decorationColor = Colors.white.withValues(alpha: 0.07);
    return SizedBox(
      width: 360,
      height: 360,
      child: ColoredBox(
        color: blue,
        child: Stack(
          children: [
            Positioned(
              left: -15,
              top: 175,
              child: Transform.rotate(
                angle: 0.3,
                child: Icon(Icons.edit_outlined, size: 104, color: decorationColor),
              ),
            ),
            Positioned(
              right: 10,
              top: 170,
              child: Icon(Icons.trending_up_rounded, size: 84, color: decorationColor),
            ),
            Positioned(
              left: 55,
              bottom: 78,
              child: Icon(Icons.search_rounded, size: 80, color: decorationColor),
            ),
            Positioned(
              right: 85,
              bottom: 82,
              child: Icon(Icons.thumb_up_outlined, size: 58, color: decorationColor),
            ),
            Positioned(
              right: 15,
              bottom: 12,
              child: Icon(Icons.checklist_rounded, size: 108, color: decorationColor),
            ),
            Positioned(
              left: 20,
              bottom: 0,
              child: Icon(Icons.discount_outlined, size: 92, color: decorationColor),
            ),
            const Positioned(
              top: 35,
              left: 0,
              right: 0,
              child: Text(
                '冒险者公会问题反馈',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            Positioned(
              top: 118,
              left: 126,
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: QrImageView(
                    data: feedbackFormUrl,
                    version: QrVersions.auto,
                    size: 82,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 237,
              left: 0,
              right: 0,
              child: Text(
                '长按图片扫码',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
