import 'package:flutter_app/core/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit bootstrap reauthorization protects a rejoined transport', () {
    expect(
      shouldRetainRevokedTransportShare(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{},
        reauthorizedTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
      ),
      isTrue,
    );
  });

  test('active app-device binding protects its transport share', () {
    expect(
      shouldRetainRevokedTransportShare(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
        reauthorizedTransportIds: const <String>{},
      ),
      isTrue,
    );
  });

  test('stale revoked transport is still removable without authorization', () {
    expect(
      shouldRetainRevokedTransportShare(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{},
        reauthorizedTransportIds: const <String>{},
      ),
      isFalse,
    );
  });

  test('reinstall may reset only a stale revoked transport before bootstrap', () {
    expect(
      shouldResetStaleRevokedTransportBeforeBootstrap(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{},
        revokedTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
      ),
      isTrue,
    );
  });

  test('normal first join never resets a transport', () {
    expect(
      shouldResetStaleRevokedTransportBeforeBootstrap(
        transportId: 'NEW-TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{},
        revokedTransportIds: const <String>{'OLD-TRANSPORT-DEVICE-ID'},
      ),
      isFalse,
    );
  });

  test('active transport is never treated as stale revoked rejoin', () {
    expect(
      shouldResetStaleRevokedTransportBeforeBootstrap(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
        revokedTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
      ),
      isFalse,
    );
  });
}
