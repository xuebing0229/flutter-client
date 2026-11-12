import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/portability/app_backup_data.dart';
import 'account_common_views.dart';
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

  @override
  Widget build(BuildContext context) {
    return RevokedAccountView(
      onRejoin: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExistingAccountJoinPage(
            onAdoptBackup: onAdoptBackup,
          ),
        ),
      ),
      onChooseOther: store.returnToAccountChooser,
      onRetryAcknowledgement: () => _retryAcknowledgement(context),
      onRemove: () => _removeLocalAccount(context),
    );
  }

  Future<void> _retryAcknowledgement(BuildContext context) async {
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
    if (confirmed == true) {
      await onRemoveLocalAccount(accountId);
    }
  }
}
