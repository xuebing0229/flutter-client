import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../account/account_models.dart';

class InteractionHintStore {
  const InteractionHintStore();

  static const _accountsDirName = 'accounts';
  static const _firstRunGuideFile = 'first_run_guide_v1_seen';

  Future<File> _guideFile(String accountId) async {
    final directory = await getApplicationSupportDirectory();
    final safeId = requireValidAccountId(accountId);
    return File(
      '${directory.path}/$_accountsDirName/$safeId/$_firstRunGuideFile',
    );
  }

  Future<bool> hasSeenFirstRunGuide(String accountId) async {
    final file = await _guideFile(accountId);
    return file.exists();
  }

  Future<void> markFirstRunGuideSeen(String accountId) async {
    final file = await _guideFile(accountId);
    await file.parent.create(recursive: true);
    await file.writeAsString('1', flush: true);
  }
}
