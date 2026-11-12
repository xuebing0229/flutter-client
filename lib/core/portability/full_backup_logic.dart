import 'app_backup_data.dart';

AppBackupData withFullBackupMetadata(
  AppBackupData source, {
  Iterable<String>? screenshotImportHistory,
  Object? desktopPetBackup,
}) {
  final settings = <String, dynamic>{...source.settings};
  if (screenshotImportHistory != null) {
    settings['screenshotImportHistory'] =
        screenshotImportHistory.where((item) => item.isNotEmpty).toSet().toList()
          ..sort();
  }
  if (desktopPetBackup != null) {
    settings['desktopPetBackup'] = desktopPetBackup;
  }
  return AppBackupData(
    exportedAt: source.exportedAt,
    orders: source.orders,
    products: source.products,
    nodePresets: source.nodePresets,
    focusSessions: source.focusSessions,
    accountSyncState: source.accountSyncState,
    syncRecords: source.syncRecords,
    settings: settings,
  );
}

Set<String>? parseScreenshotImportHistory(AppBackupData backup) {
  final raw = backup.settings['screenshotImportHistory'];
  if (raw == null) return null;
  if (raw is! List || raw.any((item) => item is! String)) {
    throw const FormatException('截图导入历史格式无效。');
  }
  return raw.cast<String>().where((item) => item.isNotEmpty).toSet();
}

int backupReferenceImageCount(AppBackupData backup) {
  return backup.orders.fold<int>(
        0,
        (count, order) => count + order.referenceImages.length,
      ) +
      backup.products.fold<int>(
        0,
        (count, product) => count + product.referenceImages.length,
      );
}

void validateBackupForCurrentAccount({
  required AppBackupData backup,
  required String? currentAccountId,
}) {
  if (backup.syncRecords == null) {
    throw const FormatException(
      '这份备份不包含双端同步历史，不能作为完整备份恢复。'
      '请重新导出完整备份后再恢复。',
    );
  }
  final incoming = backup.accountSyncState;
  if (currentAccountId != null && incoming == null) {
    throw const FormatException('这份备份没有账号归属信息，不能覆盖当前账号。');
  }
  if (incoming != null &&
      currentAccountId != null &&
      incoming.accountId != currentAccountId) {
    throw const FormatException('这份备份属于另一个激活账号，不能导入到当前账号。');
  }
}
