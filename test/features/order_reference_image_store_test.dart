import 'dart:io';

import 'package:flutter_app/core/portability/data_portability_file_bridge.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_app/features/orders/data/order_reference_image_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _TemporaryRecordStore extends SyncRecordStore {
  _TemporaryRecordStore(this.directory);

  final Directory directory;

  @override
  Future<Directory> rootDirectory(String accountId) async {
    await directory.create(recursive: true);
    return directory;
  }
}

class _PickingImageBridge extends DataPortabilityFileBridge {
  _PickingImageBridge(this.images);

  final List<PickedLocalImage> images;

  @override
  Future<List<PickedLocalImage>> pickImages() async => images;
}

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'guild-reference-picker-test-',
    );
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('temporary picker copy is released after reference image import', () async {
    final source = File('${temporary.path}/picked.png');
    final bytes = <int>[1, 2, 3, 4, 5];
    await source.writeAsBytes(bytes, flush: true);

    final syncRoot = Directory('${temporary.path}/sync-v1');
    final store = OrderReferenceImageStore(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _PickingImageBridge(
        <PickedLocalImage>[
          PickedLocalImage(
            path: source.path,
            name: 'picked.png',
            temporary: true,
          ),
        ],
      ),
    );

    final imported = await store.pickAndImport(
      accountId: 'account',
      orderId: 'order-1',
    );

    expect(imported, hasLength(1));
    expect(await source.exists(), isFalse);
    final stored = await store.localFile(
      accountId: 'account',
      image: imported.single,
    );
    expect(await stored.readAsBytes(), bytes);
  });

  test('temporary picker copy is released when reference import fails', () async {
    final source = File('${temporary.path}/picked.exe');
    await source.writeAsBytes(<int>[1, 2, 3], flush: true);

    final store = OrderReferenceImageStore(
      syncRecordStore: _TemporaryRecordStore(
        Directory('${temporary.path}/sync-v1'),
      ),
      fileBridge: _PickingImageBridge(
        <PickedLocalImage>[
          PickedLocalImage(
            path: source.path,
            name: 'picked.exe',
            temporary: true,
          ),
        ],
      ),
    );

    await expectLater(
      store.pickAndImport(
        accountId: 'account',
        orderId: 'order-1',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await source.exists(), isFalse);
  });
}
