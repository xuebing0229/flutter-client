import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/portability/app_backup_data.dart';
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
                    '可以登录这台设备上已经保存的账号，也可以注册新账号或从其他设备加入。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  if (store.localAccounts.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '本机已有账号',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final account in store.localAccounts) ...[
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
                                    _removeLocalAccount(context, account);
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
                          onTap: () => store.selectLocalAccount(
                            account.accountId,
                          ),
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
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivateAccountPage(store: store),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _EntryCard(
                    icon: Icons.devices_other_rounded,
                    title: '已有账号 / 加入已有账号',
                    subtitle: '从原设备扫码加入，或导入之前保存的完整数据包。',
                    buttonText: '加入已有账号',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExistingAccountJoinPage(
                          onAdoptBackup: onAdoptBackup,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  Future<void> _removeLocalAccount(
    BuildContext context,
    LocalAccountSummary account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('从本机移除“${account.accountName}”？'),
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
      await onRemoveLocalAccount(account.accountId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除本机账号失败：$error')),
      );
    }
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
