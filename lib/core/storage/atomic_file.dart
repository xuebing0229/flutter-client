import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Writes a file without exposing a delete-before-replace window.
///
/// POSIX rename replaces the destination atomically. Windows needs the native
/// replace flag because Dart's File.rename cannot replace an existing file.
// All writers of the same target must share one queue. Without it two
// overlapping saves would delete or overwrite each other's fixed .tmp file,
// potentially corrupting the final sync record or throwing during rename.
// Independent files still write concurrently; the entry is removed on settle.
final Map<String, Future<void>> _atomicWriteTails = <String, Future<void>>{};

Future<void> atomicWriteString(File file, String content) {
  final key = file.absolute.path;
  final previous = _atomicWriteTails[key] ?? Future<void>.value();
  final operation = previous.then<void>((_) => _writeAtomicFile(file, content));
  // A failed write must report its error to its caller, but must not prevent
  // the next queued write from repairing the same destination.
  final tail = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  _atomicWriteTails[key] = tail;
  unawaited(tail.whenComplete(() {
    if (identical(_atomicWriteTails[key], tail)) {
      _atomicWriteTails.remove(key);
    }
  }));
  return operation;
}

Future<void> _writeAtomicFile(File file, String content) async {
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
