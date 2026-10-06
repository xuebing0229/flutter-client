import 'package:flutter_app/core/account/account_models.dart';
import 'package:flutter_app/core/sync/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

AccountSyncState _state(AccountDevice local, AccountDevice remote) {
  final now = DateTime.utc(2026, 10, 6);
  return AccountSyncState(
    accountId: 'account',
    accountName: 'tester',
    password: 'password',
    accountNameUpdatedAt: now,
    passwordUpdatedAt: now,
    devices: <String, AccountDevice>{
      local.id: local,
      remote.id: remote,
    },
    revocations: const <String, DeviceRevocation>{},
  );
}

AccountDevice _device({
  required String id,
  required int? build,
  required int? protocol,
  required int? minimum,
}) {
  final now = DateTime.utc(2026, 10, 6);
  return AccountDevice(
    id: id,
    name: id,
    platform: id == 'phone' ? 'android' : 'windows',
    firstSeenAt: now,
    lastSeenAt: now,
    appBuild: build,
    syncProtocolVersion: protocol,
    minSyncProtocolVersion: minimum,
  );
}

void main() {
  test('different app builds warn but remain protocol compatible', () {
    final notices = syncDeviceVersionNotices(
      state: _state(
        _device(id: 'phone', build: 87, protocol: 1, minimum: 1),
        _device(id: 'desktop', build: 86, protocol: 1, minimum: 1),
      ),
      currentDeviceId: 'phone',
    );

    expect(notices, hasLength(1));
    expect(notices.single.status, SyncVersionStatus.differentBuild);
  });

  test('non-overlapping protocol ranges are incompatible', () {
    final notices = syncDeviceVersionNotices(
      state: _state(
        _device(id: 'phone', build: 90, protocol: 2, minimum: 2),
        _device(id: 'desktop', build: 87, protocol: 1, minimum: 1),
      ),
      currentDeviceId: 'phone',
    );

    expect(notices, hasLength(1));
    expect(notices.single.status, SyncVersionStatus.incompatible);
  });

  test('legacy devices without protocol metadata get a soft warning', () {
    final notices = syncDeviceVersionNotices(
      state: _state(
        _device(id: 'phone', build: 87, protocol: 1, minimum: 1),
        _device(id: 'desktop', build: null, protocol: null, minimum: null),
      ),
      currentDeviceId: 'phone',
    );

    expect(notices, hasLength(1));
    expect(notices.single.status, SyncVersionStatus.legacyUnknown);
  });

  test('same build and compatible protocol need no warning', () {
    final notices = syncDeviceVersionNotices(
      state: _state(
        _device(id: 'phone', build: 87, protocol: 1, minimum: 1),
        _device(id: 'desktop', build: 87, protocol: 1, minimum: 1),
      ),
      currentDeviceId: 'phone',
    );

    expect(notices, isEmpty);
  });

  test('legacy account device json still decodes without version metadata', () {
    final device = AccountDevice.fromJson(<String, dynamic>{
      'id': 'phone',
      'name': 'phone',
      'platform': 'android',
      'firstSeenAt': '2026-10-06T00:00:00.000Z',
      'lastSeenAt': '2026-10-06T00:00:00.000Z',
    });

    expect(device.appBuild, isNull);
    expect(device.syncProtocolVersion, isNull);
    expect(device.minSyncProtocolVersion, isNull);
  });
}
