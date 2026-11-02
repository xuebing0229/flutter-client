import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/portability/app_backup_data.dart';
import 'account_common_views.dart';
import 'activate_account_page.dart';
import 'existing_account_join_page.dart';

class AccountEntryPage extends StatelessWidget {
  const AccountEntryPage({
    required this.store,
    required this.onAdoptBackup,
    required this.onRemoveLocalAccount,
    super.key,
  });

  final AccountStore store;
  final Future<void> Function(AppBackupData backup) onAdoptBackup;
  final Future<void> Function(String accountId) onRemoveLocalAccount;

  @override
  Widget build(BuildContext context) {
    return AccountEntryView(
      accounts: [
        for (final account in store.localAccounts)
          AccountEntryItem(
            accountId: account.accountId,
            accountName: account.accountName,
          ),
      ],
      onSelectAccount: store.selectLocalAccount,
      onRemoveAccount: (account) => _removeLocalAccount(context, account),
      onActivate: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActivateAccountPage(store: store),
        ),
      ),
      onJoin: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExistingAccountJoinPage(
            onAdoptBackup: onAdoptBackup,
          ),
        ),
      ),
    );
  }

  Future<void> _removeLocalAccount(
    BuildContext context,
    AccountEntryItem account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('从本机移除“${account.accountName}”？'),
          content: const Text(
            '会立即从这台设备移除这个账号和本地工作数据。'
            '设备解绑状态会在后台静默同步给其他设备；'
            '之后重新加入需要从仍在使用的设备扫码，或导入完整数据包。',
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
      await onRemoveLocalAccount(account.accountId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除本机账号失败：$error')),
      );
    }
  }
}
