import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../account/account_models.dart';
import '../portability/app_backup_data.dart';
import 'atomic_file.dart';

class AppDataPersistence {
  const AppDataPersistence({Directory? supportDirectory})
      : _supportDirectory = supportDirectory;

  final Directory? _supportDirectory;

  Future<Directory> _appSupportDirectory() async =>
      _supportDirectory ?? await getApplicationSupportDirectory();

  static const String _fileName = 'app-data-v1.json';
  static const String _focusForegroundExitFileName = 'focus-last-foreground-exit.txt';
  static const String _accountsDirName = 'accounts';
  static final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  String _safeAccountId(String accountId) => requireValidAccountId(accountId);

  Future<Directory> _accountDirectory(String accountId) async {
    final dir = await _appSupportDirectory();
    return Directory(
      '${dir.path}/$_accountsDirName/${_safeAccountId(accountId)}',
    );
  }

  Future<File> _accountFile(String accountId) async {
    final dir = await _accountDirectory(accountId);
    return File('${dir.path}/$_fileName');
  }

  Future<File> _focusForegroundExitFile(String accountId) async {
    final dir = await _accountDirectory(accountId);
    return File('${dir.path}/$_focusForegroundExitFileName');
  }

  Future<DateTime?> loadFocusForegroundExit({
    required String accountId,
  }) async {
    try {
      final file = await _focusForegroundExitFile(accountId);
      if (!await file.exists()) return null;
      return DateTime.tryParse((await file.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFocusForegroundExit({
    required String accountId,
    required DateTime value,
  }) async {
    final file = await _focusForegroundExitFile(accountId);
    await file.parent.create(recursive: true);
    await atomicWriteString(file, value.toUtc().toIso8601String());
  }

  Future<AppBackupData?> load({required String accountId}) async {
    await (_writeTails[accountId] ?? Future<void>.value());

    final file = await _accountFile(accountId);
    if (!await file.exists()) return null;

    final backup = await _read(file);
    if (backup == null) return null;
    _assertAccountBinding(backup, accountId);
    return backup;
  }

  Future<List<AccountSyncState>> discoverRecoverableAccounts() async {
    final supportDir = await _appSupportDirectory();
    final accountsDir = Directory('${supportDir.path}/$_accountsDirName');
    if (!await accountsDir.exists()) {
      return const <AccountSyncState>[];
    }

    final backups = <AppBackupData>[];
    await for (final entity in accountsDir.list(followLinks: false)) {
      if (entity is! Directory) continue;

      final file = File('${entity.path}/$_fileName');
      if (!await file.exists()) continue;

      try {
        final backup = await _read(file);
        final account = backup?.accountSyncState;
        final folderName = entity.path.split(Platform.pathSeparator).last;
        if (backup != null &&
            account != null &&
            account.accountId.isNotEmpty &&
            account.hasCredentials &&
            folderName == _safeAccountId(account.accountId)) {
          backups.add(backup);
        }
      } catch (_) {
        // One damaged account data file must not block recovery of the others.
      }
    }

    backups.sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    return <AccountSyncState>[
      for (final backup in backups) backup.accountSyncState!,
    ];
  }

  Future<void> save(AppBackupData data, {required String accountId}) {
    _assertAccountBinding(data, accountId);

    final operation = (_writeTails[accountId] ?? Future<void>.value())
        .then<void>((_) => _writeAccountData(data, accountId));
    _writeTails[accountId] = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> deleteAccountData(String accountId) {
    final operation = (_writeTails[accountId] ?? Future<void>.value())
        .then<void>((_) => _deleteAccountData(accountId));
    _writeTails[accountId] = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _writeAccountData(AppBackupData data, String accountId) async {
    final file = await _accountFile(accountId);
    await file.parent.create(recursive: true);

    await atomicWriteString(file, data.encode(pretty: false));
  }

  Future<void> _deleteAccountData(String accountId) async {
    final file = await _accountFile(accountId);
    final accountDir = file.parent;
    if (await accountDir.exists()) {
      await accountDir.delete(recursive: true);
    }
  }

  Future<AppBackupData?> _read(File file) async {
    final source = await file.readAsString();
    // Missing files represent a fresh account; an existing empty file is
    // damaged data and must never silently initialize an empty workspace.
    if (source.trim().isEmpty) {
      throw const FormatException('本地数据文件为空，已停止读取以避免覆盖原有数据。');
    }
    return AppBackupData.decode(source);
  }

  void _assertAccountBinding(AppBackupData data, String accountId) {
    final embedded = data.accountSyncState?.accountId;
    if (embedded == null || embedded != accountId) {
      throw const FormatException('账号数据归属不一致，已拒绝读写。');
    }
  }
}
