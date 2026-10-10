import 'dart:io';

import 'package:flutter_app/core/storage/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('guild-atomic-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('overlapping writes to one file are serialized without .tmp races',
      () async {
    final file = File('${temporary.path}/state.json');
    final payloads = <String>[
      for (var index = 0; index < 32; index++)
        '${index.toString().padLeft(2, '0')}:${'x'.padRight(128 * 1024 + index, 'x')}',
    ];

    // This used to race on state.json.tmp: concurrent writers could truncate
    // each other's temporary contents, or rename a temp already moved away.
    await Future.wait(
      payloads.map((payload) => atomicWriteString(file, payload)),
    );
    expect(await file.readAsString(), payloads.last);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('a failed save never blocks a later successful write', () async {
    final destination = Directory('${temporary.path}/state.json');
    await destination.create(recursive: true);
    final file = File(destination.path);

    await expectLater(
      atomicWriteString(file, 'first'),
      throwsA(isA<FileSystemException>()),
    );
    await destination.delete();
    await atomicWriteString(file, 'second');

    expect(await file.readAsString(), 'second');
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}
