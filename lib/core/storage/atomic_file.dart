import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final Map<String, Future<void>> _atomicWriteTails = <String, Future<void>>{};

/// Writes a file without exposing a delete-before-replace window.
///
/// Writes to the same target are serialized in call order. This keeps two
/// callers from deleting or renaming the same `.tmp` file concurrently.
/// Different target files can still be written in parallel.
Future<void> atomicWriteString(File file, String content) {
  final key = file.absolute.path;
  final previous = _atomicWriteTails[key] ?? Future<void>.value();
  final operation = previous.then<void>(
    (_) => _atomicWriteStringUnlocked(file, content),
    onError: (Object _, StackTrace __) =>
        _atomicWriteStringUnlocked(file, content),
  );
  final tail = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  _atomicWriteTails[key] = tail;
  unawaited(
    tail.whenComplete(() {
      if (identical(_atomicWriteTails[key], tail)) {
        _atomicWriteTails.remove(key);
      }
    }),
  );
  return operation;
}

Future<void> _atomicWriteStringUnlocked(File file, String content) async {
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');

  // Clean up old temp file if exists
  if (await temp.exists()) {
    try {
      await temp.delete();
    } catch (_) {
      // Continue even if cleanup fails
    }
  }

  await temp.writeAsString(content, flush: true);

  try {
    if (Platform.isWindows) {
      _replaceWindows(temp, file);
    } else {
      await temp.rename(file.path);
    }
  } catch (_) {
    if (await temp.exists()) {
      try {
        await temp.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

void _replaceWindows(File source, File target) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final moveFileEx = kernel32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('MoveFileExW');
  final sourcePath = source.path.toNativeUtf16();
  final targetPath = target.path.toNativeUtf16();
  try {
    // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH.
    if (moveFileEx(sourcePath, targetPath, 0x1 | 0x8) == 0) {
      throw FileSystemException('Windows 无法替换持久化文件。', target.path);
    }
  } finally {
    malloc.free(sourcePath);
    malloc.free(targetPath);
  }
}
