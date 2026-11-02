import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../core/account/account_models.dart';
import '../../../core/account/account_store.dart';
import '../../../core/portability/data_portability_file_bridge.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../shared/presentation/spotlight_guide.dart';
import 'account_common_views.dart';
import 'avatar_crop_page.dart';
import 'share_account_device_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    required this.store,
    required this.buildTransferPackage,
    required this.syncCoordinator,
    required this.onBeforeSignOut,
    required this.onRevokeDevice,
    this.guideTargets,
    super.key,
  });

  final AccountStore store;
  final Future<String> Function() buildTransferPackage;
  final SyncCoordinator syncCoordinator;
  final Future<void> Function() onBeforeSignOut;
  final Future<void> Function(String deviceId) onRevokeDevice;
  final QuickStartGuideTargets? guideTargets;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
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

  Future<void> _renameDevice(AccountDevice device, String name) async {
    try {
      await widget.store.renameDevice(device.id, name);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _revokeDevice(AccountDevice device) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解绑这台设备？'),
        content: Text(
          '“${device.name}”会从使用中设备移除。\n\n'
          '如果这台设备只是暂时离线，请选择“普通解绑”：'
          '它下次上线会收到解绑记录并退出账号，确认后才停止共享同步目录。\n\n'
          '如果这台设备上的 App 已经卸载、设备丢失或确定不会再打开旧安装，'
          '请选择“已卸载/丢失”：旧安装不可能再回传确认，会直接结束这条旧同步关系。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('normal'),
            child: const Text('普通解绑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('force'),
            child: const Text('已卸载/丢失'),
          ),
        ],
      ),
    );
    if (action == null) return;

    try {
      await widget.onRevokeDevice(device.id);
      if (action == 'force') {
        await widget.syncCoordinator.forceFinalizeRevokedDevice(device.id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解绑设备失败：$error')),
      );
    }
  }

  Future<void> _signOut() async {
    await widget.onBeforeSignOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.store.returnToAccountChooser();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => AccountManagementView(
        accountName: widget.store.accountName ?? '',
        password: widget.store.accountPassword,
        avatarBytes: widget.store.accountAvatarBytes,
        onEditAvatar: _avatarBusy ? null : _pickAvatar,
        devices: widget.store.activeDevices,
        currentDeviceId: widget.store.currentDeviceId,
        onRenameAccount: widget.store.renameAccount,
        onChangePassword: (currentPassword, newPassword) =>
            widget.store.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        ),
        onRenameDevice: _renameDevice,
        onRevokeDevice: _revokeDevice,
        onAddDevice: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ShareAccountDevicePage(
              buildTransferPackage: widget.buildTransferPackage,
              syncCoordinator: widget.syncCoordinator,
            ),
          ),
        ),
        onSignOut: _signOut,
        guideTargets: widget.guideTargets,
      ),
    );
  }
}
