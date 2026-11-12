import 'dart:convert';

import '../../../core/web/web_platform_bridge.dart';

import 'web_screenshot_files.dart';
import 'screenshot_import_history_common.dart';

class ScreenshotImportHistory {
  const ScreenshotImportHistory();

  String _key(String accountId) =>
      'adventurers-guild.web.ocr-history.v1.$accountId';

  String _priceKey(String accountId) =>
      'adventurers-guild.web.ocr-price-memory.v1.$accountId';

  Future<String> hashImage(String token) async {
    return hashScreenshotBytes(WebScreenshotFiles.bytes(token));
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
    await replaceAll(
      accountId: accountId,
      fingerprints: mergeScreenshotImportFingerprints(current, fingerprints),
    );
  }

  Future<Map<String, double>> readPriceMemory({
    required String accountId,
  }) async {
    final source = webStorageGet(_priceKey(accountId));
    if (source == null || source.trim().isEmpty) return <String, double>{};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return <String, double>{};
      final values = <String, double>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! num) continue;
        final key = (entry.key as String).trim();
        final price = (entry.value as num).toDouble();
        if (key.isNotEmpty && price.isFinite && price >= 0) {
          values[key] = price;
        }
      }
      return values;
    } catch (_) {
      return <String, double>{};
    }
  }

  Future<void> rememberPrices({
    required String accountId,
    required Map<String, double> prices,
  }) async {
    if (prices.isEmpty) return;
    final current = await readPriceMemory(accountId: accountId);
    for (final entry in prices.entries) {
      final key = entry.key.trim();
      final price = entry.value;
      if (key.isNotEmpty && price.isFinite && price >= 0) {
        current[key] = price;
      }
    }
    webStorageSet(_priceKey(accountId), jsonEncode(current));
  }
}
