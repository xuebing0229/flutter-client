import 'dart:io';

import 'package:flutter_app/core/storage/app_data_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late AppDataPersistence persistence;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('guild-save-read-test-');
    persistence = AppDataPersistence(supportDirectory: temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('missing workspace is new, but existing empty save is corruption', () async {
    const accountId = 'empty-account';
    expect(await persistence.load(accountId: accountId), isNull);

    final saved = File(
      '${temporary.path}/accounts/$accountId/app-data-v1.json',
    );
    await saved.parent.create(recursive: true);
    await saved.writeAsString('', flush: true);

    await expectLater(
      persistence.load(accountId: accountId),
      throwsA(isA<FormatException>()),
    );
    // Never treat the damaged file as a newly created empty workspace or
    // erase it as a side effect of reading.
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsString(), isEmpty);
  });

  test('whitespace-only persisted account is rejected, not recovered', () async {
    const accountId = 'whitespace-account';
    final saved = File(
      '${temporary.path}/accounts/$accountId/app-data-v1.json',
    );
    await saved.parent.create(recursive: true);
    await saved.writeAsString('  \n\t  ', flush: true);

    await expectLater(
      persistence.load(accountId: accountId),
      throwsA(isA<FormatException>()),
    );
    expect(await persistence.discoverRecoverableAccounts(), isEmpty);
    expect(await saved.readAsString(), '  \n\t  ');
  });
}
