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

}
