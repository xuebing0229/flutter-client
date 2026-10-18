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
  test('legacy same machine alias can be reclaimed by exact name/platform', () {
    final current = _device(
      id: 'new',
      name: 'yyt',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 18),
    );
    final old = _device(
      id: 'old',
      name: 'yyt',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 12),
    );

    expect(
      isLegacySameInstallationCandidate(current: current, candidate: old),
      isTrue,
    );
  });

  test('legacy alias fallback does not merge a different machine shape', () {
    final current = _device(
      id: 'new',
      name: 'yyt',
      platform: 'windows',
      firstSeenAt: DateTime.utc(2026, 10, 18),
    );

    expect(
      isLegacySameInstallationCandidate(
        current: current,
        candidate: _device(
          id: 'other-name',
          name: 'other',
          platform: 'windows',
          firstSeenAt: DateTime.utc(2026, 10, 12),
        ),
      ),
      isFalse,
    );
    expect(
      isLegacySameInstallationCandidate(
        current: current,
        candidate: _device(
          id: 'other-platform',
          name: 'yyt',
          platform: 'android',
          firstSeenAt: DateTime.utc(2026, 10, 12),
        ),
      ),
      isFalse,
    );
    expect(
      isLegacySameInstallationCandidate(
        current: current,
        candidate: _device(
          id: 'already-stable',
          name: 'yyt',
          platform: 'windows',
          firstSeenAt: DateTime.utc(2026, 10, 12),
          installationId: 'installation-identity-123',
        ),
      ),
      isFalse,
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
}
