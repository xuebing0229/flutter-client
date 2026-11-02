// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/account/account_transfer_service.dart';
import '../../../core/account/web_account_store.dart';
import '../../../core/portability/app_backup_data.dart';
import '../../../core/web/web_platform_bridge.dart';

class WebExistingAccountJoinPage extends StatefulWidget {
  const WebExistingAccountJoinPage({
    required this.store,
    super.key,
  });

  final WebAccountStore store;

  @override
  State<WebExistingAccountJoinPage> createState() =>
      _WebExistingAccountJoinPageState();
}

class _WebExistingAccountJoinPageState
    extends State<WebExistingAccountJoinPage> {
  static const RelayAccountTransferClient _client =
      RelayAccountTransferClient();

  final TextEditingController _deviceCodeController =
      TextEditingController();

  SyncthingAccountTransferClientSession? _session;
  bool _starting = false;
  bool _receiving = false;
  bool _finished = false;
  String? _error;

  Future<void> _startJoin() async {
    if (_starting || _receiving || _finished) return;
    final raw = _deviceCodeController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先粘贴原设备复制的设备码。');
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });

    SyncthingAccountTransferClientSession? session;
    try {
      final descriptor = AccountTransferDescriptor.decode(
        AddDeviceCode.accountTransferFrom(raw),
      );
      session = await _client.start(
        descriptor,
        receiverName: _browserDeviceName(),
      );
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _receiving = true;
      });
      unawaited(_receive(session));
    } on FormatException catch (error) {
      await session?.close();
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      await session?.close();
      if (mounted) setState(() => _error = '网页设备加入失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _receive(
    SyncthingAccountTransferClientSession session,
  ) async {
    try {
      final source = await session.receive();
      if (!mounted || !identical(_session, session)) return;

      final backup = AppBackupData.decode(source);
      final account = backup.accountSyncState;
      if (account == null || !account.hasCredentials) {
        throw const FormatException('收到的账号信息不完整，请重新生成设备码。');
      }

      final appDeviceId = session.response.receiverAppDeviceId?.trim();
      if (appDeviceId == null || appDeviceId.length < 16) {
        throw const FormatException('网页设备身份无效，请重新加入。');
      }

      // Keep the bootstrap package as the initial local workspace. It is
      // intentionally small; after password login the existing web peer-sync
      // service pulls the real CRDT workspace and assets from online devices.
      webStorageSet(
        'adventurers-guild.web.workspace.v2.${account.accountId}',
        backup.encode(pretty: false),
      );
      await widget.store.importAccountState(
        account,
        preferredDeviceId: appDeviceId,
        select: true,
        stayLoggedIn: false,
      );

      _finished = true;
      await session.close();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('网页设备已加入账号，请输入账号密码登录。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FormatException catch (error) {
      await session.close();
      if (mounted && identical(_session, session)) {
        setState(() {
          _session = null;
          _receiving = false;
          _error = error.message;
        });
      }
    } catch (error) {
      await session.close();
      if (mounted && identical(_session, session)) {
        setState(() {
          _session = null;
          _receiving = false;
          _error = '接收账号信息失败：$error';
        });
      }
    }
  }

  Future<void> _copyResponse() async {
    final response = _session?.response.encode();
    if (response == null) return;
    await Clipboard.setData(ClipboardData(text: response));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('回应码已复制，请粘贴回原设备确认'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteDeviceCode() async {
    final data = await Clipboard.getData('text/plain');
    final value = data?.text?.trim();
    if (value == null || value.isEmpty) return;
    _deviceCodeController.text = value;
  }

  String _browserDeviceName() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('edg/')) return 'Edge 网页';
    if (ua.contains('firefox/')) return 'Firefox 网页';
    if (ua.contains('opr/') || ua.contains('opera')) return 'Opera 网页';
    if (ua.contains('chrome/') || ua.contains('crios/')) return 'Chrome 网页';
    if (ua.contains('safari/')) return 'Safari 网页';
    return '网页设备';
  }

  @override
  void dispose() {
    _deviceCodeController.dispose();
    if (!_finished) {
      unawaited(_session?.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final response = _session?.response.encode();

    return Scaffold(
      appBar: AppBar(title: const Text('从设备加入账号')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            children: [
              Text(
                '在已经登录的手机或电脑打开「账号与设备 → 添加设备」，'
                '复制设备码并粘贴到这里。网页会生成回应二维码/回应码，'
                '让原设备确认一次即可加入。',
                style: TextStyle(
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _deviceCodeController,
                        enabled: !_starting && !_receiving,
                        minLines: 4,
                        maxLines: 8,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '原设备设备码',
                          hintText: '粘贴「添加设备」页面复制的设备码',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: '粘贴',
                            onPressed:
                                _starting || _receiving ? null : _pasteDeviceCode,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _starting || _receiving ? null : _startJoin,
                        icon: _starting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.link_rounded),
                        label: Text(_starting ? '正在连接…' : '生成网页回应码'),
                      ),
                    ],
                  ),
                ),
              ),
              if (response != null) ...[
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Text(
                          '让原设备确认这个回应码',
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
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _copyResponse,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('复制回应码'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(
                          '确认后会通过加密在线连接接收账号信息。'
                          '随后登录账号，排单、成品和参考图会继续自动同步。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
            ],
          ),
        ),
      ),
    );
  }
}
