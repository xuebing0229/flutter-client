import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/sync/sync_merge_engine.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

const accountId = 'sync-test-account';

class _TemporaryRecordStore extends SyncRecordStore {
  _TemporaryRecordStore(this.directory);

  final Directory directory;

  @override
  Future<Directory> rootDirectory(String accountId) async => directory;
}

File _recordFile(Directory root, SyncEntityKind kind, String id) {
  final name = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
  return File('${root.path}/${kind.directoryName}/$name.json');
}

void main() {
  late Directory temporary;
  late SyncRecordStore store;
  late SyncMergeEngine engine;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('guild-sync-records-');
    store = _TemporaryRecordStore(temporary);
    engine = SyncMergeEngine();
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  for (final kind in SyncEntityKind.values) {
    test('${kind.name} canonical record survives repeated reads', () async {
      final record = SyncRecord.bootstrap(
        kind: kind,
        id: 'app',
        values: <String, dynamic>{'id': 'app', 'title': 'test'},
        deviceId: 'phone',
      );
      await store.write(accountId: accountId, record: record);

      for (var read = 0; read < 3; read++) {
        final records = await store.readAllMerged(
          accountId: accountId,
          kind: kind,
        );
        expect(records.keys, contains('app'));
        expect(await _recordFile(temporary, kind, 'app').exists(), isTrue);
      }
    });
  }

  test('concurrent themes keep their conflict and only delete the variant', () async {
    const values = <String, dynamic>{
      'id': 'app',
      'themeMode': 'system',
      'themePaletteId': 'guild',
    };
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: values,
      deviceId: 'phone',
    );
    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'themePaletteId': 'tavern'},
      deviceId: 'phone',
    );
    final desktop = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: values,
      nextValues: <String, dynamic>{...values, 'themePaletteId': 'blue'},
      deviceId: 'desktop',
    );
    await store.write(accountId: accountId, record: phone);
    final canonical = _recordFile(temporary, SyncEntityKind.settings, 'app');
    final variant = File('${canonical.parent.path}/YXBw.sync-conflict-desktop.json');
    await variant.writeAsString(desktop.copyWith(accountId: accountId).encode());

    final merged = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.settings,
      recordId: 'app',
    );
    expect(merged, isNotNull);
    expect(merged!.conflicts.values.single.field, 'themePaletteId');
    expect(await canonical.exists(), isTrue);
    expect(await variant.exists(), isFalse);
    final reread = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.settings,
      recordId: 'app',
    );
    expect(reread!.toJson(), merged.toJson());
  });

  test('targeted local edit merges conflict variants without reading unrelated records', () async {
    final baseline = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'chosen-order',
      values: const <String, dynamic>{
        'id': 'chosen-order',
        'title': '原始',
        'price': 120,
      },
      deviceId: 'phone',
    );
    final phone = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: const <String, dynamic>{
        'id': 'chosen-order',
        'title': '原始',
        'price': 120,
      },
      nextValues: const <String, dynamic>{
        'id': 'chosen-order',
        'title': '手机编辑',
        'price': 120,
      },
      deviceId: 'phone',
    );
    final pc = engine.applyLocalSnapshot(
      record: baseline,
      previousValues: const <String, dynamic>{
        'id': 'chosen-order',
        'title': '原始',
        'price': 120,
      },
      nextValues: const <String, dynamic>{
        'id': 'chosen-order',
        'title': '原始',
        'price': 245,
      },
      deviceId: 'desktop',
    );
    await store.write(accountId: accountId, record: phone);
    final canonical = _recordFile(temporary, SyncEntityKind.order, 'chosen-order');
    final conflict = File('${canonical.path.substring(0, canonical.path.length - 5)}'
        '.sync-conflict-20261010-desktop.json');
    await conflict.writeAsString(pc.copyWith(accountId: accountId).encode());
    for (var i = 0; i < 250; i++) {
      final unrelated = SyncRecord.bootstrap(
        kind: SyncEntityKind.order,
        id: 'unrelated-$i',
        values: <String, dynamic>{
          'id': 'unrelated-$i',
          'title': '无关历史订单',
        },
        deviceId: 'phone',
      );
      await store.write(accountId: accountId, record: unrelated);
    }

    final targeted = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.order,
      recordId: 'chosen-order',
    );
    expect(targeted, isNotNull);
    expect(engine.materialize(targeted!)!['title'], '手机编辑');
    expect(engine.materialize(targeted)!['price'], 245);
    expect(await conflict.exists(), isFalse);
    expect(await canonical.exists(), isTrue);
    final all = await store.readAllMerged(
      accountId: accountId,
      kind: SyncEntityKind.order,
    );
    expect(all.length, 251);
  });

  test('unexpectedly named legacy sync variant remains mergeable', () async {
    final value = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: const <String, dynamic>{'id': 'app', 'themeMode': 'system'},
      deviceId: 'phone',
    );
    final unusual = File('${temporary.path}/${SyncEntityKind.settings.directoryName}/'
        'manual-backup.copy.json');
    await unusual.parent.create(recursive: true);
    await unusual.writeAsString(value.copyWith(accountId: accountId).encode());

    final merged = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.settings,
      recordId: 'app',
    );
    expect(merged, isNotNull);
    expect(engine.materialize(merged!)!['themeMode'], 'system');
    expect(await unusual.exists(), isFalse);
    expect(await _recordFile(temporary, SyncEntityKind.settings, 'app').exists(),
        isTrue);
  });

  test('settings survive successive phone and desktop edits in both directions', () async {
    final phoneRoot = await Directory('${temporary.path}/phone').create();
    final desktopRoot = await Directory('${temporary.path}/desktop').create();
    final phoneStore = _TemporaryRecordStore(phoneRoot);
    final desktopStore = _TemporaryRecordStore(desktopRoot);
    final stores = [phoneStore, desktopStore];
    final roots = [phoneRoot, desktopRoot];
    final initial = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: <String, dynamic>{
        'id': 'app',
        'themeMode': 'system',
        'themePaletteId': 'guild',
      },
      deviceId: 'phone',
    );
    for (final deviceStore in stores) {
      await deviceStore.write(accountId: accountId, record: initial);
    }

    for (var edit = 0; edit < 4; edit++) {
      final writer = edit % 2;
      final reader = 1 - writer;
      final baseline = (await stores[writer].readAllMerged(
        accountId: accountId,
        kind: SyncEntityKind.settings,
      ))['app']!;
      final before = engine.materialize(baseline)!;
      final after = <String, dynamic>{...before, 'themePaletteId': 'theme-$edit'};
      await stores[writer].write(
        accountId: accountId,
        record: engine.applyLocalSnapshot(
          record: baseline,
          previousValues: before,
          nextValues: after,
          deviceId: writer == 0 ? 'phone' : 'desktop',
        ),
      );
      // The coordinator reads records again to rebuild conflicts before the
      // transport sends the file. That read must leave the source intact.
      await stores[writer].readAllMerged(
        accountId: accountId,
        kind: SyncEntityKind.settings,
      );
      await _recordFile(roots[writer], SyncEntityKind.settings, 'app').copy(
        _recordFile(roots[reader], SyncEntityKind.settings, 'app').path,
      );
      final received = (await stores[reader].readAllMerged(
        accountId: accountId,
        kind: SyncEntityKind.settings,
      ))['app']!;
      expect(engine.materialize(received), after);
      expect(received.conflicts, isEmpty);
      expect(await _recordFile(roots[reader], SyncEntityKind.settings, 'app').exists(), isTrue);
    }
  });

  test('portable restore overlays bundled assets without dropping existing ones', () async {
    final existing = File(
      '${temporary.path}/assets/order-reference-images/old/old.png',
    );
    await existing.parent.create(recursive: true);
    await existing.writeAsBytes(<int>[1, 2, 3], flush: true);

    final importedRoot = await Directory.systemTemp.createTemp(
      'guild-import-assets-',
    );
    addTearDown(() async {
      if (await importedRoot.exists()) {
        await importedRoot.delete(recursive: true);
      }
    });
    final imported = File(
      '${importedRoot.path}/order-reference-images/new/new.png',
    );
    await imported.parent.create(recursive: true);
    await imported.writeAsBytes(<int>[9, 8, 7], flush: true);

    await store.replacePortableRecords(
      accountId: accountId,
      records: const <Map<String, dynamic>>[],
      assetSourceDirectory: importedRoot,
    );

    expect(
      await File(
        '${temporary.path}/assets/order-reference-images/old/old.png',
      ).readAsBytes(),
      <int>[1, 2, 3],
    );
    expect(
      await File(
        '${temporary.path}/assets/order-reference-images/new/new.png',
      ).readAsBytes(),
      <int>[9, 8, 7],
    );
  });

  test('portable restore retains consensus-gated old art cleanup markers', () async {
    final marker = File('${temporary.path}/gc-asset-candidates/marked.json');
    await marker.parent.create(recursive: true);
    await marker.writeAsString(
      '{"schemaVersion":1,"relativePath":"assets/order-reference-images/a/b.png"}',
      flush: true,
    );

    await store.replacePortableRecords(
      accountId: accountId,
      records: const <Map<String, dynamic>>[],
    );
    expect(await marker.exists(), isTrue);
    expect(await marker.readAsString(), contains('relativePath'));
  });

  test('restore ZIP assets override matching paths while preserving offline-only files', () async {
    final oldShared = File('${temporary.path}/assets/refs/same.png');
    final oldOnly = File('${temporary.path}/assets/refs/offline.png');
    await oldShared.parent.create(recursive: true);
    await oldShared.writeAsBytes(<int>[1, 1, 1]);
    await oldOnly.writeAsBytes(<int>[9, 9, 9]);

    final importDir = await Directory.systemTemp.createTemp('guild-overlay-');
    addTearDown(() async {
      if (await importDir.exists()) await importDir.delete(recursive: true);
    });
    final backupImage = File('${importDir.path}/refs/same.png');
    final newOnly = File('${importDir.path}/refs/new.png');
    await backupImage.parent.create(recursive: true);
    await backupImage.writeAsBytes(<int>[2, 2, 2]);
    await newOnly.writeAsBytes(<int>[3, 3, 3]);

    await store.replacePortableRecords(
      accountId: accountId,
      records: const <Map<String, dynamic>>[],
      assetSourceDirectory: importDir,
    );
    expect(await oldShared.readAsBytes(), <int>[2, 2, 2]);
    expect(await oldOnly.readAsBytes(), <int>[9, 9, 9]);
    expect(
      await File('${temporary.path}/assets/refs/new.png').readAsBytes(),
      <int>[3, 3, 3],
    );
    // Pre-staging copies from the imported bundle without consuming it.
    expect(await backupImage.readAsBytes(), <int>[2, 2, 2]);
  });

  test('temporary ZIP asset ownership transfers by directory rename when possible', () async {
    final imported = await Directory('${temporary.path}/bundle/assets')
        .create(recursive: true);
    final art = File('${imported.path}/refs/big-picture.png');
    await art.parent.create(recursive: true);
    await art.writeAsBytes(List<int>.filled(1024 * 1024, 7));

    await store.replacePortableRecords(
      accountId: accountId,
      records: const <Map<String, dynamic>>[],
      assetSourceDirectory: imported,
      transferImportedAssets: true,
    );

    final recovered = File('${temporary.path}/assets/refs/big-picture.png');
    expect(await recovered.length(), 1024 * 1024);
    expect(await recovered.readAsBytes(), List<int>.filled(1024 * 1024, 7));
    // The disposable import folder was moved rather than copied, reducing
    // the simultaneous on-disk footprint when the filesystem supports it.
    expect(await imported.exists(), isFalse);
  });

  test('failed restore returns transferred ZIP asset source to caller', () async {
    final original = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'survivor',
      values: const <String, dynamic>{'id': 'survivor', 'title': '原来的订单'},
      deviceId: 'phone',
    );
    await store.write(accountId: accountId, record: original);
    final oldAsset = File('${temporary.path}/assets/refs/file');
    await oldAsset.parent.create(recursive: true);
    await oldAsset.writeAsBytes([8, 9, 10]);

    final source = await Directory('${temporary.path}/bundle/assets')
        .create(recursive: true);
    final newArt = File('${source.path}/refs/file/image.png');
    await newArt.parent.create(recursive: true);
    await newArt.writeAsBytes([4, 5, 6]);

    await expectLater(
      store.replacePortableRecords(
        accountId: accountId,
        records: const <Map<String, dynamic>>[],
        assetSourceDirectory: source,
        transferImportedAssets: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await oldAsset.readAsBytes(), [8, 9, 10]);
    expect(await newArt.readAsBytes(), [4, 5, 6]);
    final restored = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.order,
      recordId: 'survivor',
    );
    expect(engine.materialize(restored!)!['title'], '原来的订单');
  });

  test('restore rolls back the entire old root on asset merge failure', () async {
    final original = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'untouched-order',
      values: const <String, dynamic>{
        'id': 'untouched-order',
        'title': 'must survive rollback',
      },
      deviceId: 'phone',
    );
    await store.write(accountId: accountId, record: original);
    final oldFile = File('${temporary.path}/assets/refs/shape');
    await oldFile.parent.create(recursive: true);
    await oldFile.writeAsBytes(<int>[8, 7, 6]);

    // Import claims that a *file* already in the live root is a directory.
    // This must fail after staging and after renaming the old root aside,
    // and then restore the exact old root and all of its assets.
    final imported = await Directory.systemTemp.createTemp('guild-bad-merge-');
    addTearDown(() async {
      if (await imported.exists()) await imported.delete(recursive: true);
    });
    final colliding = File('${imported.path}/refs/shape/new.png');
    await colliding.parent.create(recursive: true);
    await colliding.writeAsBytes(<int>[1, 2, 3]);

    await expectLater(
      store.replacePortableRecords(
        accountId: accountId,
        records: const <Map<String, dynamic>>[],
        assetSourceDirectory: imported,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await oldFile.readAsBytes(), <int>[8, 7, 6]);
    final restored = await store.readMergedRecord(
      accountId: accountId,
      kind: SyncEntityKind.order,
      recordId: 'untouched-order',
    );
    expect(restored, isNotNull);
    expect(engine.materialize(restored!)!['title'], 'must survive rollback');
    expect(await Directory('${temporary.path}/assets/refs/shape').exists(),
        isFalse);
  });

}
