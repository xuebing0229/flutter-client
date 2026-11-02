import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/state/focus_store.dart';
import '../../features/orders/data/node_presets.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/domain/finished_product.dart';
import '../../features/products/state/product_store.dart';
import 'sync_entity_codec.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';

typedef SyncSettingsCapture = Map<String, dynamic> Function();
typedef SyncSettingsApply = Future<void> Function(Map<String, dynamic> settings);

class SyncConflictView {
  const SyncConflictView({
    required this.kind,
    required this.recordId,
    required this.conflict,
  });

  final SyncEntityKind kind;
  final String recordId;
  final SyncConflict conflict;

  String get entityLabel => switch (kind) {
        SyncEntityKind.order => '排单',
        SyncEntityKind.product => '成品',
        SyncEntityKind.nodePreset => '节点预设',
        SyncEntityKind.focusSession => '专注记录',
        SyncEntityKind.settings => '界面设置',
      };

  String get fieldLabel => syncFieldLabel(conflict.field);
}

String syncFieldLabel(String field) {
  return switch (field) {
    'title' => '名称',
    'clientName' => '单主',
    'platform' => '平台',
    'deadline' => '截稿日期',
    'nodePresetId' => '节点预设',
    'nodePresetSnapshot' => '节点预设快照',
    'currentNodeId' => '当前节点',
    'currentNodeProgress' => '节点小进度',
    'price' => '稿费',
    'feeEnabled' => '手续费',
    'huajiaLoveLevel' => '真爱永恒',
    'onlinePercent' => '线上比例',
    'supplementAmount' => '补款基准',
    'supplementFeeEnabled' => '补款手续费',
    'deductionAmount' => '减款基准',
    'deductionFeeEnabled' => '减款手续费',
    'description' => '备注',
    'tags' => '自定义标签',
    'referenceImages' => '参考图',
    'completedAt' => '交稿时间',
    'settledAt' => '结算时间',
    'settledIncome' => '结算收入',
    'archiveOutcome' => '归档结果',
    'settlementNodeId' => '结算节点',
    'customRefundAmount' => '退款金额',
    'isArchived' => '归档状态',
    'isPinned' => '置顶状态',
    'saleType' => '售卖方式',
    'soldCount' => '售出数量基准',
    'saleRecords' => '售出记录',
    'saleClientNames' => '售出单主',
    'archivedAt' => '归档时间',
    'themeMode' => '主题模式',
    'themePaletteId' => '主题色',
    'customThemePalettes' => '自定义主题色方案',
    'uiStyle' || 'uiTexture' => 'UI风格',
    'features' => '功能开关',
    'feature.clientInfo' => '显示单主信息',
    'feature.customTags' => '自定义标签开关',
    'feature.referenceImages' => '参考图开关',
    'feature.nodeProgress' => '节点小进度',
    'feature.search' => '搜索',
    'feature.sorting' => '排序',
    'feature.viewSwitch' => '列表 / 卡片视图切换',
    'feature.products' => '成品功能开关',
    'feature.schedule' => '日程功能开关',
    'feature.statistics' => '统计功能开关',
    'feature.deadlineReminders' => '截稿提醒开关',
    'feature.abstractMode' => '抽象版开关',
    'feature.abstractEffects' => '抽象版表现',
    'orderCardView' => '排单卡片视图',
    'productCardView' => '成品卡片视图',
    'orderSortMode' => '排单排序',
    'productSortMode' => '成品排序',
    'desktopNavigationOpen' => '电脑导航栏状态',
    'name' => '预设名称',
    'nodes' => '节点内容',
    'startedAt' => '专注开始时间',
    'endedAt' => '专注结束时间',
    'orderId' => '专注排单',
    'orderTitleSnapshot' => '排单标题快照',
    SyncRecord.deletedField => '删除状态',
    _ => field,
  };
}

class SyncWorkspaceEngine {
  SyncWorkspaceEngine({
    required this.orderStore,
    required this.productStore,
    required this.nodePresetStore,
    required this.focusStore,
    required this.captureSettings,
    required this.applySettings,
    required this.mergeEngine,
    this.settingsRecordId = 'app',
  });

  final OrderStore orderStore;
  final ProductStore productStore;
  final NodePresetStore nodePresetStore;
  final FocusStore focusStore;
  final SyncSettingsCapture captureSettings;
  final SyncSettingsApply applySettings;
  final SyncMergeEngine mergeEngine;
  final String settingsRecordId;

  Map<String, Map<String, dynamic>> captureOrders() =>
      <String, Map<String, dynamic>>{
        for (final order in orderStore.orders)
          order.id: SyncEntityCodec.orderToFields(order),
      };

  Map<String, Map<String, dynamic>> captureProducts() =>
      <String, Map<String, dynamic>>{
        for (final product in productStore.products)
          product.id: SyncEntityCodec.productToFields(product),
      };

  Map<String, Map<String, dynamic>> capturePresets() =>
      <String, Map<String, dynamic>>{
        for (final preset in nodePresetStore.presets)
          preset.id: SyncEntityCodec.nodePresetToFields(preset),
      };

  Map<String, Map<String, dynamic>> captureFocusSessions() =>
      <String, Map<String, dynamic>>{
        for (final session in focusStore.sessions)
          session.id: SyncEntityCodec.focusSessionToFields(session),
      };

  Map<SyncEntityKind, Map<String, Map<String, dynamic>>> captureEntities() =>
      <SyncEntityKind, Map<String, Map<String, dynamic>>>{
        SyncEntityKind.order: captureOrders(),
        SyncEntityKind.product: captureProducts(),
        SyncEntityKind.nodePreset: capturePresets(),
        SyncEntityKind.focusSession: captureFocusSessions(),
        SyncEntityKind.settings: <String, Map<String, dynamic>>{
          settingsRecordId: captureSettings(),
        },
      };

