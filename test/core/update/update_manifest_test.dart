import 'package:flutter_app/core/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UpdateManifest manifest({required bool published, int build = 20}) {
    return UpdateManifest(
      schema: 1,
      channel: 'beta',
      version: '1.0.0',
      build: build,
      published: published,
      downloadUri: Uri.parse('https://example.invalid/app.apk'),
      notes: '',
    );
  }

  test('only a published higher build is considered an update', () {
    expect(manifest(published: true).isNewerThan(19), isTrue);
    expect(manifest(published: false).isNewerThan(19), isFalse);
    expect(manifest(published: true).isNewerThan(20), isFalse);
  });
}
