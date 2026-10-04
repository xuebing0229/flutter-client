final RegExp _accountIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

String requireValidAccountId(String value) {
  if (value.isEmpty || !_accountIdPattern.hasMatch(value)) {
    throw const FormatException('账号身份格式无效。');
  }
  return value;
}

class AccountDevice {
  const AccountDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.nameUpdatedAt,
    this.syncTransportId,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? nameUpdatedAt;
  final String? syncTransportId;

  AccountDevice copyWith({
    String? name,
    String? platform,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    DateTime? nameUpdatedAt,
    String? syncTransportId,
  }) {
    return AccountDevice(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      nameUpdatedAt: nameUpdatedAt ?? this.nameUpdatedAt,
      syncTransportId: syncTransportId ?? this.syncTransportId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'platform': platform,
    'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    if (nameUpdatedAt != null)
      'nameUpdatedAt': nameUpdatedAt!.toUtc().toIso8601String(),
    if (syncTransportId != null) 'syncTransportId': syncTransportId,
  };

  factory AccountDevice.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final platform = json['platform'];
    final nameUpdatedAt = json['nameUpdatedAt'];
    final syncTransportId = json['syncTransportId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('设备记录缺少设备 ID。');
    }
    if (name is! String || name.isEmpty) {
      throw const FormatException('设备记录缺少设备名称。');
    }
    if (platform is! String || platform.isEmpty) {
      throw const FormatException('设备记录缺少平台信息。');
    }
    if (syncTransportId != null &&
        (syncTransportId is! String || syncTransportId.trim().length < 20)) {
      throw const FormatException('设备同步身份格式无效。');
    }
    return AccountDevice(
      id: id,
      name: name,
      platform: platform,
      firstSeenAt: _date(json['firstSeenAt']),
      lastSeenAt: _date(json['lastSeenAt']),
      nameUpdatedAt: nameUpdatedAt == null ? null : _date(nameUpdatedAt),
      syncTransportId: syncTransportId?.trim(),
    );
  }
}

class DeviceRevocation {
  const DeviceRevocation({required this.deviceId, required this.revokedAt});

  final String deviceId;
  final DateTime revokedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'deviceId': deviceId,
    'revokedAt': revokedAt.toUtc().toIso8601String(),
  };

  factory DeviceRevocation.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException('解绑记录缺少设备 ID。');
    }
    return DeviceRevocation(
      deviceId: deviceId,
      revokedAt: _date(json['revokedAt']),
    );
  }
}

class AccountSyncState {
  const AccountSyncState({
    required this.accountId,
    required this.accountName,
    required this.password,
    required this.accountNameUpdatedAt,
    required this.passwordUpdatedAt,
    this.avatarBase64,
    this.avatarUpdatedAt,
    required this.devices,
    required this.revocations,
  });

  final String accountId;
  final String accountName;
  final String password;
  final DateTime accountNameUpdatedAt;
  final DateTime passwordUpdatedAt;
  final String? avatarBase64;
  final DateTime? avatarUpdatedAt;
  final Map<String, AccountDevice> devices;
  final Map<String, DeviceRevocation> revocations;

  bool get hasCredentials => accountName.isNotEmpty && password.isNotEmpty;

  Iterable<AccountDevice> get activeDevices sync* {
    for (final device in devices.values) {
      if (!revocations.containsKey(device.id)) {
        yield device;
      }
    }
  }

  bool isRevoked(String deviceId) => revocations.containsKey(deviceId);

