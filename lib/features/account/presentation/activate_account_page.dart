import 'package:flutter/material.dart';

import '../../../core/account/account_store.dart';
import 'account_common_views.dart';

class ActivateAccountPage extends StatelessWidget {
  const ActivateAccountPage({
    required this.store,
    super.key,
  });

  final AccountStore store;

  @override
  Widget build(BuildContext context) {
    return AccountActivationView(
      onActivate: ({
        required activationCode,
        required accountName,
        required password,
      }) => store.activate(
        activationCode: activationCode,
        accountName: accountName,
        password: password,
      ),
      onActivated: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }
}
