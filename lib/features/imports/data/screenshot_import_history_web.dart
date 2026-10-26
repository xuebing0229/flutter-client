import 'dart:convert';

import '../../../core/web/web_platform_bridge.dart';

import 'package:cryptography/cryptography.dart';

import 'web_screenshot_files.dart';

String screenshotCardFingerprint({
  required String imageSha256,
  required int cardIndex,
  required bool products,
}) =>
    '${products ? 'products' : 'orders'}|$imageSha256|$cardIndex';

class ScreenshotImportHistory {
  const ScreenshotImportHistory();

  String _key(String accountId) =>
      'adventurers-guild.web.ocr-history.v1.$accountId';

  Future<String> hashImage(String token) async {
    final hash = await Sha256().hash(WebScreenshotFiles.bytes(token));
    return hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Set<String>> read({required String accountId}) async {
    final source = webStorageGet(_key(accountId));
    if (source == null || source.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().where((item) => item.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> replaceAll({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    final values = fingerprints.where((item) => item.isNotEmpty).toSet().toList()
      ..sort();
    webStorageSet(_key(accountId), jsonEncode(values));
  }

  Future<void> markImported({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    final current = await read(accountId: accountId);
    current.addAll(fingerprints.where((item) => item.isNotEmpty));
    await replaceAll(accountId: accountId, fingerprints: current);
  }
}
