import 'dart:io';

import 'package:flutter_app/core/portability/data_portability_file_bridge.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_app/features/orders/data/order_reference_image_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalSyncRoot extends SyncRecordStore {
  _LocalSyncRoot(this.root);
  final Directory root;

  @override
  Future<Directory> rootDirectory(String accountId) async {
    await root.create(recursive: true);
    return root;
  }
}

class _PickedImages extends DataPortabilityFileBridge {
  _PickedImages(this.source);
  final File source;

  @override
  Future<List<PickedLocalImage>> pickImages() async => <PickedLocalImage>[
    PickedLocalImage(path: source.path, name: 'local-picture.png'),
  ];
}

class _PartialBatchImages extends DataPortabilityFileBridge {
  _PartialBatchImages(this.valid, this.missing);
  final File valid;
  final File missing;

  @override
  Future<List<PickedLocalImage>> pickImages() async => <PickedLocalImage>[
    PickedLocalImage(path: valid.path, name: 'first.png'),
    PickedLocalImage(path: missing.path, name: 'missing.png'),
  ];
}

void main() {
  test('failed batch rolls back imported images without leaving .tmp files',
      () async {
    final temporary = await Directory.systemTemp.createTemp(
      'guild-reference-batch-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final source = File('${temporary.path}/original.png');
    await source.writeAsBytes(List<int>.filled(4096, 42), flush: true);
    final syncRoot = Directory('${temporary.path}/sync-root');
    final store = OrderReferenceImageStore(
      syncRecordStore: _LocalSyncRoot(syncRoot),
      fileBridge: _PartialBatchImages(
        source,
        File('${temporary.path}/missing.png'),
      ),
    );

    await expectLater(
      store.pickAndImport(accountId: 'sample-account', orderId: 'order-safe'),
      throwsA(isA<StateError>()),
    );

    final files = await syncRoot
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File)
        .toList();
    expect(files, isEmpty);
  });

  test('only uncommitted draft images can be physically deleted', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'guild-reference-safety-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final source = File('${temporary.path}/original.png');
    await source.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    final syncRoot = Directory('${temporary.path}/sync-root');
    final store = OrderReferenceImageStore(
      syncRecordStore: _LocalSyncRoot(syncRoot),
      fileBridge: _PickedImages(source),
    );

    final committed = (await store.pickAndImport(
      accountId: 'sample-account',
      orderId: 'order-safe',
    )).single;
    expect(
      await store.exists(accountId: 'sample-account', image: committed),
      isTrue,
    );
    store.markCommitted([committed]);
    // Even if an old caller tries to discard this image, it is durable and
    // must be preserved while a different device may still be offline.
    await store.discardUnsavedImages(
      accountId: 'sample-account',
      images: [committed],
    );
    expect(
      await store.exists(accountId: 'sample-account', image: committed),
      isTrue,
    );

    final draft = (await store.pickAndImport(
      accountId: 'sample-account',
      orderId: 'order-safe',
    )).single;
    await store.discardUnsavedImages(
      accountId: 'sample-account',
      images: [draft],
    );
    expect(
      await store.exists(accountId: 'sample-account', image: draft),
      isFalse,
    );
    expect(
      await store.exists(accountId: 'sample-account', image: committed),
      isTrue,
    );
  });
}
