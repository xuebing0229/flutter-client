import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/sync/sync_asset_gc_store.dart';
import 'package:flutter_app/core/sync/sync_gc_ack_store.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _SyncRoot extends SyncRecordStore {
  _SyncRoot(this.root);

  final Directory root;

  @override
  Future<Directory> rootDirectory(String accountId) async {
    await root.create(recursive: true);
    return root;
  }
}

void main() {
  const accountId = 'asset-gc-test';
  const imagePath = 'assets/order-reference-images/b3JkZXItMQ/ref-123.png';
  late Directory temp;
  late _SyncRoot records;
  late SyncGcAckStore acks;
  late SyncAssetGcStore gc;

  Map<SyncEntityKind, Map<String, SyncRecord>> recordSet({
    bool referenced = false,
  }) {
    final values = <String, dynamic>{
      'id': 'test-product',
      'referenceImages': <Map<String, dynamic>>[
        if (referenced) <String, dynamic>{
          'id': 'image-123',
          'relativePath': imagePath,
          'fileName': 'ref.png',
        },
      ],
    };
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.product,
      id: 'test-product',
      values: values,
      deviceId: 'phone',
    );
    return <SyncEntityKind, Map<String, SyncRecord>>{
      SyncEntityKind.order: <String, SyncRecord>{},
      SyncEntityKind.product: <String, SyncRecord>{
        'test-product': record,
      },
    };
  }

  Future<File> createImage() async {
    final image = File(
      '${temp.path}${Platform.pathSeparator}'
      '${imagePath.split('/').join(Platform.pathSeparator)}',
    );
    await image.parent.create(recursive: true);
    await image.writeAsBytes([10, 20, 30], flush: true);
    return image;
  }

  Future<void> ackDevices(
    Map<SyncEntityKind, Map<String, SyncRecord>> state, {
    bool desktop = true,
  }) async {
    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'phone',
      recordsByKind: state,
      assetGcPeers: const {'phone', 'desktop'},
    );
    if (desktop) {
      await acks.writeSnapshot(
        accountId: accountId,
        deviceId: 'desktop',
        recordsByKind: state,
      assetGcPeers: const {'phone', 'desktop'},
      );
    }
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('guild-safe-art-gc-');
    records = _SyncRoot(temp);
    acks = SyncGcAckStore(recordStore: records);
    gc = SyncAssetGcStore(recordStore: records, gcAckStore: acks);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('offline or old-device ACKs block physical deletion',
      () async {
    final image = await createImage();
    final state = recordSet();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );

    Future<int> collect() => gc.collectAcknowledged(
      accountId: accountId,
      activeDeviceIds: {'phone', 'desktop'},
      recordsByKind: state,
    );

    expect(await collect(), 0);
    expect(await image.exists(), isTrue);

    await ackDevices(state, desktop: false);
    expect(await collect(), 0);
    expect(await image.exists(), isTrue);

    // Simulate desktop running an older app that only publishes legacy
    // record-history acknowledgements, with no asset-GC capability flag.
    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'desktop',
      recordsByKind: state,
      assetGcPeers: const {'phone', 'desktop'},
    );
    final oldAck = File(
      '${temp.path}/gc-acks/'
      '${base64UrlEncode(utf8.encode('desktop')).replaceAll('=', '')}.json',
    );
    final decoded = jsonDecode(await oldAck.readAsString()) as Map<String, dynamic>;
    decoded.remove('assetGcVersion');
    await oldAck.writeAsString(jsonEncode(decoded));
    expect(await collect(), 0);
    expect(await image.exists(), isTrue);

    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'desktop',
      recordsByKind: state,
      assetGcPeers: const {'phone', 'desktop'},
    );
    expect(await collect(), 1);
    expect(await image.exists(), isFalse);
    expect(await collect(), 0);
  });

  test('a still-referenced image is never GCed, even with unanimous acks',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final referenced = recordSet(referenced: true);
    await ackDevices(referenced);
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: referenced,
      ),
      0,
    );
    expect(await image.exists(), isTrue);
  });

  test('peer snapshot mismatch blocks GC until every peer sees removal',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final stale = recordSet(referenced: true);
    final current = recordSet();
    await ackDevices(stale);
    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'phone',
      recordsByKind: current,
      assetGcPeers: const {'phone', 'desktop'},
    );
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      0,
    );
    expect(await image.exists(), isTrue);

    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'desktop',
      recordsByKind: current,
      assetGcPeers: const {'phone', 'desktop'},
    );
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      1,
    );
    expect(await image.exists(), isFalse);
  });

  test('Syncthing conflict variant of a device ACK blocks all art deletion',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final current = recordSet();
    await ackDevices(current);
    final original = File(
      '${temp.path}/gc-acks/'
      '${base64UrlEncode(utf8.encode('desktop')).replaceAll('=', '')}.json',
    );
    final conflict = File(
      original.path.replaceFirst('.json', '.sync-conflict-20261010-pc.json'),
    );
    await original.copy(conflict.path);
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      0,
    );
    expect(await image.exists(), isTrue);

    await conflict.delete();
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      1,
    );
  });

  test('other entity still referencing image prevents GC after original removed',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final data = recordSet();
    data[SyncEntityKind.order]!['another-order'] = SyncRecord.bootstrap(
      kind: SyncEntityKind.order,
      id: 'another-order',
      values: <String, dynamic>{
        'id': 'another-order',
        'referenceImages': <Map<String, dynamic>>[
          {'id': 'shared', 'relativePath': imagePath},
        ],
      },
      deviceId: 'desktop',
    );
    await ackDevices(data);
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: data,
      ),
      0,
    );
    expect(await image.exists(), isTrue);
  });

  test('a newly paired peer known only to the other device blocks cleanup',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final current = recordSet();
    await ackDevices(current);
    // Desktop learned about a third bound phone before this machine did.
    // Even though both machines agree on order/product hashes, they have NOT
    // converged on which peers must be consulted before deleting the art.
    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'desktop',
      recordsByKind: current,
      assetGcPeers: const {'phone', 'desktop', 'third-phone'},
    );
    Future<int> collect() => gc.collectAcknowledged(
      accountId: accountId,
      activeDeviceIds: {'phone', 'desktop'},
      recordsByKind: current,
    );
    expect(await collect(), 0);
    expect(await image.exists(), isTrue);
    // When all devices eventually agree on membership, a new snapshot may
    // authorize cleanup (provided its contents also still match).
    await acks.writeSnapshot(
      accountId: accountId,
      deviceId: 'desktop',
      recordsByKind: current,
      assetGcPeers: const {'phone', 'desktop'},
    );
    expect(await collect(), 1);
  });

  test('cleans immediately on unanimous current ACK, without a day-based hold',
      () async {
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    final current = recordSet();
    // All bound devices already agree that no order or product needs this
    // binary. No 30-day wait, nor an artificial clock advance, is necessary.
    await ackDevices(current);
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      1,
    );
    expect(await image.exists(), isFalse);
  });

  test('unchanged ACKs are reusable without refreshing a clock', () async {
    final current = recordSet();
    await ackDevices(current);
    final file = File(
      '${temp.path}/gc-acks/'
      '${base64UrlEncode(utf8.encode('phone')).replaceAll('=', '')}.json',
    );
    final before = await file.readAsString();
    await ackDevices(current);
    expect(await file.readAsString(), before);
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [imagePath],
    );
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      1,
    );
    expect(await image.exists(), isFalse);
  });

  test('rejects unsafe paths and never deletes a symlink target', () async {
    expect(
      SyncAssetGcStore.isSafeReferencePath('assets/../secrets.txt'),
      isFalse,
    );
    expect(
      SyncAssetGcStore.isSafeReferencePath(
        'assets/order-reference-images/abc/../../secret.png',
      ),
      isFalse,
    );
    final image = await createImage();
    await gc.registerUnlinked(
      accountId: accountId,
      relativePaths: [
        '../private/data',
        imagePath,
      ],
    );
    final current = recordSet();
    await ackDevices(current);
    // Replace the image with a link to a non-account file. Deleting it must
    // be forbidden even though every peer has agreed on the reference state.
    final outside = File('${temp.parent.path}/external-guild-target.png');
    await outside.writeAsBytes([99, 98, 97]);
    addTearDown(() async {
      if (await outside.exists()) await outside.delete();
    });
    await image.delete();
    try {
      await Link(image.path).create(outside.path);
    } on FileSystemException {
      return; // Some Windows CI environments disallow creating symlinks.
    }
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      0,
    );
    expect(await outside.readAsBytes(), [99, 98, 97]);
  });

  test('does not delete a physical file never scheduled from a saved edit',
      () async {
    final image = await createImage();
    final current = recordSet();
    await ackDevices(current);
    expect(
      await gc.collectAcknowledged(
        accountId: accountId,
        activeDeviceIds: {'phone', 'desktop'},
        recordsByKind: current,
      ),
      0,
    );
    expect(await image.exists(), isTrue);
  });
}
