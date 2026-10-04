import 'dart:convert';
import 'dart:io';

import '../account/account_models.dart';
import '../storage/atomic_file.dart';
import 'sync_record_store.dart';

class AccountSyncRecordStore {
  AccountSyncRecordStore({SyncRecordStore? recordStore})
    : recordStore = recordStore ?? SyncRecordStore();

  final SyncRecordStore recordStore;

  Future<Directory> _directory(String accountId) async {
    final root = await recordStore.rootDirectory(accountId);
    final directory = Directory('${root.path}/account-states');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _revocationAckDirectory(String accountId) async {
    final root = await recordStore.rootDirectory(accountId);
    final directory = Directory('${root.path}/revocation-acks');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _revocationAckFile(
    String accountId,
    String deviceId,
  ) async {
    final directory = await _revocationAckDirectory(accountId);
    final safeDeviceId = base64Url
        .encode(utf8.encode(deviceId))
        .replaceAll('=', '');
    return File('${directory.path}/$safeDeviceId.json');
  }

  Future<void> writeRevocationAck({
    required String accountId,
    required String deviceId,
    required DateTime revokedAt,
  }) async {
    final file = await _revocationAckFile(accountId, deviceId);
    final payload = jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'deviceId': deviceId,
      'revokedAt': revokedAt.toUtc().toIso8601String(),
      'acknowledgedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await atomicWriteString(file, payload);
  }

  Future<bool> hasRevocationAck({
    required String accountId,
    required String deviceId,
    required DateTime revokedAt,
  }) async {
    final file = await _revocationAckFile(accountId, deviceId);
    if (!await file.exists()) return false;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['schemaVersion'] != 1) return false;
      if (decoded['deviceId'] != deviceId) return false;

      final ackedRevokedAt = decoded['revokedAt'];
      if (ackedRevokedAt is! String) return false;
      final parsed = DateTime.tryParse(ackedRevokedAt);
      if (parsed == null) return false;
      return !parsed.toUtc().isBefore(revokedAt.toUtc());
    } catch (_) {
      return false;
    }
  }

  Future<void> write({
    required String accountId,
    required String deviceId,
    required AccountSyncState state,
  }) async {
    if (state.accountId != accountId) {
      throw const FormatException('账号同步状态与当前账号不一致。');
    }
    if (!state.devices.containsKey(deviceId)) {
      throw const FormatException('当前同步设备不属于这个账号。');
    }
    if (state.isRevoked(deviceId)) {
      throw const FormatException('已解绑设备不能继续写入账号同步状态。');
    }

    final directory = await _directory(accountId);
    final safeDeviceId = base64Url
        .encode(utf8.encode(deviceId))
        .replaceAll('=', '');
    final file = File('${directory.path}/$safeDeviceId.json');
    final payload = jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'writerDeviceId': deviceId,
      'account': state.toJson(),
    });

    if (await file.exists()) {
      try {
        if (await file.readAsString() == payload) {
          return;
        }
      } catch (_) {
        // Rewrite below if the existing state cannot be read cleanly.
      }
    }

    await atomicWriteString(file, payload);
  }

  Future<AccountSyncState?> readMerged({
    required String accountId,
    AccountSyncState? seed,
  }) async {
    final directory = await _directory(accountId);
    final variants = <({String writerDeviceId, AccountSyncState state})>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map || decoded['schemaVersion'] != 1) {
          throw const FormatException('账号同步记录版本无效。');
        }
        final writerDeviceId = decoded['writerDeviceId'];
        final raw = decoded['account'];
        if (writerDeviceId is! String || writerDeviceId.isEmpty) {
          throw const FormatException('账号同步记录缺少写入设备。');
        }
        if (raw is! Map) {
          throw const FormatException('账号同步记录缺少账号数据。');
        }
        final state = AccountSyncState.fromJson(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (state.accountId != accountId) {
          throw const FormatException('账号同步记录属于另一个账号。');
        }
        if (!state.devices.containsKey(writerDeviceId)) {
          throw const FormatException('账号同步记录的写入设备不在账号中。');
        }
        variants.add((writerDeviceId: writerDeviceId, state: state));
      } catch (_) {
        // A Syncthing replacement can be observed between rename steps.
        // The next scan will retry without deleting the source file.
      }
    }

    final baselineRevocations = <String, DeviceRevocation>{
      if (seed != null) ...seed.revocations,
    };

    // A device already known locally as revoked is no longer an authority for
    // account metadata. In particular, its stale file must not be able to add
    // fresh revocations for other devices after it has been unshared.
    final trustedVariants = <({String writerDeviceId, AccountSyncState state})>[
      for (final variant in variants)
        if (!baselineRevocations.containsKey(variant.writerDeviceId)) variant,
    ];

    final revocations = <String, DeviceRevocation>{...baselineRevocations};
    for (final variant in trustedVariants) {
      for (final entry in variant.state.revocations.entries) {
        final current = revocations[entry.key];
        if (current == null ||
            entry.value.revokedAt.isAfter(current.revokedAt)) {
          revocations[entry.key] = entry.value;
        }
      }
    }

    AccountSyncState? merged = seed;
    for (final variant in trustedVariants) {
      if (revocations.containsKey(variant.writerDeviceId)) {
        continue;
      }
      merged = merged == null ? variant.state : merged.merge(variant.state);
    }

    if (merged != null && !_sameRevocations(merged.revocations, revocations)) {
      merged = merged.copyWith(revocations: revocations);
    }
    return merged;
  }
}

bool _sameRevocations(
  Map<String, DeviceRevocation> left,
  Map<String, DeviceRevocation> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null ||
        other.revokedAt.toUtc() != entry.value.revokedAt.toUtc()) {
      return false;
    }
  }
  return true;
}
