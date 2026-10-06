import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/account/account_transfer_service.dart';
import '../../../core/account/qr_image_decoder.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../shared/presentation/layout_spacing.dart';
import 'scan_account_transfer_page.dart';

class ExistingAccountJoinPage extends StatefulWidget {
  const ExistingAccountJoinPage({required this.onAdoptBackup, super.key});

  final Future<void> Function(AppBackupData backup) onAdoptBackup;

  @override
  State<ExistingAccountJoinPage> createState() =>
      _ExistingAccountJoinPageState();
}

class _ExistingAccountJoinPageState extends State<ExistingAccountJoinPage> {
  static const DataPortabilityFileBridge _fileBridge =
      DataPortabilityFileBridge();

  final TextEditingController _pairingCodeController =
      TextEditingController();

  bool _busy = false;
  String? _error;

  Future<void> _scanJoin() async {
    if (_busy) return;

    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ScanAccountTransferPage(),
      ),
    );

    if (!mounted || raw == null) return;
    await _receiveFromAddDeviceCode(raw);
  }

  Future<void> _galleryJoin() async {
    if (_busy) return;

    final controller = Platform.isAndroid
        ? MobileScannerController(
            autoStart: false,
            formats: const [BarcodeFormat.qrCode],
          )
        : null;
    String? temporaryPath;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      temporaryPath = await _fileBridge.pickQrImage();
      if (!mounted || temporaryPath == null) return;

      String? raw;
      if (Platform.isWindows) {
        raw = decodeQrImage(await File(temporaryPath).readAsBytes());
      } else {
        final capture = await controller!.analyzeImage(
          temporaryPath,
          formats: const [BarcodeFormat.qrCode],
        );

        for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
          final value = barcode.rawValue?.trim();
          if (value != null && value.isNotEmpty) {
            raw = value;
            break;
          }
        }
      }

      if (raw == null || raw.trim().isEmpty) {
        throw const FormatException('所选图片中没有识别到二维码。');
      }

      if (mounted) setState(() => _busy = false);
      await _receiveFromAddDeviceCode(raw);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '相册二维码识别失败：$error');
    } finally {
      await controller?.dispose();
      if (Platform.isAndroid && temporaryPath != null) {
        try {
          final file = File(temporaryPath);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Temporary cache cleanup failure does not affect joining.
        }
      }
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _codeJoin() async {
    if (_busy) return;

    final raw = _pairingCodeController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先输入或粘贴配对码。');
      return;
    }
    await _receiveFromAddDeviceCode(raw);
  }

  Future<void> _receiveFromAddDeviceCode(String raw) async {
    try {
      final descriptor = AccountTransferDescriptor.decode(
        AddDeviceCode.accountTransferFrom(raw),
      );
      final source = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => _ReceiveAccountTransferPage(
            descriptor: descriptor,
          ),
        ),
      );
      if (!mounted || source == null) return;
      await _adopt(source);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '加入设备失败：$error');
    }
  }

  Future<void> _importPackage() async {
    if (_busy) return;

    try {
      final source = await _fileBridge.importBackup();
      if (!mounted || source == null) return;
      await _adopt(source);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取数据包失败：$error');
    }
  }

  Future<void> _adopt(String source) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backup = AppBackupData.decode(source);
      final account = backup.accountSyncState;
      if (account == null || !account.hasCredentials) {
        throw const FormatException('这份数据包没有可用的账号登录信息。');
      }

      final bootstrapOnly = backup.settings['bootstrapOnly'] == true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('加入这个账号？'),
          content: Text(
            '账号：${account.accountName}\n\n'
            '${bootstrapOnly ? '账号信息已经接收完成。确认后先登录账号，排单、成品等工作数据会通过正式设备同步继续自动传入。' : '这份完整数据包会写入当前设备。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认加入'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await widget.onAdoptBackup(backup);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '加入账号失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('加入已有账号')),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 18,
          top: 18,
          right: 18,
        ),
        children: [
          Text(
            '新设备第一次加入时，需要和原设备完成一次双向确认。'
            '先传账号信息用于登录，排单、成品等工作数据会在登录后通过正式同步通道继续传输。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          if (Platform.isAndroid || Platform.isWindows) ...[
            _JoinOption(
              icon: Icons.qr_code_scanner_rounded,
              title: '二维码加入',
              subtitle: Platform.isAndroid
                  ? '原设备打开「账号与设备 → 添加设备」并保持页面打开。扫描后本机会显示回应二维码，再让原设备扫描一次即可确认。'
                  : '手机打开「账号与设备 → 添加设备」并保持页面打开，把二维码截图保存到电脑。选图后电脑会生成回应二维码或回应码供手机确认；不要求同一 Wi-Fi。',
              buttonText: Platform.isAndroid ? '相机扫码' : '选择二维码图片',
              secondaryButtonText: Platform.isAndroid ? '从相册选择二维码' : null,
              enabled: !_busy,
              onTap: Platform.isAndroid ? _scanJoin : _galleryJoin,
              onSecondaryTap: Platform.isAndroid ? _galleryJoin : null,
            ),
            const SizedBox(height: 14),
          ],
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.link_rounded, size: 34, color: colors.primary),
                  const SizedBox(height: 10),
                  Text(
                    '配对码加入',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '无法扫码时，在原设备「账号与设备 → 添加设备」里复制配对码并保持该页面打开。'
                    '粘贴后本机会生成一枚回应码，需要再填回原设备确认。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pairingCodeController,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '配对码',
                      hintText: '在这里粘贴原设备复制的配对码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '粘贴',
                        onPressed: _busy
                            ? null
                            : () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                final value = data?.text?.trim();
                                if (value == null || value.isEmpty) return;
                                _pairingCodeController.text = value;
                              },
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _busy ? null : _codeJoin,
                      child: const Text('使用配对码加入'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _JoinOption(
            icon: Icons.upload_file_rounded,
            title: '导入完整数据包',
            subtitle: '适合原设备不在身边但已经保存过完整备份的情况。',
            buttonText: '选择数据包',
            enabled: !_busy,
            onTap: _importPackage,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

class _ReceiveAccountTransferPage extends StatefulWidget {
  const _ReceiveAccountTransferPage({required this.descriptor});

  final AccountTransferDescriptor descriptor;

  @override
  State<_ReceiveAccountTransferPage> createState() =>
      _ReceiveAccountTransferPageState();
}

class _ReceiveAccountTransferPageState
    extends State<_ReceiveAccountTransferPage> {
  static const SyncthingAccountTransferClient _client =
      SyncthingAccountTransferClient();

  SyncthingAccountTransferClientSession? _session;
  Timer? _progressTimer;
  Map<String, dynamic>? _transferProgress;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    SyncthingAccountTransferClientSession? session;
    try {
      session = await _client.start(widget.descriptor);
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() => _session = session);
      _startProgressPolling(session);

      final source = await session.receive();
      _finished = true;
      _stopProgressPolling();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await session.close();

      if (!mounted) return;
      Navigator.of(context).pop(source);
    } on FormatException catch (error) {
      _stopProgressPolling();
      await session?.close();
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      _stopProgressPolling();
      await session?.close();
      if (mounted) setState(() => _error = '设备确认失败：$error');
    }
  }

  void _startProgressPolling(SyncthingAccountTransferClientSession session) {
    _progressTimer?.cancel();
    unawaited(_refreshTransferProgress(session));
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshTransferProgress(session));
    });
  }

  Future<void> _refreshTransferProgress(
    SyncthingAccountTransferClientSession session,
  ) async {
    try {
      final progress = await session.transferProgress();
      if (!mounted || !identical(_session, session)) return;
      setState(() => _transferProgress = progress);
    } catch (_) {
      // Progress is supplemental. The transfer itself keeps running if a
      // status sample is temporarily unavailable.
    }
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _copyResponse() async {
    final response = _session?.response.encode();
    if (response == null) return;
    await Clipboard.setData(ClipboardData(text: response));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('回应码已复制，请粘贴到原设备'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _stopProgressPolling();
    if (!_finished) {
      unawaited(_session?.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final response = _session?.response.encode();
    final progress = _transferProgress;
    final completion = ((progress?['completion'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100)
        .toDouble();
    final progressBytes = (progress?['globalBytes'] as num?)?.toInt() ?? 0;
    final progressItems = (progress?['globalItems'] as num?)?.toInt() ?? 0;
    final hasMeasuredProgress = progress != null &&
        (progressBytes > 0 || progressItems > 0);

    return Scaffold(
      appBar: AppBar(title: const Text('确认新设备')),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 18,
          top: 18,
          right: 18,
        ),
        children: [
          Text(
            '第一步已经完成。现在请保持本页打开，同时让原设备继续停留在「添加设备」页面。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 42,
                      color: colors.error,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                  ] else if (response == null) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      Platform.isWindows
                          ? '正在初始化 Windows 同步核心并准备本机回应码……首次使用可能需要 10–30 秒。'
                          : '正在准备本机回应码……',
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    const Text(
                      '请让原设备扫描下面的回应二维码',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: QrImageView(
                        data: response,
                        size: 250,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '如果不方便扫码，也可以复制回应码，在原设备「添加设备」页面粘贴确认。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyResponse,
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('复制回应码'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: hasMeasuredProgress ? completion / 100 : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasMeasuredProgress
                          ? '正在传输账号信息 ${completion >= 99.95 ? '100' : completion.toStringAsFixed(1)}%'
                          : '原设备确认后会自动接收账号信息。完成后本页会自动关闭，不需要再操作。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinOption extends StatelessWidget {
  const _JoinOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.enabled,
    required this.onTap,
    this.secondaryButtonText,
    this.onSecondaryTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final String? secondaryButtonText;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 34, color: colors.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: enabled ? onTap : null,
                child: Text(buttonText),
              ),
            ),
            if (secondaryButtonText != null && onSecondaryTap != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: enabled ? onSecondaryTap : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(secondaryButtonText!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
