import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/portability/app_backup_data.dart';
import 'existing_account_join_page.dart';

class RevokedDevicePage extends StatelessWidget {
  const RevokedDevicePage({
    required this.store,
    required this.onAdoptBackup,
    required this.onRemoveLocalAccount,
    required this.onAcknowledgeRevocation,
    super.key,
  });

  final AccountStore store;
  final Future<void> Function(AppBackupData backup) onAdoptBackup;
  final Future<void> Function(String accountId) onRemoveLocalAccount;
  final Future<void> Function() onAcknowledgeRevocation;

  Future<void> _retryRevocationAcknowledgement(BuildContext context) async {
    try {
      await onAcknowledgeRevocation();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('解绑确认已重新写入同步目录。')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解绑确认写入失败：$error')),
      );
    }
  }

  Future<void> _removeLocalAccount(BuildContext context) async {
    final accountId = store.accountId;
    if (accountId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('从本机移除这个账号？'),
          content: const Text(
            '会删除这台设备保存的账号记录、工作数据和同步目录，'
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
    if (confirmed != true || !context.mounted) return;

    try {
      await onRemoveLocalAccount(accountId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除本机账号失败：$error')),
      );
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
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '解绑后不能只凭账号名和密码重新进入。要重新加入，需要从仍在使用的原设备扫码加入，或导入这个账号的完整数据包。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ExistingAccountJoinPage(
                                onAdoptBackup: onAdoptBackup,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.devices_other_rounded),
                          label: const Text('重新加入已有账号'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: store.returnToAccountChooser,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('返回账号选择'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            _retryRevocationAcknowledgement(context),
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('重试发送解绑确认'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _removeLocalAccount(context),
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
