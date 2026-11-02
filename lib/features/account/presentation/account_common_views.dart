import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/account/account_models.dart';
import '../../../core/theme/guild_visual_theme.dart';
import '../../shared/presentation/layout_spacing.dart';
import '../../shared/presentation/spotlight_guide.dart';

class AccountEntryItem {
  const AccountEntryItem({
    required this.accountId,
    required this.accountName,
  });

  final String accountId;
  final String accountName;
}

class AccountEntryView extends StatelessWidget {
  const AccountEntryView({
    required this.accounts,
    required this.onSelectAccount,
    required this.onRemoveAccount,
    required this.onActivate,
    required this.onJoin,
    this.introText =
        '可以登录这台设备上已经保存的账号，也可以注册新账号或从其他设备加入。',
    this.localAccountsTitle = '本机已有账号',
    super.key,
  });

  final List<AccountEntryItem> accounts;
  final ValueChanged<String> onSelectAccount;
  final ValueChanged<AccountEntryItem> onRemoveAccount;
  final VoidCallback onActivate;
  final VoidCallback onJoin;
  final String introText;
  final String localAccountsTitle;

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
              child: Column(
                children: [
                  Icon(
                    Icons.palette_outlined,
                    size: 58,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '冒险者公会',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    introText,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  if (accounts.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        localAccountsTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final account in accounts) ...[
                      Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                        child: ListTile(
                          leading: const Icon(Icons.person_rounded),
                          title: Text(account.accountName),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chevron_right_rounded),
                              PopupMenuButton<String>(
                                tooltip: '账号操作',
                                onSelected: (value) {
                                  if (value == 'remove') {
                                    onRemoveAccount(account);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text('从本机移除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => onSelectAccount(account.accountId),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 4),
                  ],
                  _EntryCard(
                    icon: Icons.add_card_rounded,
                    title: '首次使用 / 注册激活',
                    subtitle: '使用一枚新激活码创建账号，只需要这一次。',
                    buttonText: '注册并激活',
                    onTap: onActivate,
                  ),
                  const SizedBox(height: 14),
                  _EntryCard(
                    icon: Icons.devices_other_rounded,
                    title: '已有账号 / 加入已有账号',
                    subtitle: '从原设备加入，或导入之前保存的完整数据包。',
                    buttonText: '加入已有账号',
                    onTap: onJoin,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccountActivationView extends StatefulWidget {
  const AccountActivationView({
    required this.onActivate,
    required this.onActivated,
    super.key,
  });

  final Future<void> Function({
    required String activationCode,
    required String accountName,
    required String password,
  }) onActivate;
  final VoidCallback onActivated;

  @override
  State<AccountActivationView> createState() => _AccountActivationViewState();
}

class _AccountActivationViewState extends State<AccountActivationView> {
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
      await widget.onActivate(
        activationCode: _code.text,
        accountName: _accountName.text,
        password: _password.text,
      );
      if (!mounted) return;
      widget.onActivated();
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '首次注册需要联网核销激活码。注册成功后激活码不再参与登录，账号之后可离线使用。',
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
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? '隐藏密码' : '显示密码',
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
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
                            prefixIcon: const Icon(Icons.lock_reset_rounded),
                            suffixIcon: IconButton(
                              tooltip:
                                  _showPasswordAgain ? '隐藏密码' : '显示密码',
                              onPressed: () => setState(
                                () => _showPasswordAgain = !_showPasswordAgain,
                              ),
                              icon: Icon(
                                _showPasswordAgain
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
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _activate,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(_busy ? '正在验证…' : '注册并激活'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '授权服务器只核销激活码，不接收账号名、密码或业务数据；注册成功后登录、使用和设备同步都不依赖它。',
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

class AccountLoginView extends StatefulWidget {
  const AccountLoginView({
    required this.initialAccountName,
    required this.onLogin,
    required this.onChooseOther,
    required this.onRemove,
    super.key,
  });

  final String initialAccountName;
  final Future<bool> Function({
    required String accountName,
    required String password,
  }) onLogin;
  final VoidCallback onChooseOther;
  final Future<void> Function() onRemove;

  @override
  State<AccountLoginView> createState() => _AccountLoginViewState();
}

class _AccountLoginViewState extends State<AccountLoginView> {
  late final TextEditingController _accountName =
      TextEditingController(text: widget.initialAccountName);
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
    try {
      final ok = await widget.onLogin(
        accountName: _accountName.text,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() {
        if (!ok) _error = '账号名或密码不正确。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRemove();
    } catch (error) {
      if (mounted) setState(() => _error = '移除本机账号失败：$error');
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
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
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? '隐藏密码' : '显示密码',
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('登录'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _busy ? null : widget.onChooseOther,
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('使用其他账号 / 返回初始页'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _remove,
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

class RevokedAccountView extends StatelessWidget {
  const RevokedAccountView({
    required this.onRejoin,
    required this.onChooseOther,
    required this.onRemove,
    this.onRetryAcknowledgement,
    this.description =
        '解绑后不能只凭账号名和密码重新进入。要重新加入，需要从仍在使用的原设备加入，或导入这个账号的完整数据包。',
    super.key,
  });

  final VoidCallback onRejoin;
  final VoidCallback onChooseOther;
  final VoidCallback onRemove;
  final VoidCallback? onRetryAcknowledgement;
  final String description;

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
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.phonelink_erase_rounded,
                        size: 44,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '这台设备已解绑',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRejoin,
                          icon: const Icon(Icons.devices_other_rounded),
                          label: const Text('重新加入已有账号'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: onChooseOther,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('返回账号选择'),
                      ),
                      if (onRetryAcknowledgement != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: onRetryAcknowledgement,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('重试发送解绑确认'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onRemove,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('从本机移除这个账号'),
                      ),
                    ],
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

class AccountManagementView extends StatelessWidget {
  const AccountManagementView({
    required this.accountName,
    required this.password,
    required this.devices,
    required this.currentDeviceId,
    required this.onRenameAccount,
    required this.onChangePassword,
    required this.onRenameDevice,
    required this.onRevokeDevice,
    required this.onSignOut,
    this.avatarBytes,
    this.onEditAvatar,
    this.onAddDevice,
    this.guideTargets,
    super.key,
  });

  final String accountName;
  final String? password;
  final Uint8List? avatarBytes;
  final VoidCallback? onEditAvatar;
  final List<AccountDevice> devices;
  final String? currentDeviceId;
  final Future<void> Function(String name) onRenameAccount;
  final Future<void> Function(String currentPassword, String newPassword)
      onChangePassword;
  final Future<void> Function(AccountDevice device, String name) onRenameDevice;
  final Future<void> Function(AccountDevice device) onRevokeDevice;
  final VoidCallback? onAddDevice;
  final Future<void> Function() onSignOut;
  final QuickStartGuideTargets? guideTargets;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SpotlightTarget(
          targetKey: guideTargets?.accountTitleKey,
          child: const Text(
            '账号与设备',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 16,
          top: 8,
          right: 16,
        ),
        children: [
          AccountProfileCard(
            accountName: accountName,
            avatarBytes: avatarBytes,
            onEditAvatar: onEditAvatar,
          ),
          const SizedBox(height: 12),
          AccountCredentialCard(
            accountName: accountName,
            password: password,
            onRenameAccount: onRenameAccount,
            onChangePassword: onChangePassword,
          ),
          const SizedBox(height: 14),
          AccountDevicesCard(
            devices: devices,
            currentDeviceId: currentDeviceId,
            onRenameDevice: onRenameDevice,
            onRevokeDevice: onRevokeDevice,
          ),
          if (onAddDevice != null) ...[
            const SizedBox(height: 14),
            SpotlightTarget(
              targetKey: guideTargets?.accountDevicesKey,
              child: GuildContentPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.add_to_home_screen_rounded),
                  title: const Text(
                    '添加设备',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('二维码、扫码或配对码'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onAddDevice,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async => onSignOut(),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

class AccountProfileCard extends StatelessWidget {
  const AccountProfileCard({
    required this.accountName,
    this.avatarBytes,
    this.onEditAvatar,
    super.key,
  });

  final String accountName;
  final Uint8List? avatarBytes;
  final VoidCallback? onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GuildContentPanel(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            InkWell(
              onTap: onEditAvatar,
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colors.secondaryContainer,
                    foregroundImage:
                        avatarBytes == null ? null : MemoryImage(avatarBytes!),
                    child: avatarBytes == null
                        ? Icon(
                            Icons.person_rounded,
                            color: colors.onSecondaryContainer,
                            size: 30,
                          )
                        : null,
                  ),
                  if (onEditAvatar != null)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 12,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountName.isEmpty ? '我的账号' : accountName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    onEditAvatar == null ? '账号资料' : '点击头像可更换',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountCredentialCard extends StatefulWidget {
  const AccountCredentialCard({
    required this.accountName,
    required this.password,
    required this.onRenameAccount,
    required this.onChangePassword,
    super.key,
  });

  final String accountName;
  final String? password;
  final Future<void> Function(String name) onRenameAccount;
  final Future<void> Function(String currentPassword, String newPassword)
      onChangePassword;

  @override
  State<AccountCredentialCard> createState() => _AccountCredentialCardState();
}

class _AccountCredentialCardState extends State<AccountCredentialCard> {
  bool _showPassword = false;

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制')),
    );
  }

  Future<void> _changeAccountName() async {
    final controller = TextEditingController(text: widget.accountName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改账号名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '新账号名',
            helperText: '2–32 个字符',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    try {
      await widget.onRenameAccount(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号名已修改')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        var showCurrent = false;
        var showNext = false;
        var showAgain = false;
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration decoration(
              String label,
              bool visible,
              VoidCallback toggle, {
              String? helperText,
            }) =>
                InputDecoration(
                  labelText: label,
                  helperText: helperText,
                  suffixIcon: IconButton(
                    tooltip: visible ? '隐藏密码' : '显示密码',
                    onPressed: toggle,
                    icon: Icon(
                      visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                );
            void submit() {
              if (next.text != again.text) {
                setDialogState(() => errorText = '两次输入的新密码不一致。');
                return;
              }
              Navigator.of(dialogContext).pop((current.text, next.text));
            }

            return AlertDialog(
              scrollable: true,
              title: const Text('修改密码'),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: current,
                      autofocus: true,
                      obscureText: !showCurrent,
                      textInputAction: TextInputAction.next,
                      decoration: decoration(
                        '当前密码',
                        showCurrent,
                        () => setDialogState(
                          () => showCurrent = !showCurrent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: next,
                      obscureText: !showNext,
                      textInputAction: TextInputAction.next,
                      decoration: decoration(
                        '新密码',
                        showNext,
                        () => setDialogState(() => showNext = !showNext),
                        helperText: '至少 6 个字符',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: again,
                      obscureText: !showAgain,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: decoration(
                        '确认新密码',
                        showAgain,
                        () => setDialogState(() => showAgain = !showAgain),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(onPressed: submit, child: const Text('保存')),
              ],
            );
          },
        );
      },
    );
    current.dispose();
    next.dispose();
    again.dispose();
    if (result == null || !mounted) return;
    try {
      await widget.onChangePassword(result.$1, result.$2);
      if (!mounted) return;
      setState(() => _showPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已修改')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final password = widget.password;
    return GuildContentPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_rounded),
                const SizedBox(width: 10),
                Text(
                  '账号凭据',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '只在当前设备已登录时可查看。忘记账密时，可以从仍然登录着的设备找回。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _CredentialRow(
              label: '账号名',
              value: widget.accountName,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '修改账号名',
                    onPressed: _changeAccountName,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (widget.accountName.isNotEmpty)
                    IconButton(
                      tooltip: '复制账号名',
                      onPressed: () => _copy(widget.accountName, '账号名'),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                ],
              ),
            ),
            const Divider(height: 20),
            _CredentialRow(
              label: '密码',
              value: password == null
                  ? '当前不可查看'
                  : (_showPassword ? password : '••••••••'),
              trailing: password == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '修改密码',
                          onPressed: _changePassword,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: _showPassword ? '隐藏密码' : '显示密码',
                          onPressed: () => setState(
                            () => _showPassword = !_showPassword,
                          ),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: '复制密码',
                          onPressed: () => _copy(password, '密码'),
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountDevicesCard extends StatelessWidget {
  const AccountDevicesCard({
    required this.devices,
    required this.currentDeviceId,
    required this.onRenameDevice,
    required this.onRevokeDevice,
    super.key,
  });

  final List<AccountDevice> devices;
  final String? currentDeviceId;
  final Future<void> Function(AccountDevice device, String name) onRenameDevice;
  final Future<void> Function(AccountDevice device) onRevokeDevice;

  @override
  Widget build(BuildContext context) {
    return GuildContentPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_other_rounded),
                const SizedBox(width: 10),
                Text(
                  '使用中设备',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text('${devices.length} 台'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '设备数量不限制。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final device in devices)
              _DeviceTile(
                device: device,
                isCurrent: device.id == currentDeviceId,
                onRename: (name) => onRenameDevice(device, name),
                onRevoke: device.id == currentDeviceId
                    ? null
                    : () => onRevokeDevice(device),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isCurrent,
    required this.onRename,
    this.onRevoke,
  });

  final AccountDevice device;
  final bool isCurrent;
  final ValueChanged<String> onRename;
  final VoidCallback? onRevoke;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: device.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '设备名称'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onRename(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final platformIcon = switch (device.platform) {
      'windows' => Icons.desktop_windows_outlined,
      'macos' || 'linux' => Icons.computer_outlined,
      'ios' => Icons.phone_iphone_rounded,
      _ => Icons.smartphone_rounded,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(platformIcon),
      title: Row(
        children: [
          Flexible(child: Text(device.name)),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                child: Text(
                  '当前设备',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text('最后使用 ${formatAccountDeviceTime(device.lastSeenAt.toLocal())}'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'rename') _rename(context);
          if (value == 'revoke') onRevoke?.call();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'rename',
            child: Text('修改设备名称'),
          ),
          if (onRevoke != null)
            const PopupMenuItem(
              value: 'revoke',
              child: Text('解绑设备'),
            ),
        ],
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(value, maxLines: 1)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 34, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onTap,
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatAccountDeviceTime(DateTime value) {
  final now = DateTime.now();
  final sameDay = value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
  String two(int n) => n.toString().padLeft(2, '0');
  if (sameDay) {
    return '今天 ${two(value.hour)}:${two(value.minute)}';
  }
  return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
}
