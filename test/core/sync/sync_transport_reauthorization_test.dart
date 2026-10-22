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

  test('reinstall rejoin resets a transport used only by a revoked device', () {
    expect(
      shouldResetRevokedTransportBeforeRejoin(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{},
        revokedTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
      ),
      isTrue,
    );
  });

  test('active transport is never reset during another device rejoin', () {
    expect(
      shouldResetRevokedTransportBeforeRejoin(
        transportId: 'TRANSPORT-DEVICE-ID',
        activeTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
        revokedTransportIds: const <String>{'TRANSPORT-DEVICE-ID'},
      ),
      isFalse,
    );
  });

  test('unrelated fresh transport does not trigger stale-device cleanup', () {
    expect(
      shouldResetRevokedTransportBeforeRejoin(
        transportId: 'NEW-TRANSPORT-ID',
        activeTransportIds: const <String>{},
        revokedTransportIds: const <String>{'OLD-TRANSPORT-ID'},
      ),
      isFalse,
    );
  });
}
