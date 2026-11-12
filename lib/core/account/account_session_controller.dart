import 'account_local_state.dart';
import 'account_models.dart';
import 'account_session_logic.dart';
import 'account_state_mutations.dart';

class AccountSessionController {
  AccountSessionController({
    required this.accounts,
    required this.getSelectedAccountId,
    required this.setSelectedAccountId,
    required this.getStatus,
    required this.setStatus,
    required this.persist,
    required this.notify,
    required this.touchForLogin,
  });

  final Map<String, LocalAccountRecord> accounts;
  final String? Function() getSelectedAccountId;
  final void Function(String? value) setSelectedAccountId;
  final AccountStatus Function() getStatus;
  final void Function(AccountStatus value) setStatus;
  final Future<void> Function() persist;
  final void Function() notify;
  final Future<AccountSyncState> Function(LocalAccountRecord record)
      touchForLogin;

  LocalAccountRecord? get selectedRecord {
    final id = getSelectedAccountId();
    return id == null ? null : accounts[id];
  }

  Future<void> selectLocalAccount(String accountId) async {
    final record = accounts[accountId];
    if (record == null) {
      throw const FormatException('这个本机账号已经不存在。');
    }
    setSelectedAccountId(accountId);
    final locked = record.copyWith(stayLoggedIn: false);
    accounts[accountId] = locked;
    setStatus(accountStatusForRecord(locked));
    await persist();
    notify();
  }

  Future<bool> unlock({
    required String accountName,
    required String password,
  }) async {
    final record = selectedRecord;
    if (record == null || record.syncState.isRevoked(record.currentDeviceId)) {
      setStatus(accountStatusForRecord(record));
      notify();
      return false;
    }

    if (!accountCredentialsMatch(
      record: record,
      accountName: accountName,
      password: password,
    )) {
      return false;
    }

    final touched = await touchForLogin(record);
    accounts[record.syncState.accountId] = record.copyWith(
      syncState: touched,
      stayLoggedIn: true,
    );
    setStatus(AccountStatus.unlocked);
    await persist();
    notify();
    return true;
  }

  Future<void> lock() async {
    final record = selectedRecord;
    if (record == null) {
      setStatus(AccountStatus.unactivated);
      notify();
      return;
    }
    final locked = record.copyWith(stayLoggedIn: false);
    accounts[record.syncState.accountId] = locked;
    setStatus(accountStatusForRecord(locked));
    await persist();
    notify();
  }

  Future<void> returnToAccountChooser() async {
    final record = selectedRecord;
    if (record != null) {
      accounts[record.syncState.accountId] =
          record.copyWith(stayLoggedIn: false);
    }
    setSelectedAccountId(null);
    setStatus(AccountStatus.unactivated);
    await persist();
    notify();
  }

  Future<void> renameDevice(String deviceId, String name) async {
    final record = selectedRecord;
    if (record == null) return;
    accounts[record.syncState.accountId] = record.copyWith(
      syncState: renameAccountDeviceState(
        record.syncState,
        deviceId: deviceId,
        name: name,
      ),
    );
    await persist();
    notify();
  }

  Future<void> renameCurrentDevice(String name) {
    final id = selectedRecord?.currentDeviceId;
    if (id == null) return Future<void>.value();
    return renameDevice(id, name);
  }

  Future<void> renameAccount(String name) async {
    final record = selectedRecord;
    if (record == null) return;
    accounts[record.syncState.accountId] = record.copyWith(
      syncState: renameAccountState(record.syncState, name),
    );
    await persist();
    notify();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final record = selectedRecord;
    if (record == null || getStatus() != AccountStatus.unlocked) {
      throw const FormatException('当前账号未登录，不能修改密码。');
    }
    accounts[record.syncState.accountId] = record.copyWith(
      syncState: changeAccountPasswordState(
        record.syncState,
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
    await persist();
    notify();
  }

  Future<void> revokeDevice(String deviceId) async {
    final record = selectedRecord;
    if (record == null) return;
    accounts[record.syncState.accountId] = record.copyWith(
      syncState: revokeAccountDeviceState(
        record.syncState,
        currentDeviceId: record.currentDeviceId,
        deviceId: deviceId,
      ),
    );
    await persist();
    notify();
  }
}
