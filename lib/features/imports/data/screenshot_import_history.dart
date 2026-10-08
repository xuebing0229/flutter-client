import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/account/account_models.dart';
import '../../core/storage/atomic_file.dart';

/// A fingerprint is attached to ONE recognized card, not an entire
/// screenshot. Importing only some rows must not hide the other rows later.
String screenshotCardFingerprint({
  required String imageSha256,
  required int cardIndex,
  required bool products,
}) =>
    '${products ? 'products' : 'orders'}|$imageSha256|$cardIndex';

class ScreenshotImportHistory {
  const ScreenshotImportHistory();

  Future<File> _file(String accountId) async {
    final dir = await getApplicationSupportDirectory();
    final safeId = requireValidAccountId(accountId);
    return File('${dir.path}/accounts/$safeId/screenshot-import-history-v1.json');
  }

  Future<String> hashImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Set<String>> read({required String accountId}) async {
    final file = await _file(accountId);
    if (!await file.exists()) return <String>{};
    final raw = jsonDecode(await file.readAsString());
    if (raw is! List) throw const FormatException('截图导入记录格式错误');
    return raw.whereType<String>().toSet();
  }

  Future<void> markImported({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    final keys = fingerprints.where((key) => key.isNotEmpty).toSet();
    if (keys.isEmpty) return;
    final existing = await read(accountId: accountId);
    existing.addAll(keys);
    final file = await _file(accountId);
    await atomicWriteString(file, jsonEncode(existing.toList()..sort()));
  }
}
