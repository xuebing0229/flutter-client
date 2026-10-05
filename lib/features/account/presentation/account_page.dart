import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../core/account/account_models.dart';
import '../../../core/account/account_store.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../shared/presentation/layout_spacing.dart';
import 'avatar_crop_page.dart';
import 'share_account_device_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    required this.store,
    required this.buildTransferPackage,
    required this.syncCoordinator,
    required this.onBeforeSignOut,
    required this.onRevokeDevice,
    super.key,
  });

  final AccountStore store;
  final Future<String> Function() buildTransferPackage;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function() onBeforeSignOut;
  final Future<void> Function(String deviceId) onRevokeDevice;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final devices = store.activeDevices;
        final currentId = store.currentDeviceId;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              '账号与设备',
              style: TextStyle(fontWeight: FontWeight.w700),
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
              _AccountCard(store: store),
              const SizedBox(height: 12),
              _CredentialCard(store: store),
              const SizedBox(height: 14),
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
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
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          const Spacer(),
                          Text('${devices.length} 台'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '设备数量不限制。解绑记录会在下一次正常数据同步时同步到其他设备。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final device in devices)
                        _DeviceTile(
                          device: device,
                          isCurrent: device.id == currentId,
                          onRename: () => _renameDevice(context, device),
                          onRevoke: device.id == currentId
                              ? null
                              : () => _revokeDevice(context, device),
                        ),
                      if (store.revokedDeviceCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            '另有 ${store.revokedDeviceCount} 条已解绑设备记录，会保留用于防止其他设备的滞后同步状态重新恢复已解绑设备。',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ShareAccountDevicePage(
                        buildTransferPackage: buildTransferPackage,
                        syncCoordinator: syncCoordinator,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  await onBeforeSignOut();
                  if (!context.mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await store.returnToAccountChooser();
                },
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('退出登录'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameDevice(
    BuildContext context,
    AccountDevice device,
  ) async {
    final controller = TextEditingController(text: device.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '设备名称'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return;
    try {
      await store.renameDevice(device.id, result);
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  Future<void> _revokeDevice(
    BuildContext context,
    AccountDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解绑这台设备？'),
        content: Text(
          '“${device.name}”会从使用中设备移除。在线设备收到解绑记录后会退出账号，'
          '并回传确认；确认到达后才会停止向它共享同步目录。'
          '如果设备离线，会在下次上线收到解绑记录后退出。'
          '之后重新加入账号时仍不需要再次输入激活码。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await onRevokeDevice(device.id);
    }
  }
}

class _CredentialCard extends StatefulWidget {
  const _CredentialCard({required this.store});

  final AccountStore store;

  @override
  State<_CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends State<_CredentialCard> {
  bool _showPassword = false;

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制')),
    );
  }

  Future<void> _changeAccountName() async {
    final controller = TextEditingController(
      text: widget.store.accountName ?? '',
    );

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
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null || !mounted) return;

    try {
      await widget.store.renameAccount(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号名已修改')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
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
            InputDecoration passwordDecoration(
              String label,
              bool visible,
              VoidCallback onToggle, {
              String? helperText,
            }) {
              return InputDecoration(
                labelText: label,
                helperText: helperText,
                suffixIcon: IconButton(
                  tooltip: visible ? '隐藏密码' : '显示密码',
                  onPressed: onToggle,
                  icon: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              );
            }

            void submit() {
              if (next.text != again.text) {
                setDialogState(() {
                  errorText = '两次输入的新密码不一致。';
                });
                return;
              }
              Navigator.of(dialogContext).pop(
                (current.text, next.text),
              );
            }

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
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
                      decoration: passwordDecoration(
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
                      decoration: passwordDecoration(
                        '新密码',
                        showNext,
                        () => setDialogState(
                          () => showNext = !showNext,
                        ),
                        helperText: '至少 6 个字符',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: again,
                      obscureText: !showAgain,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: passwordDecoration(
                        '确认新密码',
                        showAgain,
                        () => setDialogState(
                          () => showAgain = !showAgain,
                        ),
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
                FilledButton(
                  onPressed: submit,
                  child: const Text('保存'),
                ),
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
      await widget.store.changePassword(
        currentPassword: result.$1,
        newPassword: result.$2,
      );
      if (!mounted) return;
      setState(() => _showPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已修改')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accountName = widget.store.accountName ?? '';
    final password = widget.store.accountPassword;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
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
              value: accountName,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '修改账号名',
                    onPressed: _changeAccountName,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (accountName.isNotEmpty)
                    IconButton(
                      tooltip: '复制账号名',
                      onPressed: () => _copy(accountName, '账号名'),
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
                          onPressed: () {
                            setState(() => _showPassword = !_showPassword);
                          },
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
        Expanded(
          child: SelectableText(
            value,
            maxLines: 1,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _AccountCard extends StatefulWidget {
  const _AccountCard({required this.store});

  final AccountStore store;

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  static const DataPortabilityFileBridge _fileBridge =
      DataPortabilityFileBridge();

  bool _avatarBusy = false;

  Future<void> _pickAvatar() async {
    if (_avatarBusy) return;

    setState(() => _avatarBusy = true);
    try {
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) => AvatarCropPage(
            pickImage: _fileBridge.pickImage,
          ),
        ),
      );
      if (!mounted || cropped == null) return;

      final croppedImage = img.decodeImage(cropped);
      if (croppedImage == null) {
        throw const FormatException('头像裁剪结果无效。');
      }

      var processed = croppedImage;
      if (processed.width > 320 || processed.height > 320) {
        processed = processed.width >= processed.height
            ? img.copyResize(processed, width: 320)
            : img.copyResize(processed, height: 320);
      }

      var encoded = img.encodeJpg(processed, quality: 82);
      if (encoded.length > 192 * 1024) {
        encoded = img.encodeJpg(processed, quality: 72);
      }
      if (encoded.length > 192 * 1024) {
        processed = processed.width >= processed.height
            ? img.copyResize(processed, width: 256)
            : img.copyResize(processed, height: 256);
        encoded = img.encodeJpg(processed, quality: 72);
      }

      await widget.store.setAccountAvatarBytes(encoded);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新，并会随账号数据同步')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像更新失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatar = widget.store.accountAvatarBytes;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Tooltip(
              message: '点击更换头像',
              child: InkWell(
                onTap: _avatarBusy ? null : _pickAvatar,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colors.secondaryContainer,
                      foregroundImage:
                          avatar == null ? null : MemoryImage(avatar),
                      child: avatar == null
                          ? Icon(
                              Icons.person_rounded,
                              color: colors.onSecondaryContainer,
                              size: 30,
                            )
                          : null,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.surface,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _avatarBusy
                              ? SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
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
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.store.accountName ?? '我的账号',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '点击头像可更换',
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isCurrent,
    this.onRename,
    this.onRevoke,
  });

  final AccountDevice device;
  final bool isCurrent;
  final VoidCallback? onRename;
  final VoidCallback? onRevoke;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      subtitle: Text('最后使用 ${_formatTime(device.lastSeenAt.toLocal())}'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'rename') onRename?.call();
          if (value == 'revoke') onRevoke?.call();
        },
        itemBuilder: (context) => [
          if (onRename != null)
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

String _formatTime(DateTime value) {
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
