import '../../features/orders/data/order_reference_image_store.dart';
import '../../features/imports/data/screenshot_import_history.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/state/product_store.dart';
import '../account/account_models.dart';
import '../sync/public_peer_sync_service.dart';

PublicPeerSyncService createWorkspacePublicPeerSyncService({
  required String accountId,
  required String deviceId,
  required AccountSyncState Function() captureAccountState,
  required Future<void> Function(AccountSyncState incoming) mergeAccountState,
  required Future<List<Map<String, dynamic>>> Function() exportRecords,
  required Future<void> Function(List<Map<String, dynamic>> incoming)
      mergeRecords,
  required OrderStore orderStore,
  required ProductStore productStore,
  required OrderReferenceImageStore referenceImageStore,
  bool Function(AccountDevice device)? shouldTargetDevice,
}) {
  const importHistory = ScreenshotImportHistory();
  return PublicPeerSyncService(
    accountId: accountId,
    deviceId: deviceId,
    captureAccountState: captureAccountState,
    mergeAccountState: mergeAccountState,
    exportRecords: exportRecords,
    mergeRecords: mergeRecords,
    shouldTargetDevice: shouldTargetDevice,
    captureAssetPaths: () => <String>{
      for (final order in orderStore.orders)
        for (final image in order.referenceImages) image.relativePath,
      for (final product in productStore.products)
        for (final image in product.referenceImages) image.relativePath,
    },
    assetExists: (path) async =>
        (await referenceImageStore.readAssetBytes(
          accountId: accountId,
          relativePath: path,
        )) !=
        null,
    readAsset: (path) => referenceImageStore.readAssetBytes(
      accountId: accountId,
      relativePath: path,
    ),
    writeAsset: (path, bytes) => referenceImageStore.writeAssetBytes(
      accountId: accountId,
      relativePath: path,
      bytes: bytes,
    ),
    captureImportHistory: () => importHistory.read(accountId: accountId),
    mergeImportHistory: (fingerprints) => importHistory.markImported(
      accountId: accountId,
      fingerprints: fingerprints,
    ),
  );
}
