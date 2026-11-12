import 'account_models.dart';

enum AccountStatus { loading, unactivated, locked, unlocked, revoked }

class LocalAccountSummary {
  const LocalAccountSummary({
    required this.accountId,
    required this.accountName,
  });

  final String accountId;
  final String accountName;
}

class LocalAccountRecord {
  const LocalAccountRecord({
    required this.syncState,
    required this.currentDeviceId,
    required this.stayLoggedIn,
    this.activationSerial,
  });

  final AccountSyncState syncState;
  final String currentDeviceId;
  final String? activationSerial;
  final bool stayLoggedIn;

  LocalAccountRecord copyWith({
    AccountSyncState? syncState,
    String? currentDeviceId,
    String? activationSerial,
    bool? stayLoggedIn,
  }) {
    return LocalAccountRecord(
      syncState: syncState ?? this.syncState,
      currentDeviceId: currentDeviceId ?? this.currentDeviceId,
      activationSerial: activationSerial ?? this.activationSerial,
      stayLoggedIn: stayLoggedIn ?? this.stayLoggedIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'currentDeviceId': currentDeviceId,
        'activationSerial': activationSerial,
        'stayLoggedIn': stayLoggedIn,
        'syncState': syncState.toJson(),
      };

  factory LocalAccountRecord.fromJson(
    Map<String, dynamic> json, {
    bool allowMissingPassword = false,
  }) {
    final rawSync = json['syncState'];
    if (rawSync is! Map) {
      throw const FormatException('本机账号记录缺少账号数据。');
    }
    final syncState = AccountSyncState.fromCompatibleJson(
      rawSync.map((key, value) => MapEntry(key.toString(), value)),
      allowMissingPassword: allowMissingPassword,
    );
    final currentDeviceId = json['currentDeviceId'];
    final activationSerial = json['activationSerial'];
    final stayLoggedIn = json['stayLoggedIn'];
    if (currentDeviceId is! String || currentDeviceId.isEmpty) {
      throw const FormatException('本机账号记录缺少当前设备 ID。');
    }
    if (activationSerial != null && activationSerial is! String) {
      throw const FormatException('本机账号激活编号格式无效。');
    }
    if (stayLoggedIn is! bool) {
      throw const FormatException('本机账号登录状态格式无效。');
    }
    if (!syncState.devices.containsKey(currentDeviceId)) {
      throw const FormatException('本机账号记录缺少当前设备。');
    }
    return LocalAccountRecord(
      syncState: syncState,
      currentDeviceId: currentDeviceId,
      activationSerial: activationSerial as String?,
      stayLoggedIn: stayLoggedIn,
    );
  }
}
