import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Writes a file without exposing a delete-before-replace window.
///
/// POSIX rename replaces the destination atomically. Windows needs the native
/// replace flag because Dart's File.rename cannot replace an existing file.
Future<void> atomicWriteString(File file, String content) async {
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
