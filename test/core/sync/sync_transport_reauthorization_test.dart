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
}
