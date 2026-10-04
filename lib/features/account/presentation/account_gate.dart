import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import '../../../core/portability/app_backup_data.dart';
import 'account_entry_page.dart';
import 'local_login_page.dart';
import 'revoked_device_page.dart';

class AccountGate extends StatelessWidget {
  const AccountGate({
    required this.store,
    required this.onAdoptBackup,
    required this.onRemoveLocalAccount,
    required this.onAcknowledgeRevocation,
    required this.unlockedBuilder,
    super.key,
  });

  final AccountStore store;
  final Future<void> Function(AppBackupData backup) onAdoptBackup;
  final Future<void> Function(String accountId) onRemoveLocalAccount;
  final Future<void> Function() onAcknowledgeRevocation;
  final Widget Function(String accountId) unlockedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return switch (store.status) {
          AccountStatus.loading => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          AccountStatus.unactivated => AccountEntryPage(
              store: store,
              onAdoptBackup: onAdoptBackup,
              onRemoveLocalAccount: onRemoveLocalAccount,
            ),
          AccountStatus.revoked => RevokedDevicePage(
              store: store,
              onAdoptBackup: onAdoptBackup,
              onRemoveLocalAccount: onRemoveLocalAccount,
              onAcknowledgeRevocation: onAcknowledgeRevocation,
            ),
          AccountStatus.locked => LocalLoginPage(
              store: store,
              onRemoveLocalAccount: onRemoveLocalAccount,
            ),
          AccountStatus.unlocked => unlockedBuilder(store.accountId!),
        };
      },
    );
  }
}
