import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_app/core/portability/app_backup_data.dart';
import 'package:flutter_app/core/portability/data_portability_file_bridge.dart';
import 'package:flutter_app/core/portability/full_backup_bundle_service.dart';
import 'package:flutter_app/core/sync/sync_record_store.dart';
import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/products/domain/finished_product.dart';
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

class _PickingFileBridge extends DataPortabilityFileBridge {
  _PickingFileBridge(this.picked);

  final PickedBackupFile picked;

  @override
  Future<PickedBackupFile?> pickBackupFile() async => picked;
}

class _CapturingFileBridge extends DataPortabilityFileBridge {
  _CapturingFileBridge(this.destination);

  final File destination;

  @override
  Future<bool> exportLocalFile({
    required String sourcePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    await destination.parent.create(recursive: true);
    await File(sourcePath).copy(destination.path);
    return true;
  }
}

void main() {
  late Directory temporary;
  late Directory syncRoot;
  late File exportedFile;

  const preset = NodePreset(
    id: 'preset',
    name: '默认',
    nodes: <NodeDefinition>[
      NodeDefinition(
        id: 'draft',
        name: '草图',
        iconKey: 'edit',
        colorValue: 0xFF777777,
        progressPercent: 20,
      ),
    ],
  );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'guild-full-backup-test-',
    );
    syncRoot = Directory('${temporary.path}/sync-v1');
    await syncRoot.create(recursive: true);
    exportedFile = File('${temporary.path}/captured-backup.zip');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  AppBackupData backupWithImage({required int sizeBytes}) {
    final image = OrderReferenceImage(
      id: 'ref-1',
      fileName: '参考.png',
      relativePath: 'assets/order-reference-images/b3JkZXItMQ/ref-1.png',
      addedAt: DateTime.utc(2026, 10, 6, 1),
      sizeBytes: sizeBytes,
    );
    return AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: <QueueOrder>[
        QueueOrder(
          id: 'order-1',
          platform: CommissionPlatform.mihuashi,
          title: '测试排单',
          clientName: '测试',
          deadline: null,
          nodePresetId: preset.id,
          nodePresetSnapshot: preset,
          currentNodeId: 'draft',
          referenceImages: <OrderReferenceImage>[image],
        ),
      ],
      products: const [],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
  }

  test('full backup zip contains and restores reference image originals', () async {
    final bytes = <int>[1, 2, 3, 4, 5, 6, 7, 8];
    final asset = File(
      '${syncRoot.path}/assets/order-reference-images/b3JkZXItMQ/ref-1.png',
    );
    await asset.parent.create(recursive: true);
    await asset.writeAsBytes(bytes, flush: true);

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    final backup = backupWithImage(sizeBytes: bytes.length);

    expect(
      await service.exportFullBackup(
        accountId: 'account',
        backup: backup,
        fileName: 'backup.zip',
      ),
      isTrue,
    );
    expect(await exportedFile.exists(), isTrue);

    final imported = await service.readBackupFile(
      exportedFile,
      displayName: 'backup.zip',
    );
    try {
      expect(imported.includesBundledAssets, isTrue);
      expect(imported.backup.orders.single.title, '测试排单');

      final restoredAsset = File(
        '${imported.extractedDirectory!.path}/'
        'assets/order-reference-images/b3JkZXItMQ/ref-1.png',
      );
      expect(await restoredAsset.readAsBytes(), bytes);
    } finally {
      await imported.dispose();
    }
  });

