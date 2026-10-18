import 'package:flutter_app/core/account/account_models.dart';
import 'package:flutter_app/core/account/account_store.dart';
import 'package:flutter_test/flutter_test.dart';

AccountDevice _device({
  required String id,
  required String name,
  required String platform,
  required DateTime firstSeenAt,
  String? installationId,
}) {
  return AccountDevice(
    id: id,
    name: name,
    platform: platform,
    firstSeenAt: firstSeenAt,
    lastSeenAt: firstSeenAt,
    installationId: installationId,
  );
}

void main() {
  test('same name and platform are not enough to identify one device', () {
    final other = _device(
      id: 'old',
      name: 'yyt',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 12),
    );

    expect(
      isSameDeviceIdentityForAutomaticDedupe(
        installationId: 'new-installation-identity',
        syncTransportId: 'NEW-TRANSPORT-IDENTITY-1234567890',
        candidate: other,
      ),
      isFalse,
    );
  });

  test('exact installation or transport identity can dedupe', () {
    final byInstallation = _device(
      id: 'installation',
      name: 'other-name',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 12),
      installationId: 'same-installation-identity',
    );
    expect(
      isSameDeviceIdentityForAutomaticDedupe(
        installationId: 'same-installation-identity',
        syncTransportId: 'NEW-TRANSPORT-IDENTITY-1234567890',
        candidate: byInstallation,
      ),
      isTrue,
    );

    final byTransport = AccountDevice(
      id: 'transport',
      name: 'other-name',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 12),
      lastSeenAt: DateTime.utc(2026, 10, 12),
      syncTransportId: 'SAME-TRANSPORT-IDENTITY-1234567890',
    );
    expect(
      isSameDeviceIdentityForAutomaticDedupe(
        installationId: 'new-installation-identity',
        syncTransportId: 'SAME-TRANSPORT-IDENTITY-1234567890',
        candidate: byTransport,
      ),
      isTrue,
    );
  });

  test('installation identity survives device json round trip', () {
    final source = _device(
      id: 'device',
      name: 'yyt',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 18),
      installationId: 'installation-identity-123',
    );
    final decoded = AccountDevice.fromJson(source.toJson());

    expect(decoded.installationId, 'installation-identity-123');
  });
  test('newer transport binding can migrate under the same installation id', () {
    final oldTime = DateTime.utc(2026, 10, 12);
    final newTime = DateTime.utc(2026, 10, 18);
    final local = AccountSyncState(
      accountId: 'account',
      accountName: 'artist',
      password: '123456',
      accountNameUpdatedAt: oldTime,
      passwordUpdatedAt: oldTime,
      devices: <String, AccountDevice>{
        'device': AccountDevice(
          id: 'device',
          name: 'yyt',
          platform: 'windows',
          firstSeenAt: oldTime,
          lastSeenAt: oldTime,
          syncTransportId: 'OLD-TRANSPORT-IDENTITY-1234567890',
        ),
      },
      revocations: const <String, DeviceRevocation>{},
    );
    final incoming = AccountSyncState(
      accountId: 'account',
      accountName: 'artist',
      password: '123456',
      accountNameUpdatedAt: oldTime,
      passwordUpdatedAt: oldTime,
      devices: <String, AccountDevice>{
        'device': AccountDevice(
          id: 'device',
          name: 'yyt',
          platform: 'windows',
          firstSeenAt: oldTime,
          lastSeenAt: newTime,
          syncTransportId: 'NEW-TRANSPORT-IDENTITY-1234567890',
          installationId: 'installation-identity-123',
        ),
      },
      revocations: const <String, DeviceRevocation>{},
    );

    final merged = local.merge(incoming);
    expect(
      merged.devices['device']!.syncTransportId,
      'NEW-TRANSPORT-IDENTITY-1234567890',
    );
    expect(
      merged.devices['device']!.installationId,
      'installation-identity-123',
    );
  });

}