  AccountSyncState merge(AccountSyncState other) {
    if (accountId != other.accountId) {
      throw const FormatException('账号身份不一致，不能合并设备记录。');
    }

    final mergedDevices = <String, AccountDevice>{...devices};
    for (final entry in other.devices.entries) {
      final local = mergedDevices[entry.key];
      final incoming = entry.value;
      if (local == null) {
        mergedDevices[entry.key] = incoming;
        continue;
      }

      final localNameUpdatedAt = local.nameUpdatedAt ?? local.firstSeenAt;
      final incomingNameUpdatedAt =
          incoming.nameUpdatedAt ?? incoming.firstSeenAt;
      final takeIncomingName =
          incomingNameUpdatedAt.isAfter(localNameUpdatedAt) ||
          (incomingNameUpdatedAt.isAtSameMomentAs(localNameUpdatedAt) &&
              incoming.name.compareTo(local.name) < 0);
      final takeIncomingActivity =
          incoming.lastSeenAt.isAfter(local.lastSeenAt);
      final activitySource = takeIncomingActivity ? incoming : local;
      final nameSource = takeIncomingName ? incoming : local;
      final firstSeenAt = incoming.firstSeenAt.isBefore(local.firstSeenAt)
          ? incoming.firstSeenAt
          : local.firstSeenAt;
      final lastSeenAt = takeIncomingActivity
          ? incoming.lastSeenAt
          : local.lastSeenAt;

      mergedDevices[entry.key] = AccountDevice(
        id: local.id,
        name: nameSource.name,
        platform: activitySource.platform,
        firstSeenAt: firstSeenAt,
        lastSeenAt: lastSeenAt,
        nameUpdatedAt: nameSource.nameUpdatedAt,
        // Syncthing identity is a device binding, not mutable profile data.
        // Once known, a newer activity snapshot must not silently remap it.
        syncTransportId: local.syncTransportId ?? incoming.syncTransportId,
      );
    }

    final mergedRevocations = <String, DeviceRevocation>{...revocations};
    for (final entry in other.revocations.entries) {
      final local = mergedRevocations[entry.key];
      final incoming = entry.value;
      if (local == null || incoming.revokedAt.isAfter(local.revokedAt)) {
        mergedRevocations[entry.key] = incoming;
      }
    }

    final takeOtherName = _preferIncomingProfileValue(
      localValue: accountName,
      localUpdatedAt: accountNameUpdatedAt,
      incomingValue: other.accountName,
      incomingUpdatedAt: other.accountNameUpdatedAt,
    );
    final takeOtherPassword =
        other.password.isNotEmpty &&
        (password.isEmpty ||
            _preferIncomingProfileValue(
              localValue: password,
              localUpdatedAt: passwordUpdatedAt,
              incomingValue: other.password,
              incomingUpdatedAt: other.passwordUpdatedAt,
            ));

    final localAvatarUpdatedAt =
        avatarUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final incomingAvatarUpdatedAt =
        other.avatarUpdatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final localAvatar = avatarBase64 ?? '';
    final incomingAvatar = other.avatarBase64 ?? '';
    final takeOtherAvatar =
        incomingAvatar.isNotEmpty &&
        (localAvatar.isEmpty ||
            incomingAvatarUpdatedAt.isAfter(localAvatarUpdatedAt) ||
            (incomingAvatarUpdatedAt.isAtSameMomentAs(localAvatarUpdatedAt) &&
                incomingAvatar.compareTo(localAvatar) < 0));

    final mergedNameUpdatedAt = takeOtherName
        ? other.accountNameUpdatedAt
        : accountNameUpdatedAt;
    final mergedPasswordUpdatedAt = takeOtherPassword
        ? other.passwordUpdatedAt
        : passwordUpdatedAt;
    final mergedAvatarUpdatedAt = takeOtherAvatar
        ? other.avatarUpdatedAt
        : avatarUpdatedAt;

    return AccountSyncState(
      accountId: accountId,
      accountName: takeOtherName ? other.accountName : accountName,
      password: takeOtherPassword ? other.password : password,
      accountNameUpdatedAt: mergedNameUpdatedAt,
      passwordUpdatedAt: mergedPasswordUpdatedAt,
      avatarBase64: takeOtherAvatar ? other.avatarBase64 : avatarBase64,
      avatarUpdatedAt: mergedAvatarUpdatedAt,
      devices: mergedDevices,
      revocations: mergedRevocations,
    );
  }

