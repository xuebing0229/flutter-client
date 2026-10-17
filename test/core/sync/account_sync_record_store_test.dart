import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/account/account_models.dart';
import 'package:flutter_app/core/sync/account_sync_record_store.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _TemporaryRecordStore extends SyncRecordStore {
  _TemporaryRecordStore(this.directory);

  final Directory directory;

  @override
  Future<Directory> rootDirectory(String accountId) async => directory;
}

AccountSyncState _state({
  required DateTime now,
  required Map<String, DeviceRevocation> revocations,
}) {
  return AccountSyncState(
    accountId: 'account',
    accountName: 'artist',
    password: '123456',
    accountNameUpdatedAt: now,
    passwordUpdatedAt: now,
    devices: <String, AccountDevice>{
      'device-a': AccountDevice(
        id: 'device-a',
        name: 'A',
        platform: 'windows',
        firstSeenAt: now,
        lastSeenAt: now,
        syncTransportId: 'AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH',
      ),
      'device-b': AccountDevice(
        id: 'device-b',
        name: 'B',
        platform: 'android',
        firstSeenAt: now,
        lastSeenAt: now,
        syncTransportId: 'IIIIIII-JJJJJJJ-KKKKKKK-LLLLLLL-MMMMMMM-NNNNNNN-OOOOOOO-PPPPPPP',
      ),
    },
    revocations: revocations,
  );
}

void main() {
  late Directory temporary;
  late AccountSyncRecordStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'guild-account-sync-records-',
    );
    store = AccountSyncRecordStore(
      recordStore: _TemporaryRecordStore(temporary),
    );
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('normal writer still rejects a revoked writer device', () async {
    final now = DateTime.utc(2026, 10, 17, 12);
    final revokedAt = now.add(const Duration(minutes: 1));
    final state = _state(
      now: now,
      revocations: <String, DeviceRevocation>{
        'device-a': DeviceRevocation(
          deviceId: 'device-a',
          revokedAt: revokedAt,
        ),
      },
    );

    expect(
      () => store.write(
        accountId: 'account',
        deviceId: 'device-a',
        state: state,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('self-unbind publishes the existing revocation tombstone and ack', () async {
    final now = DateTime.utc(2026, 10, 17, 12);
    final revokedAt = now.add(const Duration(minutes: 1));
    final state = _state(
      now: now,
      revocations: <String, DeviceRevocation>{
        'device-a': DeviceRevocation(
          deviceId: 'device-a',
          revokedAt: revokedAt,
        ),
      },
    );

    await store.writeSelfRevocation(
      accountId: 'account',
      deviceId: 'device-a',
      state: state,
    );
    await store.writeRevocationAck(
      accountId: 'account',
      deviceId: 'device-a',
      revokedAt: revokedAt,
    );

    expect(
      await store.hasRevocationAck(
        accountId: 'account',
        deviceId: 'device-a',
        revokedAt: revokedAt,
      ),
      isTrue,
    );

    final merged = await store.readMerged(
      accountId: 'account',
      seed: _state(now: now, revocations: const <String, DeviceRevocation>{}),
    );
    expect(merged, isNotNull);
    expect(merged!.isRevoked('device-a'), isTrue);
    expect(merged.activeDevices.map((device) => device.id), isNot(contains('device-a')));
    expect(merged.activeDevices.map((device) => device.id), contains('device-b'));

    final stateDirectory = Directory('${temporary.path}/account-states');
    final files = await stateDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    final payload = jsonDecode(await files.single.readAsString()) as Map;
    expect(payload['writerDeviceId'], 'device-a');
  });
}
