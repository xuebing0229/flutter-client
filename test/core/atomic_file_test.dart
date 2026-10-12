import 'dart:io';

import 'package:flutter_app/core/storage/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent writes to the same target are serialized in call order', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-file-test-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/state.json');

    final writes = <Future<void>>[
      for (var index = 0; index < 40; index++)
        atomicWriteString(file, 'value-$index'),
    ];
    await Future.wait(writes);

    expect(await file.readAsString(), 'value-39');
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}