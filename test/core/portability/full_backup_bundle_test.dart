import 'dart:convert';
import 'dart:io';

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

  AppBackupData backupWithProductImage({required int sizeBytes}) {
    final image = OrderReferenceImage(
      id: 'ref-product-1',
      fileName: '成品参考.png',
      relativePath:
          'assets/order-reference-images/cHJvZHVjdC0x/ref-product-1.png',
      addedAt: DateTime.utc(2026, 10, 6, 1),
      sizeBytes: sizeBytes,
    );
    return AppBackupData(
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
  }

  test('full backup includes product-only reference image files', () async {
    final bytes = <int>[11, 22, 33, 44];
    final relativePath =
        'assets/order-reference-images/cHJvZHVjdC0x/ref-product-1.png';
    final asset = File('${syncRoot.path}/$relativePath');
    await asset.parent.create(recursive: true);
    await asset.writeAsBytes(bytes, flush: true);

    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    final backup = backupWithProductImage(sizeBytes: bytes.length);
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
      expect(imported.backup.products.single.referenceImages.length, 1);
      final extracted = File(
        '${imported.extractedDirectory!.path}/$relativePath',
      );
      expect(await extracted.readAsBytes(), bytes);
    } finally {
      await imported.dispose();
    }
  });

  test('full backup refuses missing product reference images', () async {
    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );
    expect(
      () => service.exportFullBackup(
        accountId: 'account',
        backup: backupWithProductImage(sizeBytes: 4),
        fileName: 'backup.zip',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await exportedFile.exists(), isFalse);
  });

  test('ZIP import rejects duplicate reference image entries', () async {
    // A deliberately malformed, real ZIP with two central-directory entries
    // for the same asset. ZipFileEncoder deduplicates repeated addFile calls,
    // so construct this tiny fixture via Python's standard zipfile instead.
    // No manifest is needed: ambiguous entries must be rejected before
    // extraction or manifest decoding.
    const duplicateZipBase64 =
        'UEsDBBQAAAAAAM48Sl1X7nGSBQAAAAUAAAAyAAAAYXNzZXRzL29yZGVyLXJl'
        'ZmVyZW5jZS1pbWFnZXMvYjNKa1pYSXRNUS9yZWYtMS5wbmdmaXJzdFBLAwQU'
        'AAAAAADOPEpdaREftgYAAAAGAAAAMgAAAGFzc2V0cy9vcmRlci1yZWZlcmVu'
        'Y2UtaW1hZ2VzL2IzSmtaWEl0TVEvcmVmLTEucG5nc2Vjb25kUEsBAhQDFAAA'
        'AAAAzjxKXVfucZIFAAAABQAAADIAAAAAAAAAAAAAAIABAAAAAGFzc2V0cy9v'
        'cmRlci1yZWZlcmVuY2UtaW1hZ2VzL2IzSmtaWEl0TVEvcmVmLTEucG5nUEsB'
        'AhQDFAAAAAAAzjxKXWkRH7YGAAAABgAAADIAAAAAAAAAAAAAAIABVQAAAGFz'
        'c2V0cy9vcmRlci1yZWZlcmVuY2UtaW1hZ2VzL2IzSmtaWEl0TVEvcmVmLTEu'
        'cG5nUEsFBgAAAAACAAIAwAAAAKsAAAAAAA==';

    await exportedFile.writeAsBytes(base64Decode(duplicateZipBase64));
    final service = FullBackupBundleService(
      syncRecordStore: _TemporaryRecordStore(syncRoot),
      fileBridge: _CapturingFileBridge(exportedFile),
    );

    await expectLater(
      service.readBackupFile(exportedFile, displayName: 'backup.zip'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('重复文件'),
        ),
      ),
    );
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
