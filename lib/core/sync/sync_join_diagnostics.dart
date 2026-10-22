import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SyncJoinDiagnostics {
  SyncJoinDiagnostics._();

  static const String fileName = 'sync-join-diagnostic-v1.jsonl';
  static Future<void> _tail = Future<void>.value();

  static Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
  }

  static String get platform => Platform.isWindows
      ? 'windows'
      : Platform.isAndroid
          ? 'android'
          : Platform.operatingSystem;

  static Future<void> reset({required String role}) {
    return _serialize(() async {
      final file = await _file();
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      await _appendUnlocked(file, 'trace.reset', <String, Object?>{
        'role': role,
      });
    });
  }

  static Future<void> record(
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    return _serialize(() async {
      final file = await _file();
      await _appendUnlocked(file, event, fields);
    });
  }

  static Future<String> readText() async {
    await _tail;
    final file = await _file();
    if (!await file.exists()) {
      return '暂无同步加入诊断记录。';
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return '暂无同步加入诊断记录。';
    }
    return text;
  }

  static Future<void> _appendUnlocked(
    File file,
    String event,
    Map<String, Object?> fields,
  ) async {
    await file.parent.create(recursive: true);
    final entry = <String, Object?>{
      'timeUtc': DateTime.now().toUtc().toIso8601String(),
      'platform': platform,
      'event': event,
      ...fields,
    };
    await file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<void> _serialize(Future<void> Function() action) {
    final next = _tail.then<void>((_) => action());
    _tail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
