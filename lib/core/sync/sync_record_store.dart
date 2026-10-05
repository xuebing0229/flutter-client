import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../account/account_models.dart';
import '../storage/atomic_file.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';

class SyncRecordStore {
  SyncRecordStore({SyncMergeEngine? mergeEngine})
    : _engine = mergeEngine ?? SyncMergeEngine();

  final SyncMergeEngine _engine;

  Future<Directory> rootDirectory(String accountId) async {
    final support = await getApplicationSupportDirectory();
    final safeAccountId = requireValidAccountId(accountId);
    final accountDirectory = Directory(
      '${support.path}/accounts/$safeAccountId',
    );
    await accountDirectory.create(recursive: true);
    await _recoverDirectorySwap(accountDirectory);
    final directory = Directory('${accountDirectory.path}/sync-v1');
    await directory.create(recursive: true);

    final ignoreFile = File('${directory.path}/.stignore');
    if (!await ignoreFile.exists()) {
      await ignoreFile.writeAsString('(?d)**/*.tmp\n', flush: true);
    }

    return directory;
  }

  Future<void> _recoverDirectorySwap(Directory accountDirectory) async {
    final target = Directory('${accountDirectory.path}/sync-v1');
    final staging = <Directory>[];
    final previous = <Directory>[];
    await for (final entity in accountDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('sync-v1.import-')) staging.add(entity);
      if (name.startsWith('sync-v1.previous-')) previous.add(entity);
    }
    previous.sort((a, b) => a.path.compareTo(b.path));
    if (!await target.exists() && previous.isNotEmpty) {
      // A staging import may still be incomplete. Roll back to the last
      // complete directory if the app stopped between the two renames.
      await previous.last.rename(target.path);
    }

