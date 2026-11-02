import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';

class AdventurerNewsStorage {
  const AdventurerNewsStorage();

  static const _fileName = 'adventurer-news-last-seen-build-v1.txt';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<int?> readLastSeen() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = int.tryParse((await file.readAsString()).trim());
    return value != null && value >= 0 ? value : null;
  }

  Future<void> writeLastSeen(int build) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await atomicWriteString(file, build.toString());
  }
}
