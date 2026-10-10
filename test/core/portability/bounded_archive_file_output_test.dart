import 'dart:io';

import 'package:archive/archive_io.dart';

import 'package:flutter_app/core/portability/bounded_archive_file_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('guild-bounded-zip-');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('allows exact expected image bytes without an arbitrary global cap', () async {
    final path = '${temp.path}/reference.bin';
    final output = BoundedArchiveFileOutput(path, 4);
    try {
      output.writeByte(1);
      output.writeBytes([2, 3, 4]);
      expect(output.length, 4);
    } finally {
      await output.close();
    }
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    // Corruption with the same byte length must still be detected.
    expect(output.crc32, getCrc32([1, 2, 3, 4]));
  });

  test('rejects decoder writing one byte beyond the metadata budget', () async {
    final path = '${temp.path}/overflow.bin';
    final output = BoundedArchiveFileOutput(path, 3);
    try {
      output.writeBytes([1, 2, 3]);
      expect(
        () => output.writeByte(4),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => output.writeBytes([4, 5]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => output.writeBackReference(1, 2),
        throwsA(isA<FormatException>()),
      );
      expect(output.length, 3);
    } finally {
      await output.close();
    }
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('CRC includes output generated from decompression back-references', () async {
    final path = '${temp.path}/backreference.bin';
    final output = BoundedArchiveFileOutput(path, 7);
    try {
      output.writeBytes([1, 2, 3, 4]);
      output.writeBackReference(3, 3);
      expect(output.length, 7);
    } finally {
      await output.close();
    }
    final bytes = await File(path).readAsBytes();
    expect(bytes, [1, 2, 3, 4, 2, 3, 4]);
    expect(output.crc32, getCrc32(bytes));
  });

  test('rejects an empty declared resource when bytes are actually emitted', () async {
    final output = BoundedArchiveFileOutput('${temp.path}/empty.bin', 0);
    try {
      expect(() => output.writeByte(1), throwsA(isA<FormatException>()));
      expect(output.length, 0);
    } finally {
      await output.close();
    }
  });
}
