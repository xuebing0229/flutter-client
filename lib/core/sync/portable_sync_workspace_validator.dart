import 'dart:convert';

import '../portability/app_backup_data.dart';
import 'sync_entity_codec.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';
import 'sync_record_store.dart';

class PortableSyncWorkspaceValidator {
  const PortableSyncWorkspaceValidator._();

  static void validateBackup({
    required AppBackupData backup,
    required String accountId,
  }) {
    final records = backup.syncRecords;
    if (records == null) {
      throw const FormatException('备份缺少双端同步历史。');
    }

    final embeddedAccountId = backup.accountSyncState?.accountId;
    if (embeddedAccountId != null && embeddedAccountId != accountId) {
      throw const FormatException('备份属于另一个账号，已拒绝恢复。');
    }

    final orders = <String, Map<String, dynamic>>{
      for (final order in backup.orders)
        order.id: SyncEntityCodec.orderToFields(order),
    };
    final products = <String, Map<String, dynamic>>{
      for (final product in backup.products)
        product.id: SyncEntityCodec.productToFields(product),
    };
    final presets = <String, Map<String, dynamic>>{
      for (final preset in backup.nodePresets)
        preset.id: SyncEntityCodec.nodePresetToFields(preset),
    };

    final mergeEngine = SyncMergeEngine();
    final recordStore = SyncRecordStore(mergeEngine: mergeEngine);
    recordStore.validatePortableRecords(
      accountId: accountId,
      records: records,
      requiredIds: <SyncEntityKind, Set<String>>{
        SyncEntityKind.order: orders.keys.toSet(),
        SyncEntityKind.product: products.keys.toSet(),
        SyncEntityKind.nodePreset: presets.keys.toSet(),
      },
    );

    if (!recordsMatchWorkspace(
      accountId: accountId,
      records: records,
      orders: orders,
      products: products,
      presets: presets,
      mergeEngine: mergeEngine,
    )) {
      throw const FormatException(
        '备份正文与双端同步历史不一致，已停止恢复以避免覆盖成错误数据。'
        '请从来源设备用当前版本重新导出。',
      );
    }
  }

  static bool recordsMatchWorkspace({
    required String accountId,
    required List<Map<String, dynamic>> records,
    required Map<String, Map<String, dynamic>> orders,
    required Map<String, Map<String, dynamic>> products,
    required Map<String, Map<String, dynamic>> presets,
    SyncMergeEngine? mergeEngine,
  }) {
    final engine = mergeEngine ?? SyncMergeEngine();
    final expected = <SyncEntityKind, Map<String, Map<String, dynamic>>>{
      SyncEntityKind.order: orders,
      SyncEntityKind.product: products,
      SyncEntityKind.nodePreset: presets,
    };
    final seen = <SyncEntityKind, Set<String>>{
      for (final kind in SyncEntityKind.values) kind: <String>{},
    };
    final identities = <String>{};

    try {
      for (final raw in records) {
        final record = SyncRecord.decode(jsonEncode(raw));
        if (record.accountId != accountId) return false;

        final identity = '${record.kind.name}\u0000${record.id}';
        if (!identities.add(identity)) return false;

        final local = expected[record.kind]![record.id];
        final materialized = engine.materializeKeepingLocalConflicts(
          record,
          local,
        );

        if (local == null) {
          if (materialized != null) return false;
        } else {
          if (materialized == null ||
              !syncJsonEquals(local, materialized)) {
            return false;
          }
          seen[record.kind]!.add(record.id);
        }
      }
    } catch (_) {
      return false;
    }

    for (final entry in expected.entries) {
      if (!seen[entry.key]!.containsAll(entry.value.keys)) return false;
    }
    return true;
  }
}
