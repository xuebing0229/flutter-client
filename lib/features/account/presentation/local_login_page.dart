import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import 'account_common_views.dart';

class LocalLoginPage extends StatelessWidget {
  const LocalLoginPage({
    required this.store,
    required this.onRemoveLocalAccount,
    super.key,
  });

  final AccountStore store;
  final Future<void> Function(String accountId) onRemoveLocalAccount;

  @override
  Widget build(BuildContext context) {
    return AccountLoginView(
      initialAccountName: store.accountName ?? '',
      onLogin: ({
        required accountName,
        required password,
      }) => store.unlock(
        accountName: accountName,
        password: password,
      ),
      onChooseOther: store.returnToAccountChooser,
      onRemove: () => _removeCurrentAccount(context),
    );
  }

  Future<void> _removeCurrentAccount(BuildContext context) async {
    final accountId = store.accountId;
    final accountName = store.accountName ?? '这个账号';
    if (accountId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('从本机移除“$accountName”？'),
          content: const Text(
            '不需要先登录。会立即从这台设备移除这个账号和本地工作数据。'
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
    if (confirmed == true) {
      await onRemoveLocalAccount(accountId);
    }
  }
}
