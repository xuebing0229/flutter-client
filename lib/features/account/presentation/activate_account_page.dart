import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';

class ActivateAccountPage extends StatefulWidget {
  const ActivateAccountPage({
    required this.store,
    super.key,
  });

  final AccountStore store;

  @override
  State<ActivateAccountPage> createState() => _ActivateAccountPageState();
}

class _ActivateAccountPageState extends State<ActivateAccountPage> {
  final _code = TextEditingController();
  final _accountName = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  bool _showPasswordAgain = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _accountName.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;

    if (_password.text != _passwordAgain.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.store.activate(
        activationCode: _code.text,
        accountName: _accountName.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '注册激活失败，请检查激活码后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
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
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          size: 44,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '注册并激活冒险者公会',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '激活码只在首次注册时使用。注册成功后会绑定到这个账号，以后登录只需要账号名和密码。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _code,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '激活码',
                            helperText: '仅首次注册使用，之后无需再次输入',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _accountName,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.newUsername],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '账号名',
                            helperText: '以后登录时使用，请记住',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: !_showPassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: '登录密码',
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordAgain,
                          enabled: !_busy,
                          obscureText: !_showPasswordAgain,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _activate(),
                          decoration: InputDecoration(
                            labelText: '确认密码',
                            prefixIcon:
                                const Icon(Icons.lock_reset_rounded),
                            suffixIcon: IconButton(
                              tooltip:
                                  _showPasswordAgain ? '隐藏密码' : '显示密码',
                              onPressed: () {
                                setState(() {
                                  _showPasswordAgain =
                                      !_showPasswordAgain;
                                });
                              },
                              icon: Icon(
                                _showPasswordAgain
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _activate,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.verified_user_outlined),
                            label: Text(_busy ? '正在验证…' : '注册并激活'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '账号名和密码保存在应用本地，并随设备同步数据一起迁移；不连接我们的账号服务器。',
                          textAlign: TextAlign.center,
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
