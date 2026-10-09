import 'dart:convert';

import '../../features/focus/domain/focus_session.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/products/domain/finished_product.dart';
import '../portability/app_backup_data.dart';

class SyncEntityCodec {
  const SyncEntityCodec._();

  static Map<String, dynamic> orderToFields(QueueOrder order) {
    final backup = AppBackupData(
      exportedAt: DateTime.now(),
      orders: <QueueOrder>[order],
      products: const <FinishedProduct>[],
      nodePresets: const <NodePreset>[],
    );
    final payload = backup.toJson()['payload'] as Map<String, dynamic>;
    final orders = payload['orders'] as List<dynamic>;
    return Map<String, dynamic>.from(orders.single as Map);
  }

  static QueueOrder orderFromFields(Map<String, dynamic> fields) {
    final backup = AppBackupData.decode(
      _singleEntityBackup(
        orders: <Map<String, dynamic>>[fields],
      ),
    );
    return backup.orders.single;
  }

  static Map<String, dynamic> productToFields(FinishedProduct product) {
    final backup = AppBackupData(
      exportedAt: DateTime.now(),
      orders: const <QueueOrder>[],
      products: <FinishedProduct>[product],
      nodePresets: const <NodePreset>[],
    );
    final payload = backup.toJson()['payload'] as Map<String, dynamic>;
    final products = payload['products'] as List<dynamic>;
    return Map<String, dynamic>.from(products.single as Map);
  }

  static FinishedProduct productFromFields(Map<String, dynamic> fields) {
    final backup = AppBackupData.decode(
      _singleEntityBackup(
        products: <Map<String, dynamic>>[fields],
      ),
    );
    return backup.products.single;
  }

  static Map<String, dynamic> nodePresetToFields(NodePreset preset) {
    final backup = AppBackupData(
      exportedAt: DateTime.now(),
      orders: const <QueueOrder>[],
      products: const <FinishedProduct>[],
      nodePresets: <NodePreset>[preset],
    );
    final payload = backup.toJson()['payload'] as Map<String, dynamic>;
    final presets = payload['nodePresets'] as List<dynamic>;
    return Map<String, dynamic>.from(presets.single as Map);
  }

  static NodePreset nodePresetFromFields(Map<String, dynamic> fields) {
    final backup = AppBackupData.decode(
      _singleEntityBackup(
        nodePresets: <Map<String, dynamic>>[fields],
      ),
    );
    return backup.nodePresets.single;
  }

  static Map<String, dynamic> focusSessionToFields(FocusSession session) {
    return session.toJson();
  }

  static FocusSession focusSessionFromFields(Map<String, dynamic> fields) {
    return FocusSession.fromJson(Map<String, dynamic>.from(fields));
  }

  static String _singleEntityBackup({
    List<Map<String, dynamic>> orders = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> products = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> nodePresets =
        const <Map<String, dynamic>>[],
  }) {
    return jsonEncode(
      <String, dynamic>{
        'kind': appBackupKind,
        'schemaVersion': currentBackupSchemaVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': <String, dynamic>{
          'orders': orders,
          'products': products,
          'nodePresets': nodePresets,
          'settings': <String, dynamic>{},
        },
      },
    );
  }
}
