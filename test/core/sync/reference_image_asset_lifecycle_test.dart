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

void main() {
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
    store.markCommitted(<dynamic>[committed].cast());
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