  Future<String?> applyEntityRecords(
    SyncEntityKind kind,
    Map<String, SyncRecord> records,
  ) async {
    switch (kind) {
      case SyncEntityKind.order:
        _applyOrderRecords(records);
      case SyncEntityKind.product:
        _applyProductRecords(records);
      case SyncEntityKind.nodePreset:
        _applyPresetRecords(records);
      case SyncEntityKind.focusSession:
        _applyFocusRecords(records);
      case SyncEntityKind.settings:
        return _applySettingsRecords(records);
    }
    return null;
  }

  Future<String?> _applySettingsRecords(
    Map<String, SyncRecord> records,
  ) async {
    final record = records[settingsRecordId];
    if (record == null) return null;
    final local = captureSettings();
    final settings =
        mergeEngine.materializeKeepingLocalConflicts(record, local);
    if (settings == null) return null;
    final normalized = normalizeMaterializedSettings(settings);
    if (syncJsonEquals(normalized, local)) return null;
    try {
      await applySettings(normalized);
      return null;
    } catch (error) {
      return '应用远端界面设置失败：$error';
    }
  }

  Map<String, dynamic> normalizeMaterializedSettings(
    Map<String, dynamic> settings,
  ) {
    final normalized = <String, dynamic>{...settings};
    if (normalized.keys.any((key) => key.startsWith('feature.'))) {
      normalized.remove('features');
    }
    if (normalized.containsKey('uiStyle')) {
      normalized.remove('uiTexture');
    }
    return normalized;
  }

  void _applyOrderRecords(Map<String, SyncRecord> records) {
    final result = <QueueOrder>[];
    for (final existing in orderStore.orders) {
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.orderToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.orderFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }
    for (final record in records.values) {
      if (orderStore.contains(record.id)) continue;
      final fields = mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.orderFromFields(fields));
      } catch (_) {}
    }
    if (!_sameOrders(orderStore.orders, result)) {
      orderStore.replaceAll(result);
    }
  }

  void _applyProductRecords(Map<String, SyncRecord> records) {
    final result = <FinishedProduct>[];
    for (final existing in productStore.products) {
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.productToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.productFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }
    for (final record in records.values) {
      if (productStore.contains(record.id)) continue;
      final fields = mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.productFromFields(fields));
      } catch (_) {}
    }
    if (!_sameProducts(productStore.products, result)) {
      productStore.replaceAll(result);
    }
  }

  void _applyPresetRecords(Map<String, SyncRecord> records) {
    final result = <NodePreset>[];
    final existingIds = <String>{
      for (final preset in nodePresetStore.presets) preset.id,
    };
    for (final existing in nodePresetStore.presets) {
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.nodePresetToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.nodePresetFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }
    for (final record in records.values) {
      if (existingIds.contains(record.id)) continue;
      final fields = mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.nodePresetFromFields(fields));
      } catch (_) {}
    }
    if (!syncJsonEquals(capturePresets(), <String, Map<String, dynamic>>{
      for (final preset in result)
        preset.id: SyncEntityCodec.nodePresetToFields(preset),
    })) {
      nodePresetStore.replaceAll(result);
    }
  }

  void _applyFocusRecords(Map<String, SyncRecord> records) {
    final result = <FocusSession>[];
    for (final existing in focusStore.sessions) {
      final record = records[existing.id];
      if (record == null) {
        result.add(existing);
        continue;
      }
      final fields = mergeEngine.materializeKeepingLocalConflicts(
        record,
        SyncEntityCodec.focusSessionToFields(existing),
      );
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.focusSessionFromFields(fields));
      } catch (_) {
        result.add(existing);
      }
    }
    for (final record in records.values) {
      if (focusStore.contains(record.id)) continue;
      final fields = mergeEngine.materialize(record);
      if (fields == null) continue;
      try {
        result.add(SyncEntityCodec.focusSessionFromFields(fields));
      } catch (_) {}
    }
    if (!_sameFocus(focusStore.sessions, result)) {
      focusStore.replaceAll(result);
    }
  }

  List<SyncConflictView> collectConflicts(
    Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  ) {
    final result = <SyncConflictView>[];
    for (final kind in SyncEntityKind.values) {
      for (final record in recordsByKind[kind]?.values ??
          const <SyncRecord>[]) {
        for (final conflict in record.conflicts.values) {
          result.add(
            SyncConflictView(
              kind: kind,
              recordId: record.id,
              conflict: conflict,
            ),
          );
        }
      }
    }
    result.sort((a, b) => b.conflict.createdAt.compareTo(a.conflict.createdAt));
    return List<SyncConflictView>.unmodifiable(result);
  }

  bool _sameOrders(Iterable<QueueOrder> left, Iterable<QueueOrder> right) =>
      syncJsonEquals(
        [for (final item in left) SyncEntityCodec.orderToFields(item)],
        [for (final item in right) SyncEntityCodec.orderToFields(item)],
      );

  bool _sameProducts(
    Iterable<FinishedProduct> left,
    Iterable<FinishedProduct> right,
  ) =>
      syncJsonEquals(
        [for (final item in left) SyncEntityCodec.productToFields(item)],
        [for (final item in right) SyncEntityCodec.productToFields(item)],
      );

  bool _sameFocus(
    Iterable<FocusSession> left,
    Iterable<FocusSession> right,
  ) =>
      syncJsonEquals(
        [for (final item in left) SyncEntityCodec.focusSessionToFields(item)],
        [for (final item in right) SyncEntityCodec.focusSessionToFields(item)],
      );
}
