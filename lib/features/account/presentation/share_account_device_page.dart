import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/account/account_transfer_service.dart';
import '../../../core/account/qr_image_decoder.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../shared/presentation/layout_spacing.dart';

class ShareAccountDevicePage extends StatefulWidget {
  const ShareAccountDevicePage({
    required this.buildTransferPackage,
    required this.syncCoordinator,
    super.key,
  });

  final Future<String> Function() buildTransferPackage;
  final SyncCoordinator syncCoordinator;

  @override
  State<ShareAccountDevicePage> createState() => _ShareAccountDevicePageState();
}

class _ShareAccountDevicePageState extends State<ShareAccountDevicePage> {
  static const DataPortabilityFileBridge _fileBridge =
      DataPortabilityFileBridge();

  final TextEditingController _responseCodeController = TextEditingController();

  SyncthingAccountTransferServer? _server;
  Timer? _pollTimer;
  String? _error;
  bool _transferred = false;
  bool _receiverConfirmed = false;
  bool _responseBusy = false;
  bool _pairingBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (widget.syncCoordinator.syncPaused) {
      if (mounted) {
        setState(() => _error = '同步已暂停，请先恢复同步后再添加设备。');
      }
      return;
    }
    try {
      await widget.syncCoordinator.activateTransport();
      if (widget.syncCoordinator.syncPaused) {
        throw StateError('同步已暂停，请先恢复同步后再添加设备。');
      }
      final payload = await widget.buildTransferPackage();
      final server = await SyncthingAccountTransferServer.start(
        payload: payload,
        onTransferred: () {
          if (!mounted) return;
          setState(() => _transferred = true);
        },
      );
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() => _server = server);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) return;
        await server.poll();
        if (mounted && server.transferred != _transferred) {
          setState(() => _transferred = server.transferred);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _restart() async {
    await _server?.close();
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _server = null;
      _error = null;
      _transferred = false;
      _receiverConfirmed = false;
      _responseCodeController.clear();
    });
    await _start();
  }

  Future<String?> _scanOrPickCode() async {
    if (Platform.isWindows) {
      final path = await _fileBridge.pickQrImage();
      if (!mounted || path == null) return null;
      final decoded = decodeQrImage(await File(path).readAsBytes());
      if (decoded.trim().isEmpty) {
        throw const FormatException('所选图片中没有识别到二维码。');
      }
      return decoded.trim();
    }

    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _ScanDeviceCodePage()),
    );
  }

  Future<void> _scanResponseCode() async {
    if (_responseBusy || _transferred) return;
    try {
      final source = await _scanOrPickCode();
      if (!mounted || source == null) return;
      await _acceptResponseFromSource(source);
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (error) {
      if (mounted) _message('读取回应二维码失败：$error');
    }
  }

  Future<void> _acceptTypedResponse() async {
    final source = _responseCodeController.text.trim();
    if (source.isEmpty) {
      _message('请先粘贴新设备生成的回应码');
      return;
    }
    await _acceptResponseFromSource(source);
  }

  Future<void> _acceptResponseFromSource(String source) async {
    if (_responseBusy || _transferred) return;
    if (widget.syncCoordinator.syncPaused) {
      _message('同步已暂停，请先恢复同步后再确认新设备。');
      return;
    }
    final server = _server;
    if (server == null) {
      _message('添加设备通道还在准备，请稍后再试');
      return;
    }

    setState(() => _responseBusy = true);
    try {
      final response = AccountTransferResponseCode.decode(source);
      await server.acceptResponse(response);

      // The response is authenticated by the one-time bootstrap key, so the
      // permanent account folder can be shared with the same transport now.
      // After the new device logs in its app-device identity will arrive
      // through the normal account-state sync.
      await widget.syncCoordinator.bootstrapPeerTransport(
        deviceId: response.receiverDeviceId,
        name: response.receiverName,
      );

      if (!mounted) return;
      setState(() {
        _receiverConfirmed = true;
        _responseCodeController.clear();
      });
      _message('新设备已确认，正在传输账号信息。请继续保持本页打开直到显示完成。');
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (error) {
      if (mounted) _message('确认新设备失败：$error');
    } finally {
      if (mounted) setState(() => _responseBusy = false);
    }
  }

  Future<void> _scanPairingCode() async {
    if (_pairingBusy) return;

    try {
      final source = await _scanOrPickCode();
      if (!mounted || source == null) return;
      await _pairFromSource(source);
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (error) {
      if (mounted) _message('读取设备二维码失败：$error');
    }
  }

  Future<void> _pairFromSource(String source) async {
    setState(() => _pairingBusy = true);
    try {
      final pairing = AddDeviceCode.syncPairingFrom(source);
      await widget.syncCoordinator.pairFromPayload(pairing);
      if (mounted) {
        _message('已添加对方；正式同步通道会继续自动连接');
      }
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (error) {
      if (mounted) _message('设备配对失败：$error');
    } finally {
      if (mounted) setState(() => _pairingBusy = false);
    }
  }

  Future<void> _copyPairingCode(SyncthingAccountTransferServer server) async {
    final pairing = widget.syncCoordinator.pairingPayload;
    if (pairing == null || pairing.isEmpty) {
      _message('同步核心还在准备，请稍后再试');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _qrData(server)));
    if (mounted) _message('配对码已复制');
  }

  String _qrData(SyncthingAccountTransferServer server) {
    return AddDeviceCode(
      accountTransferPayload: server.descriptor.encode(),
      syncPairingPayload: widget.syncCoordinator.pairingPayload,
    ).encode();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _responseCodeController.dispose();
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_server?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final server = _server;

    return Scaffold(
      appBar: AppBar(title: const Text('添加设备')),
      body: AnimatedBuilder(
        animation: widget.syncCoordinator,
        builder: (context, _) {
          final pairingReady =
              widget.syncCoordinator.pairingPayload?.isNotEmpty == true;

          return ListView(
            padding: AppLayoutSpacing.pageScrollPadding(
              context,
              left: 18,
              top: 12,
              right: 18,
            ),
            children: [
              _AddDeviceCard(
                icon: Icons.qr_code_2_rounded,
                title: '第一步：让新设备扫描',
                child: Column(
                  children: [
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      )
                    else if (server == null)
                      const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: _qrData(server),
                          size: 250,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _transferred
                            ? '账号信息已经传给新设备，首次绑定完成。以后正常同步不需要再打开这个页面。'
                            : _receiverConfirmed
                            ? '新设备已经确认，正在传输账号信息。请继续保持本页打开，直到这里显示完成。'
                            : '让未登录的新设备扫描此码后，新设备会显示一枚“回应二维码”。请保持本页打开，不要返回或关闭应用。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (_transferred) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _restart,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('添加下一台设备'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddDeviceCard(
                icon: Icons.verified_user_outlined,
                title: '第二步：确认新设备',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _receiverConfirmed
                          ? '已收到并确认这台新设备的回应。现在只需等待账号信息传输完成。'
                          : '新设备扫完上面的二维码后，会生成回应二维码/回应码。请在这里扫回来或粘贴回来。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          server == null ||
                              _responseBusy ||
                              _transferred ||
                              _receiverConfirmed
                          ? null
                          : _scanResponseCode,
                      icon: _responseBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Platform.isWindows
                                  ? Icons.photo_library_outlined
                                  : Icons.qr_code_scanner_rounded,
                            ),
                      label: Text(
                        Platform.isWindows ? '选择新设备回应二维码图片' : '扫描新设备回应二维码',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _responseCodeController,
                      enabled:
                          server != null &&
                          !_responseBusy &&
                          !_transferred &&
                          !_receiverConfirmed,
                      minLines: 3,
                      maxLines: 6,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '新设备回应码',
                        hintText: '也可以把新设备复制的回应码粘贴到这里',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '粘贴',
                          onPressed:
                              server == null ||
                                  _responseBusy ||
                                  _transferred ||
                                  _receiverConfirmed
                              ? null
                              : () async {
                                  final data = await Clipboard.getData(
                                    'text/plain',
                                  );
                                  final value = data?.text?.trim();
                                  if (value == null || value.isEmpty) return;
                                  _responseCodeController.text = value;
                                },
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed:
                          server == null ||
                              _responseBusy ||
                              _transferred ||
                              _receiverConfirmed
                          ? null
                          : _acceptTypedResponse,
                      child: const Text('确认回应码'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddDeviceCard(
                icon: Icons.sync_alt_rounded,
                title: '已登录设备互相配对',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '只用于两台已经登录同一账号、但正式同步关系需要补配的情况。首次加入不需要走这里。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: !pairingReady || _pairingBusy
                          ? null
                          : _scanPairingCode,
                      icon: _pairingBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Platform.isWindows
                                  ? Icons.photo_library_outlined
                                  : Icons.qr_code_scanner_rounded,
                            ),
                      label: Text(
                        Platform.isWindows ? '选择另一台设备二维码图片' : '扫描另一台已登录设备',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddDeviceCard(
                icon: Icons.link_rounded,
                title: '无法扫码时',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '上方添加设备二维码也可以复制成文字。把它粘贴到新设备「加入已有账号 → 配对码加入」即可；之后仍会生成回应码，需要填回本页确认。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: pairingReady && server != null
                          ? () => _copyPairingCode(server)
                          : null,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制本机配对码'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanDeviceCodePage extends StatefulWidget {
  const _ScanDeviceCodePage();

  @override
  State<_ScanDeviceCodePage> createState() => _ScanDeviceCodePageState();
}

class _ScanDeviceCodePageState extends State<_ScanDeviceCodePage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描设备二维码')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddDeviceCard extends StatelessWidget {
  const _AddDeviceCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
