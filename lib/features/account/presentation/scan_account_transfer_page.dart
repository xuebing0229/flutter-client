import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/account/account_transfer_service.dart';

class ScanAccountTransferPage extends StatefulWidget {
  const ScanAccountTransferPage({super.key});

  @override
  State<ScanAccountTransferPage> createState() =>
      _ScanAccountTransferPageState();
}

class _ScanAccountTransferPageState extends State<ScanAccountTransferPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await _controller.stop();

    try {
      final transfer = AddDeviceCode.accountTransferFrom(raw);
      AccountTransferDescriptor.decode(transfer);
      if (!mounted) return;
      Navigator.of(context).pop(raw);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      await _controller.start();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '二维码识别失败：$error');
      await _controller.start();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('扫码加入账号')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                Center(
                  child: IgnorePointer(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            color: colors.surface,
            child: Column(
              children: [
                const Text(
                  '扫描原设备「添加设备」页面上的二维码',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '两台设备保持联网即可，无需连接同一 Wi-Fi。'
                  '扫描后本机会生成回应二维码，需要再让原设备确认一次。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
