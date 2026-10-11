import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// A streaming sink for untrusted ZIP entries.
///
/// Some archive decoder paths trust ZIP metadata while writing bytes. This
/// sink counts *actual* bytes sent by the decoder, so a forged uncompressed
/// size cannot exhaust the user's disk before our backup manifest validation.
///
/// No whole-file allocation: the underlying OutputFileStream buffers 256 KiB.
/// This also works for legitimate multi-gigabyte reference images.
class BoundedArchiveFileOutput extends OutputStream {
  BoundedArchiveFileOutput(String path, this.maxBytes)
      : _file = OutputFileStream(path, bufferSize: 256 * 1024),
        super(byteOrder: ByteOrder.littleEndian) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
    }
  }

  final int maxBytes;
  final OutputFileStream _file;

  int _crc32 = 0;
  /// CRC-32 of the bytes actually written, calculated incrementally.
  int get crc32 => _crc32;

  @override
  int get length => _file.length;

  @override
  bool get isOpen => _file.isOpen;

  void _requireCapacity(int count) {
    if (count < 0 || count > maxBytes - length) {
      throw const FormatException(
        '备份文件实际解压大小超过数据清单声明，已终止恢复。',
      );
    }
  }

  @override
  void writeByte(int value) {
    _requireCapacity(1);
    _file.writeByte(value);
    _crc32 = getCrc32([value], _crc32);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count > bytes.length) {
      throw const FormatException('解压数据长度无效。');
    }
    _requireCapacity(count);
    _file.writeBytes(bytes, length: count);
    // Avoid copying the entire reference image. Input is at most one
    // decompression chunk, and the CRC folds into its running 32-bit state.
    _crc32 = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      _crc32,
    );
  }

  @override
  void writeBackReference(int distance, int count) {
    _requireCapacity(count);
    final before = length;
    _file.writeBackReference(distance, count);
    // ZIP/DEFLATE overlap copies must also contribute to the CRC, including
    // when the decoder writes via back-references instead of writeBytes.
    for (var offset = before; offset < length;) {
      final next = offset + 64 * 1024 < length
          ? offset + 64 * 1024
          : length;
      _crc32 = getCrc32(_file.subset(offset, next), _crc32);
      offset = next;
    }
  }

  @override
  void writeStream(InputStream input) {
    const chunkSize = 64 * 1024;
    while (!input.isEOS) {
      // Read at most one byte beyond the allowed limit so a lying ZIP size
      // fails immediately, rather than decompressing a huge overflow chunk.
      final remaining = maxBytes - length;
      final toRead = remaining < chunkSize ? remaining + 1 : chunkSize;
      final next = input.readBytes(toRead).toUint8List();
      if (next.isEmpty) break;
      writeBytes(next);
    }
  }

  @override
  Uint8List subset(int start, [int? end]) => _file.subset(start, end);

  @override
  void flush() => _file.flush();

  @override
  Future<void> close() => _file.close();

  @override
  void closeSync() => _file.closeSync();

  @override
  void clear() => _file.closeSync();
}
