import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/account/account_models.dart';
import '../../../core/storage/atomic_file.dart';
import '../../../core/sync/embedded_syncthing_bridge.dart';
import '../../../core/sync/sync_record_store.dart';
import 'screenshot_import_history_common.dart';

class ScreenshotImportHistory {
  const ScreenshotImportHistory({
    SyncRecordStore? syncRecordStore,
    this.syncBridge = const EmbeddedSyncthingBridge(),
  }) : _syncRecordStore = syncRecordStore;

  final SyncRecordStore? _syncRecordStore;
  final EmbeddedSyncthingBridge syncBridge;

  SyncRecordStore get _store => _syncRecordStore ?? SyncRecordStore();

  Future<File> _legacyFile(String accountId) async {
    final dir = await getApplicationSupportDirectory();
    final safeId = requireValidAccountId(accountId);
    return File(
      '${dir.path}/accounts/$safeId/screenshot-import-history-v1.json',
    );
  }

  Future<Directory> _syncDirectory(String accountId) async {
    final root = await _store.rootDirectory(accountId);
    return Directory(
      '${root.path}${Platform.pathSeparator}auxiliary'
      '${Platform.pathSeparator}screenshot-import-history-v2',
    );
  }

  Future<Directory> _priceMemoryDirectory(String accountId) async {
    final root = await _store.rootDirectory(accountId);
    return Directory(
      '${root.path}${Platform.pathSeparator}auxiliary'
      '${Platform.pathSeparator}screenshot-import-price-memory-v1',
    );
  }

  String _markerName(String fingerprint) =>
      base64Url.encode(utf8.encode(fingerprint)).replaceAll('=', '');

  Future<void> _writeMarkers({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    final values = fingerprints.where((key) => key.isNotEmpty).toSet();
    if (values.isEmpty) return;
    final directory = await _syncDirectory(accountId);
    await directory.create(recursive: true);
    var wrote = false;
    for (final fingerprint in values) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${_markerName(fingerprint)}.json',
      );
      if (await file.exists()) continue;
      await atomicWriteString(
        file,
        jsonEncode(<String, dynamic>{'fingerprint': fingerprint}),
      );
      wrote = true;
    }
    if (wrote) {
      try {
        await syncBridge.requestScan(accountId: accountId);
      } catch (_) {
        // Marker files remain in the shared folder for the next normal scan.
      }
    }
  }

  Future<Set<String>> _readSynced(String accountId) async {
    final directory = await _syncDirectory(accountId);
    if (!await directory.exists()) return <String>{};
    final result = <String>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is Map && raw['fingerprint'] is String) {
          final fingerprint = (raw['fingerprint'] as String).trim();
          if (fingerprint.isNotEmpty) result.add(fingerprint);
        }
      } catch (_) {
        // One malformed marker must not hide the rest of the import history.
      }
    }
    return result;
  }

  Future<Set<String>> _readLegacy(String accountId) async {
    final file = await _legacyFile(accountId);
    if (!await file.exists()) return <String>{};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <String>{};
      return raw.whereType<String>().where((key) => key.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<String> hashImage(String path) async {
    return hashScreenshotBytes(await File(path).readAsBytes());
  }

  Future<Set<String>> read({required String accountId}) async {
    final synced = await _readSynced(accountId);
    final legacy = await _readLegacy(accountId);
    if (legacy.isNotEmpty) {
      synced.addAll(legacy);
      await _writeMarkers(accountId: accountId, fingerprints: legacy);
      try {
        final file = await _legacyFile(accountId);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Migration already succeeded in the shared workspace. A stale local
        // copy is harmless and will be retried next time.
      }
    }
    return synced;
  }

  Future<void> replaceAll({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    final values = fingerprints.where((key) => key.isNotEmpty).toSet();
    final directory = await _syncDirectory(accountId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await _writeMarkers(accountId: accountId, fingerprints: values);
    try {
      final legacy = await _legacyFile(accountId);
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {}
  }

  Future<void> markImported({
    required String accountId,
    required Iterable<String> fingerprints,
  }) async {
    await _writeMarkers(
      accountId: accountId,
      fingerprints: fingerprints,
    );
  }

  Future<Map<String, double>> readPriceMemory({
    required String accountId,
  }) async {
    final directory = await _priceMemoryDirectory(accountId);
    if (!await directory.exists()) return <String, double>{};

    final values = <String, ({double price, int updatedAt})>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is! Map ||
            raw['key'] is! String ||
            raw['price'] is! num ||
            raw['updatedAt'] is! int) {
          continue;
        }
        final key = (raw['key'] as String).trim();
        final price = (raw['price'] as num).toDouble();
        final updatedAt = raw['updatedAt'] as int;
        if (key.isEmpty || !price.isFinite || price < 0) continue;
        final previous = values[key];
        if (previous == null || updatedAt >= previous.updatedAt) {
          values[key] = (price: price, updatedAt: updatedAt);
        }
      } catch (_) {
        // One damaged or conflicted entry must not hide the rest.
      }
    }
    return <String, double>{
      for (final entry in values.entries) entry.key: entry.value.price,
    };
  }

  Future<void> rememberPrices({
    required String accountId,
    required Map<String, double> prices,
  }) async {
    final valid = <String, double>{
      for (final entry in prices.entries)
        if (entry.key.trim().isNotEmpty &&
            entry.value.isFinite &&
            entry.value >= 0)
          entry.key.trim(): entry.value,
    };
    if (valid.isEmpty) return;

    final directory = await _priceMemoryDirectory(accountId);
    await directory.create(recursive: true);
    final updatedAt = DateTime.now().microsecondsSinceEpoch;
    for (final entry in valid.entries) {
      final name = base64Url
          .encode(utf8.encode(entry.key))
          .replaceAll('=', '');
      await atomicWriteString(
        File(
          '${directory.path}${Platform.pathSeparator}$name.json',
        ),
        jsonEncode(<String, dynamic>{
          'key': entry.key,
          'price': entry.value,
          'updatedAt': updatedAt,
        }),
      );
    }
    try {
      await syncBridge.requestScan(accountId: accountId);
    } catch (_) {
      // The shared file is already durable and will sync on the next scan.
    }
  }
}