  test('full backup refuses to silently omit an unsynced image', () async {
    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );

    expect(
      () => service.exportFullBackup(
        accountId: 'account',
        backup: backupWithImage(sizeBytes: 8),
        fileName: 'backup.zip',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('full backup also contains finished-product reference images', () async {
    final bytes = <int>[9, 8, 7, 6];
    final image = OrderReferenceImage(
      id: 'product-ref-1',
      fileName: '成品参考.png',
      relativePath:
          'assets/order-reference-images/cHJvZHVjdC0x/product-ref-1.png',
      addedAt: DateTime.utc(2026, 10, 6, 1),
      sizeBytes: bytes.length,
    );
    final asset = File(
      '${syncRoot.path}/assets/order-reference-images/'
      'cHJvZHVjdC0x/product-ref-1.png',
    );
    await asset.parent.create(recursive: true);
    await asset.writeAsBytes(bytes, flush: true);

    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: const <QueueOrder>[],
      products: <FinishedProduct>[
        FinishedProduct(
          id: 'product-1',
          title: '测试成品',
          platform: CommissionPlatform.huajia,
          saleType: ProductSaleType.multiple,
          referenceImages: <OrderReferenceImage>[image],
        ),
      ],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );

    expect(
      await service.exportFullBackup(
        accountId: 'account',
        backup: backup,
        fileName: 'backup.zip',
      ),
      isTrue,
    );

    final imported = await service.readBackupFile(
      exportedFile,
      displayName: 'backup.zip',
    );
    try {
      expect(imported.backup.products.single.title, '测试成品');
      final restoredAsset = File(
        '${imported.extractedDirectory!.path}/assets/order-reference-images/'
        'cHJvZHVjdC0x/product-ref-1.png',
      );
      expect(await restoredAsset.readAsBytes(), bytes);
    } finally {
      await imported.dispose();
    }
  });
  test('full backup rejects an unreferenced bundled asset', () async {
    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: const <QueueOrder>[],
      products: const <FinishedProduct>[],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
    final buildRoot = await Directory.systemTemp.createTemp(
      'guild-extra-backup-',
    );
    addTearDown(() async {
      if (await buildRoot.exists()) {
        await buildRoot.delete(recursive: true);
      }
    });
    final manifest = File('${buildRoot.path}/backup.json');
    await manifest.writeAsString(backup.encode(), flush: true);
    final orphan = File('${buildRoot.path}/orphan.png');
    await orphan.writeAsBytes(<int>[1, 2, 3], flush: true);
    final crafted = File('${buildRoot.path}/crafted.zip');

    final encoder = ZipFileEncoder();
    encoder.create(crafted.path);
    try {
      await encoder.addFile(manifest, 'backup.json');
      await encoder.addFile(
        orphan,
        'assets/order-reference-images/orphan/orphan.png',
        ZipFileEncoder.store,
      );
    } finally {
      await encoder.close();
    }

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    expect(
      () => service.readBackupFile(crafted, displayName: 'crafted.zip'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('未被数据清单引用'),
        ),
      ),
    );
  });


  test('full backup rejects duplicate backup.json manifests', () async {
    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: const <QueueOrder>[],
      products: const <FinishedProduct>[],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
    final buildRoot = await Directory.systemTemp.createTemp(
      'guild-duplicate-manifest-',
    );
    addTearDown(() async {
      if (await buildRoot.exists()) {
        await buildRoot.delete(recursive: true);
      }
    });
    final first = File('${buildRoot.path}/first.json');
    final second = File('${buildRoot.path}/second.json');
    await first.writeAsString(backup.encode(), flush: true);
    await second.writeAsString(backup.encode(), flush: true);
    final crafted = File('${buildRoot.path}/crafted.zip');

    final encoder = ZipFileEncoder();
    encoder.create(crafted.path);
    try {
      await encoder.addFile(first, 'backup.json');
      await encoder.addFile(second, 'backup.json');
    } finally {
      await encoder.close();
    }

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    expect(
      () => service.readBackupFile(crafted, displayName: 'crafted.zip'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('重复的数据清单'),
        ),
      ),
    );
  });

  test('temporary Android-style backup picker copy is released after reading', () async {
    final pickedFile = File('${temporary.path}/picked-backup.json');
    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: const <QueueOrder>[],
      products: const <FinishedProduct>[],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
    await pickedFile.writeAsString(backup.encode(), flush: true);

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _PickingFileBridge(
        PickedBackupFile(
          path: pickedFile.path,
          name: 'picked-backup.json',
          temporary: true,
        ),
      ),
    );

    final imported = await service.pickAndReadBackup();
    expect(imported, isNotNull);
    expect(imported!.backup.nodePresets.single.id, preset.id);
    expect(await pickedFile.exists(), isFalse);
    await imported.dispose();
  });

  test('legacy json backup remains importable but is marked without assets', () async {
    final jsonFile = File('${temporary.path}/legacy.json');
    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 6, 2),
      orders: const <QueueOrder>[],
      products: const [],
      nodePresets: const <NodePreset>[preset],
      syncRecords: const <Map<String, dynamic>>[],
    );
    await jsonFile.writeAsString(backup.encode(), flush: true);

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    final imported = await service.readBackupFile(
      jsonFile,
      displayName: 'legacy.json',
    );

    expect(imported.includesBundledAssets, isFalse);
    expect(imported.backup.nodePresets.single.id, preset.id);
    await imported.dispose();
  });
}