    if (await target.exists()) {
      for (final directory in [...staging, ...previous]) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } catch (_) {
          // Syncthing can briefly retain a directory handle on Windows.
        }
      }
    }
  }

  Future<String> rootPath(String accountId) async {
    return (await rootDirectory(accountId)).path;
  }

  Future<Directory> _entityDirectory(
    String accountId,
    SyncEntityKind kind,
  ) async {
    final root = await rootDirectory(accountId);
    final directory = Directory('${root.path}/${kind.directoryName}');
    await directory.create(recursive: true);
    return directory;
  }

  Future<SyncRecord?> readMergedRecord({
    required String accountId,
    required SyncEntityKind kind,
    required String recordId,
  }) async {
    final groups = await _readGroups(accountId, kind);
    final variants = groups[recordId];
    if (variants == null || variants.isEmpty) return null;
    return _mergeAndCanonicalize(
      accountId: accountId,
      kind: kind,
      recordId: recordId,
      variants: variants,
    );
  }

  Future<Map<String, SyncRecord>> readAllMerged({
    required String accountId,
    required SyncEntityKind kind,
  }) async {
    final groups = await _readGroups(accountId, kind);
    final records = <String, SyncRecord>{};

    for (final entry in groups.entries) {
      final record = await _mergeAndCanonicalize(
        accountId: accountId,
        kind: kind,
        recordId: entry.key,
        variants: entry.value,
      );
      if (record != null) records[entry.key] = record;
    }

    return records;
  }

  Future<void> write({
    required String accountId,
    required SyncRecord record,
  }) async {
    requireValidAccountId(accountId);
    if (record.accountId != null && record.accountId != accountId) {
      throw const FormatException('同步记录属于另一个账号，已拒绝写入。');
    }
    if (!_recordIdentityMatches(record)) {
      throw const FormatException('同步记录 ID 与内容身份不一致。');
    }

    final bound = record.copyWith(accountId: accountId);
    final file = await _canonicalFile(accountId, bound.kind, bound.id);
    await _atomicWrite(file, bound.encode());
  }

  Future<List<Map<String, dynamic>>> exportPortableRecords({
    required String accountId,
  }) async {
    requireValidAccountId(accountId);
    final result = <Map<String, dynamic>>[];

    for (final kind in SyncEntityKind.values) {
      final records = await readAllMerged(accountId: accountId, kind: kind);
      final ids = records.keys.toList()..sort();
      for (final id in ids) {
        result.add(Map<String, dynamic>.from(records[id]!.toJson()));
      }
    }

    return result;
  }

  void validatePortableRecords({
    required String accountId,
    required Iterable<Map<String, dynamic>> records,
    Map<SyncEntityKind, Set<String>> requiredIds =
        const <SyncEntityKind, Set<String>>{},
  }) {
    _decodePortableRecords(
      accountId: accountId,
      records: records,
      requiredIds: requiredIds,
    );
  }

  Future<void> replacePortableRecords({
    required String accountId,
    required Iterable<Map<String, dynamic>> records,
    Map<SyncEntityKind, Set<String>> requiredIds =
        const <SyncEntityKind, Set<String>>{},
  }) async {
    final safeAccountId = requireValidAccountId(accountId);
    final decoded = _decodePortableRecords(
      accountId: safeAccountId,
      records: records,
      requiredIds: requiredIds,
    );

    final support = await getApplicationSupportDirectory();
    final accountDirectory = Directory(
      '${support.path}/accounts/$safeAccountId',
    );
    await accountDirectory.create(recursive: true);

    final target = Directory('${accountDirectory.path}/sync-v1');
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final staging = Directory(
      '${accountDirectory.path}/sync-v1.import-$suffix',
    );
    final previous = Directory(
      '${accountDirectory.path}/sync-v1.previous-$suffix',
    );

    await staging.create(recursive: true);
    await File(
      '${staging.path}/.stignore',
    ).writeAsString('(?d)**/*.tmp\n', flush: true);
    // Preserve Syncthing's folder marker when an already-running transport is
    // watching this account path.
    await Directory('${staging.path}/.stfolder').create(recursive: true);

    try {
      for (final record in decoded) {
        final directory = Directory(
          '${staging.path}/${record.kind.directoryName}',
        );
        await directory.create(recursive: true);
        final encoded = base64Url
            .encode(utf8.encode(record.id))
            .replaceAll('=', '');
        final file = File('${directory.path}/$encoded.json');
        await file.writeAsString(record.encode(), flush: true);
      }

      var movedPrevious = false;
      if (await target.exists()) {
        await target.rename(previous.path);
        movedPrevious = true;
      }

      try {
        if (movedPrevious) {
          // Portable entity history intentionally does not contain account
          // metadata variants. Keep those files across a workspace-history
          // restore so importing a backup cannot erase newer device/profile
          // or revocation state learned from other peers.
          final previousAccountStates = Directory(
            '${previous.path}/account-states',
          );
          if (await previousAccountStates.exists()) {
            await _copyDirectory(
              previousAccountStates,
              Directory('${staging.path}/account-states'),
            );
          }
          final previousRevocationAcks = Directory(
            '${previous.path}/revocation-acks',
          );
          if (await previousRevocationAcks.exists()) {
            await _copyDirectory(
              previousRevocationAcks,
              Directory('${staging.path}/revocation-acks'),
            );
          }
        }

        await staging.rename(target.path);
      } catch (_) {
        if (movedPrevious &&
            await previous.exists() &&
            !await target.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }

      if (await previous.exists()) {
        try {
          await previous.delete(recursive: true);
        } catch (_) {
          // The old directory is outside the configured sync root. A process
          // can briefly retain a handle on Windows; leaving it is harmless.
        }
      }
    } catch (_) {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  List<SyncRecord> _decodePortableRecords({
    required String accountId,
    required Iterable<Map<String, dynamic>> records,
    required Map<SyncEntityKind, Set<String>> requiredIds,
  }) {
    requireValidAccountId(accountId);
    final decoded = <SyncRecord>[];
    final identities = <String>{};
    final idsByKind = <SyncEntityKind, Set<String>>{
      for (final kind in SyncEntityKind.values) kind: <String>{},
    };

    for (final raw in records) {
      final record = SyncRecord.decode(jsonEncode(raw));
      if (record.accountId != accountId) {
        throw const FormatException('同步历史属于另一个账号，已拒绝导入。');
      }
      if (!_recordIdentityMatches(record)) {
        throw const FormatException('同步历史 ID 与内容身份不一致。');
      }

      final identity = '${record.kind.name}\u0000${record.id}';
      if (!identities.add(identity)) {
        throw FormatException('同步历史存在重复记录：${record.kind.name}/${record.id}');
      }

      decoded.add(record);
      idsByKind[record.kind]!.add(record.id);
    }

    for (final entry in requiredIds.entries) {
      final present = idsByKind[entry.key] ?? const <String>{};
      final missing = entry.value.difference(present);
      if (missing.isNotEmpty) {
        throw FormatException(
          '同步历史不完整：${entry.key.name} 缺少 '
          '${missing.take(3).join(', ')}'
          '${missing.length > 3 ? ' 等 ${missing.length} 条' : ''}',
        );
      }
    }

    return decoded;
  }

  Future<Map<String, List<_RecordVariant>>> _readGroups(
    String accountId,
    SyncEntityKind kind,
  ) async {
    final directory = await _entityDirectory(accountId, kind);
    final groups = <String, List<_RecordVariant>>{};

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;

      try {
        final source = await entity.readAsString();
        if (source.trim().isEmpty) continue;
        var record = SyncRecord.decode(source);
        if (record.kind != kind) continue;
        if (record.accountId != null && record.accountId != accountId) {
          continue;
        }
        record = record.copyWith(accountId: accountId);
        if (!_recordIdentityMatches(record)) continue;

        groups
            .putIfAbsent(record.id, () => <_RecordVariant>[])
            .add(_RecordVariant(file: entity, record: record));
      } catch (_) {
        // A file can be observed while Syncthing is replacing it.
        // Leave it untouched and retry during the next scan.
      }
    }

    return groups;
  }

  Future<SyncRecord?> _mergeAndCanonicalize({
    required String accountId,
    required SyncEntityKind kind,
    required String recordId,
    required List<_RecordVariant> variants,
  }) async {
    if (variants.isEmpty) return null;

    var merged = variants.first.record;
    for (final variant in variants.skip(1)) {
      merged = _engine.merge(merged, variant.record);
    }

    final canonical = await _canonicalFile(accountId, kind, recordId);
    final canonicalVariant = await _findCanonicalVariant(variants, canonical);
    final needsWrite =
        variants.length > 1 ||
        !await canonical.exists() ||
        canonicalVariant == null ||
        !syncJsonEquals(canonicalVariant.record.toJson(), merged.toJson());

    if (needsWrite) {
      await _atomicWrite(canonical, merged.encode());
    }

    for (final variant in variants) {
      // Directory enumeration on Windows can return the same file with a
      // different slash style (for example, '/' versus '\\'). Comparing raw
      // path strings would mistake the canonical file for a Syncthing conflict
      // variant and delete the record we just merged.
      if (await _sameFile(variant.file, canonical)) continue;
      try {
        if (await variant.file.exists()) await variant.file.delete();
      } catch (_) {
        // Syncthing can still hold a handle briefly. Next scan will retry.
      }
    }

    return merged;
  }

  Future<_RecordVariant?> _findCanonicalVariant(
    List<_RecordVariant> variants,
    File canonical,
  ) async {
    for (final variant in variants) {
      if (await _sameFile(variant.file, canonical)) return variant;
    }
    return null;
  }

  Future<bool> _sameFile(File left, File right) async {
    if (left.path == right.path) return true;
    try {
      return await FileSystemEntity.identical(left.path, right.path);
    } on FileSystemException {
      return false;
    }
  }

  Future<File> _canonicalFile(
    String accountId,
    SyncEntityKind kind,
    String recordId,
  ) async {
    final directory = await _entityDirectory(accountId, kind);
    final encoded = base64Url.encode(utf8.encode(recordId)).replaceAll('=', '');
    return File('${directory.path}/$encoded.json');
  }

  bool _recordIdentityMatches(SyncRecord record) {
    final embeddedId = record.fields['id']?.value;
    return embeddedId is String && embeddedId == record.id;
  }

  Future<void> _atomicWrite(File file, String content) async {
    await atomicWriteString(file, content);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (entity is File) {
        await entity.copy('${destination.path}/$name');
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory('${destination.path}/$name'));
      }
    }
  }
}

class _RecordVariant {
  const _RecordVariant({required this.file, required this.record});

  final File file;
  final SyncRecord record;
}
