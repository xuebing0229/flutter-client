import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/account/account_models.dart';
import '../../../core/storage/atomic_file.dart';
import '../../../core/sync/sync_record_store.dart';

/// A fingerprint is attached to ONE recognized card, not an entire
/// screenshot. Importing only some rows must not hide the other rows later.
String screenshotCardFingerprint({
  required String imageSha256,
  required int cardIndex,
  required bool products,
}) =>
    '${products ? 'products' : 'orders'}|$imageSha256|$cardIndex';

class ScreenshotImportHistory {
  const ScreenshotImportHistory({SyncRecordStore? syncRecordStore})
      : _syncRecordStore = syncRecordStore ?? const SyncRecordStore();

  final SyncRecordStore _syncRecordStore;

  Future<File> _legacyFile(String accountId) async {
    final dir = await getApplicationSupportDirectory();
    final safeId = requireValidAccountId(accountId);
    return File(
      '${dir.path}/accounts/$safeId/screenshot-import-history-v1.json',
    );
  }

  Future<Directory> _syncDirectory(String accountId) async {
    final root = await _syncRecordStore.rootDirectory(accountId);
    return Directory(
      '${root.path}${Platform.pathSeparator}auxiliary'
      '${Platform.pathSeparator}screenshot-import-history-v2',
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
    final bytes = await File(path).readAsBytes();
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
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
}
