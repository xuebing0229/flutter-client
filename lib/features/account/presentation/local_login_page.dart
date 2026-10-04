import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';

class LocalLoginPage extends StatefulWidget {
  const LocalLoginPage({
    required this.store,
    required this.onRemoveLocalAccount,
    super.key,
  });

  final AccountStore store;
  final Future<void> Function(String accountId) onRemoveLocalAccount;

  @override
  State<LocalLoginPage> createState() => _LocalLoginPageState();
}

class _LocalLoginPageState extends State<LocalLoginPage> {
  late final TextEditingController _accountName =
      TextEditingController(text: widget.store.accountName ?? '');
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _accountName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.store.unlock(
      accountName: _accountName.text,
      password: _password.text,
    );
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (!ok) _error = '账号名或密码不正确。';
    });
  }

  Future<void> _removeLocalAccount() async {
    if (_busy) return;
    final accountId = widget.store.accountId;
    final accountName = widget.store.accountName ?? '这个账号';
    if (accountId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('从本机移除“$accountName”？'),
          content: const Text(
            '不需要先登录。会删除这台设备保存的账号记录、工作数据和同步目录，'
            '不会删除其他设备上的账号或数据。之后可以重新从其他设备加入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('从本机移除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRemoveLocalAccount(accountId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '移除本机账号失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: colors.secondaryContainer,
                          child: Icon(
                            Icons.person_rounded,
                            size: 32,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '登录冒险者公会',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '使用注册时设置的账号名和密码',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _accountName,
                          autofocus: true,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '账号名',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: !_showPassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon:
                                const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? '隐藏密码' : '显示密码',
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('登录'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : widget.store.returnToAccountChooser,
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('使用其他账号 / 返回初始页'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _removeLocalAccount,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('从本机移除这个账号'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已激活账号无需再次输入激活码。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