  AccountSyncState copyWith({
    String? accountName,
    String? password,
    DateTime? accountNameUpdatedAt,
    DateTime? passwordUpdatedAt,
    String? avatarBase64,
    DateTime? avatarUpdatedAt,
    Map<String, AccountDevice>? devices,
    Map<String, DeviceRevocation>? revocations,
  }) {
    return AccountSyncState(
      accountId: accountId,
      accountName: accountName ?? this.accountName,
      password: password ?? this.password,
      accountNameUpdatedAt: accountNameUpdatedAt ?? this.accountNameUpdatedAt,
      passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
      devices: devices ?? this.devices,
      revocations: revocations ?? this.revocations,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'accountId': accountId,
    'accountName': accountName,
    'password': password,
    'accountNameUpdatedAt': accountNameUpdatedAt.toUtc().toIso8601String(),
    'passwordUpdatedAt': passwordUpdatedAt.toUtc().toIso8601String(),
    if (avatarBase64 != null) 'avatarBase64': avatarBase64,
    if (avatarUpdatedAt != null)
      'avatarUpdatedAt': avatarUpdatedAt!.toUtc().toIso8601String(),
    'devices': [for (final device in devices.values) device.toJson()],
    'revocations': [for (final item in revocations.values) item.toJson()],
  };

  factory AccountSyncState.fromJson(
    Map<String, dynamic> json, {
    bool allowEmptyPassword = false,
  }) {
    final rawDevices = json['devices'];
    final rawRevocations = json['revocations'];
    if (rawDevices is! List || rawRevocations is! List) {
      throw const FormatException('账号同步数据缺少设备或解绑记录。');
    }

    final devices = <String, AccountDevice>{};
    for (final item in rawDevices) {
      if (item is! Map) {
        throw const FormatException('账号设备记录格式无效。');
      }
      final device = AccountDevice.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (devices.containsKey(device.id)) {
        throw const FormatException('账号设备记录包含重复设备。');
      }
      devices[device.id] = device;
    }

    final revocations = <String, DeviceRevocation>{};
    for (final item in rawRevocations) {
      if (item is! Map) {
        throw const FormatException('账号解绑记录格式无效。');
      }
      final revocation = DeviceRevocation.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (revocations.containsKey(revocation.deviceId)) {
        throw const FormatException('账号解绑记录包含重复设备。');
      }
      revocations[revocation.deviceId] = revocation;
    }

    final accountId = json['accountId'];
    final accountName = json['accountName'];
    final password = json['password'];
    if (accountId is! String || accountId.isEmpty) {
      throw const FormatException('账号同步数据缺少账号 ID。');
    }
    if (accountName is! String || accountName.isEmpty) {
      throw const FormatException('账号同步数据缺少账号名。');
    }
    if (password is! String || (!allowEmptyPassword && password.isEmpty)) {
      throw const FormatException('账号同步数据缺少密码。');
    }

    final avatarBase64 = json['avatarBase64'];
    final avatarUpdatedAt = json['avatarUpdatedAt'];
    if (avatarBase64 != null && avatarBase64 is! String) {
      throw const FormatException('账号头像数据格式无效。');
    }
    if (avatarBase64 is String &&
        avatarBase64.isNotEmpty &&
        avatarUpdatedAt == null) {
      throw const FormatException('账号头像缺少更新时间。');
    }

    return AccountSyncState(
      accountId: requireValidAccountId(accountId),
      accountName: accountName,
      password: password,
      accountNameUpdatedAt: _date(json['accountNameUpdatedAt']),
      passwordUpdatedAt: _date(json['passwordUpdatedAt']),
      avatarBase64: avatarBase64 as String?,
      avatarUpdatedAt: avatarUpdatedAt == null ? null : _date(avatarUpdatedAt),
      devices: devices,
      revocations: revocations,
    );
  }

  /// Migrates the profile timestamp used by earlier released account data.
  factory AccountSyncState.fromCompatibleJson(
    Map<String, dynamic> json, {
    bool allowMissingPassword = false,
  }) {
    final normalized = Map<String, dynamic>.from(json);
    normalized['accountNameUpdatedAt'] ??= normalized['profileUpdatedAt'];
    normalized['passwordUpdatedAt'] ??= normalized['profileUpdatedAt'];
    if (allowMissingPassword) normalized['password'] ??= '';
    return AccountSyncState.fromJson(
      normalized,
      // Early local accounts had only a password verifier; keep their identity
      // until the user reactivates them rather than discarding the account.
      allowEmptyPassword: allowMissingPassword,
    );
  }
}

DateTime _date(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const FormatException('账号时间字段格式无效。');
}

bool _preferIncomingProfileValue({
  required String localValue,
  required DateTime localUpdatedAt,
  required String incomingValue,
  required DateTime incomingUpdatedAt,
}) {
  if (incomingUpdatedAt.isAfter(localUpdatedAt)) return true;
  if (incomingUpdatedAt.isBefore(localUpdatedAt)) return false;
  return incomingValue.compareTo(localValue) < 0;
}
