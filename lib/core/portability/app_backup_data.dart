import 'dart:convert';

import '../account/account_models.dart';
import '../../features/orders/data/node_presets.dart';
import '../../features/orders/domain/queue_order.dart';
import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/state/focus_store.dart';
import '../../features/orders/state/order_store.dart';
import '../../features/products/domain/finished_product.dart';
import '../../features/products/domain/sale_receipt.dart';
import '../../features/products/state/product_store.dart';

const int currentBackupSchemaVersion = 7;
const String appBackupKind = 'artist_queue_full_backup';

class AppBackupData {
  const AppBackupData({
    required this.exportedAt,
    required this.orders,
    required this.products,
    required this.nodePresets,
    this.focusSessions = const <FocusSession>[],
    this.accountSyncState,
    this.syncRecords,
    this.settings = const <String, dynamic>{},
  });

  final DateTime exportedAt;
  final List<QueueOrder> orders;
  final List<FinishedProduct> products;
  final List<NodePreset> nodePresets;
  final List<FocusSession> focusSessions;

  /// Shared account/device metadata, including the local account name/password.
  /// This stays offline and travels only through the user's own backup/sync flow.
  final AccountSyncState? accountSyncState;

  /// Portable CRDT history included in exported transfer/backup packages.
  ///
  /// Local workspace snapshots omit it; an empty list is a valid complete
  /// history for an empty workspace.
  final List<Map<String, dynamic>>? syncRecords;

  /// App-level and layout settings that travel with a full workspace backup.
  final Map<String, dynamic> settings;

  factory AppBackupData.capture({
    required OrderStore orderStore,
    required ProductStore productStore,
    required NodePresetStore nodePresetStore,
    FocusStore? focusStore,
    AccountSyncState? accountSyncState,
    List<Map<String, dynamic>>? syncRecords,
    Map<String, dynamic> settings = const <String, dynamic>{},
  }) {
    return AppBackupData(
      exportedAt: DateTime.now(),
      orders: [for (final order in orderStore.orders) order],
      products: [for (final product in productStore.products) product],
      nodePresets: [
        for (final preset in nodePresetStore.presets) preset.snapshot(),
      ],
      focusSessions: [for (final session in focusStore?.sessions ?? const <FocusSession>[]) session],
      accountSyncState: accountSyncState,
      syncRecords: syncRecords,
      settings: settings,
    );
  }

  String encode({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': appBackupKind,
      'schemaVersion': currentBackupSchemaVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'payload': <String, dynamic>{
        'orders': [for (final order in orders) _orderToJson(order)],
        'products': [for (final product in products) _productToJson(product)],
        'nodePresets': [
          for (final preset in nodePresets) _presetToJson(preset),
        ],
        'focusSessions': [
          for (final session in focusSessions) session.toJson(),
        ],
        if (accountSyncState != null) 'accountSync': accountSyncState!.toJson(),
        if (syncRecords != null)
          'syncRecords': [
            for (final record in syncRecords!)
              Map<String, dynamic>.from(record),
          ],
        'settings': settings,
      },
    };
  }

  factory AppBackupData.decode(String source) {
    final decoded = jsonDecode(source);
    final root = _asMap(decoded, '备份根节点');

    if (root['kind'] != appBackupKind) {
      throw const FormatException('这不是本应用导出的完整备份文件。');
    }

    final schema = _asInt(root['schemaVersion'], 'schemaVersion');
    if (schema < 1 || schema > currentBackupSchemaVersion) {
      throw FormatException(
        schema > currentBackupSchemaVersion
            ? '备份版本过新（schema $schema），请先更新 App 后再导入。'
            : '不支持的备份版本：$schema。',
      );
    }

    final exportedAt = DateTime.tryParse(
      _asString(root['exportedAt'], 'exportedAt'),
    );
    if (exportedAt == null) {
      throw const FormatException('备份导出时间无效。');
    }

    final rawPayload = _asMap(root['payload'], 'payload');
    final payload = schema == currentBackupSchemaVersion
        ? rawPayload
        : _normalizeLegacyPayload(rawPayload);
    final orderList = _asList(payload['orders'], 'orders');
    final productList = _asList(payload['products'], 'products');
    final presetList = _asList(payload['nodePresets'], 'nodePresets');
    final focusList = _asList(
      payload['focusSessions'] ?? <dynamic>[],
      'focusSessions',
    );

    AccountSyncState? accountSyncState;
    if (payload.containsKey('accountSync')) {
      final rawAccountSync = payload['accountSync'];
      if (rawAccountSync is! Map) {
        throw const FormatException('accountSync 格式无效。');
      }
      accountSyncState = AccountSyncState.fromCompatibleJson(
        rawAccountSync.map((key, value) => MapEntry(key.toString(), value)),
        allowMissingPassword: schema < currentBackupSchemaVersion,
      );
    }

    List<Map<String, dynamic>>? syncRecords;
    if (payload.containsKey('syncRecords')) {
      final rawSyncRecords = _asList(payload['syncRecords'], 'syncRecords');
      syncRecords = <Map<String, dynamic>>[
        for (final item in rawSyncRecords)
          Map<String, dynamic>.from(_asMap(item, 'syncRecord')),
      ];
    }

    final settings = payload['settings'] == null
        ? <String, dynamic>{}
        : _asMap(payload['settings'], 'settings');

    final orders = <QueueOrder>[
      for (final item in orderList) _orderFromJson(_asMap(item, 'order')),
    ];
    final products = <FinishedProduct>[
      for (final item in productList) _productFromJson(_asMap(item, 'product')),
    ];
    final nodePresets = <NodePreset>[
      for (final item in presetList)
        _presetFromJson(_asMap(item, 'nodePreset')),
    ];
    final focusSessions = <FocusSession>[
      for (final item in focusList)
        FocusSession.fromJson(
          _asMap(item, 'focusSession').map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
    ];

    _requireUniqueIds(orders.map((item) => item.id), '排单');
    _requireUniqueIds(products.map((item) => item.id), '成品');
    _requireUniqueIds(nodePresets.map((item) => item.id), '节点预设');
    _requireUniqueIds(focusSessions.map((item) => item.id), '专注记录');

    return AppBackupData(
      exportedAt: exportedAt,
      orders: orders,
      products: products,
      nodePresets: nodePresets,
      focusSessions: focusSessions,
      accountSyncState: accountSyncState,
      syncRecords: syncRecords,
      settings: settings,
    );
  }

  void restoreInto({
    required OrderStore orderStore,
    required ProductStore productStore,
    required NodePresetStore nodePresetStore,
    FocusStore? focusStore,
  }) {
    nodePresetStore.replaceAll(nodePresets);
    orderStore.replaceAll(orders);
    productStore.replaceAll(products);
    focusStore?.replaceAll(focusSessions);
  }
}

Map<String, dynamic> _normalizeLegacyPayload(Map<String, dynamic> payload) {
  final normalized = <String, dynamic>{...payload};
  final rawOrders = payload['orders'];
  if (rawOrders is List) {
    normalized['orders'] = [
      for (final item in rawOrders)
        item is Map
            ? _normalizeLegacyOrder(
                item.map((key, value) => MapEntry(key.toString(), value)),
              )
            : item,
    ];
  }
  final rawProducts = payload['products'];
  if (rawProducts is List) {
    normalized['products'] = [
      for (final item in rawProducts)
        item is Map
            ? _normalizeLegacyProduct(
                item.map((key, value) => MapEntry(key.toString(), value)),
              )
            : item,
    ];
  }
  final rawPresets = payload['nodePresets'];
  if (rawPresets is List) {
    normalized['nodePresets'] = [
      for (final item in rawPresets)
        item is Map
            ? _normalizeLegacyPreset(
                item.map((key, value) => MapEntry(key.toString(), value)),
              )
            : item,
    ];
  }
  normalized['focusSessions'] ??= <dynamic>[];
  normalized['settings'] ??= <String, dynamic>{};
  return normalized;
}

Map<String, dynamic> _normalizeLegacyOrder(Map<String, dynamic> source) {
  final json = <String, dynamic>{...source};
  final platform = _enumByName(
    CommissionPlatform.values,
    _asString(json['platform'], 'order.platform'),
    'order.platform',
  );
  json['clientName'] ??= '';
  json['currentNodeId'] ??= notStartedNodeId;
  final progress = json['currentNodeProgress'];
  json['currentNodeProgress'] = progress is int
      ? progress.clamp(0, 100)
      : progress ?? 0;
  json['price'] ??= 0;
  json['feeEnabled'] ??= platform.defaultFeeEnabled;
  json['huajiaLoveLevel'] ??= HuajiaLoveLevel.none.name;
  json['onlinePercent'] ??= 100;
  json['supplementAmount'] ??= 0;
  json['supplementFeeEnabled'] ??= platform.defaultAdjustmentFeeEnabled;
  json['deductionAmount'] ??= 0;
  json['deductionFeeEnabled'] ??= platform.defaultAdjustmentFeeEnabled;
  json['description'] ??= '';
  json['tags'] ??= <dynamic>[];
  json['defaultOrder'] ??= 0;
  json['referenceImages'] ??= <dynamic>[];
  json['isArchived'] ??= false;
  json['isPinned'] ??= false;
  json['nodePresetSnapshot'] = _normalizeLegacyPreset(
    _asMap(json['nodePresetSnapshot'], 'order.nodePresetSnapshot'),
  );
  return json;
}

Map<String, dynamic> _normalizeLegacyProduct(Map<String, dynamic> source) {
  final json = <String, dynamic>{...source};
  final platform = _enumByName(
    CommissionPlatform.values,
    _asString(json['platform'], 'product.platform'),
    'product.platform',
  );
  json['price'] ??= 0;
  json['feeEnabled'] ??= platform.defaultFeeEnabled;
  json['huajiaLoveLevel'] ??= HuajiaLoveLevel.none.name;
  json['onlinePercent'] ??= 100;
  json['supplementAmount'] ??= 0;
  json['supplementFeeEnabled'] ??= platform.defaultAdjustmentFeeEnabled;
  json['deductionAmount'] ??= 0;
  json['deductionFeeEnabled'] ??= platform.defaultAdjustmentFeeEnabled;
  json['description'] ??= '';
  json['referenceImages'] ??= <dynamic>[];
  json['defaultOrder'] ??= 0;
  json['soldCount'] ??= 0;
  json['saleRecords'] ??= <dynamic>[];
  json['saleReceipts'] ??= <dynamic>[];
  json['isArchived'] ??= false;
  json['isPinned'] ??= false;
  return json;
}

Map<String, dynamic> _normalizeLegacyPreset(Map<String, dynamic> source) {
  final json = <String, dynamic>{...source};
  final rawNodes = json['nodes'];
  if (rawNodes is List) {
    json['nodes'] = [
      for (final item in rawNodes)
        item is Map
            ? <String, dynamic>{
                ...item.map((key, value) => MapEntry(key.toString(), value)),
                'iconKey': item['iconKey'] ?? 'circle',
                'colorValue': item['colorValue'] ?? 0xFF7A8793,
                'builtIn': item['builtIn'] ?? false,
              }
            : item,
    ];
  }
  return json;
}

Map<String, dynamic> _orderToJson(QueueOrder order) {
  return <String, dynamic>{
    'id': order.id,
    'platform': order.platform.name,
    'title': order.title,
    'clientName': order.clientName,
    'deadline': order.deadline?.toUtc().toIso8601String(),
    'nodePresetId': order.nodePresetId,
    'nodePresetSnapshot': _presetToJson(order.nodePresetSnapshot),
    'currentNodeId': order.currentNodeId,
    'currentNodeProgress': order.currentNodeProgress,
    'price': order.price,
    'feeEnabled': order.feeEnabled,
    'huajiaLoveLevel': order.huajiaLoveLevel.name,
    'onlinePercent': order.onlinePercent,
    'supplementAmount': order.supplementAmount,
    'supplementFeeEnabled': order.supplementFeeEnabled,
    'deductionAmount': order.deductionAmount,
    'deductionFeeEnabled': order.deductionFeeEnabled,
    'description': order.description,
    'tags': order.tags,
    if (order.defaultOrder != 0) 'defaultOrder': order.defaultOrder,
    'referenceImages': [
      for (final image in order.referenceImages)
        <String, dynamic>{
          'id': image.id,
          'fileName': image.fileName,
          'relativePath': image.relativePath,
          'addedAt': image.addedAt.toUtc().toIso8601String(),
          'sizeBytes': image.sizeBytes,
        },
    ],
    'completedAt': order.completedAt?.toUtc().toIso8601String(),
    'settledAt': order.settledAt?.toUtc().toIso8601String(),
    'settledIncome': order.settledIncome,
    'archiveOutcome': order.archiveOutcome?.name,
    'settlementNodeId': order.settlementNodeId,
    'customRefundAmount': order.customRefundAmount,
    'isArchived': order.isArchived,
    'isPinned': order.isPinned,
  };
}

QueueOrder _orderFromJson(Map<String, dynamic> json) {
  final id = _asString(json['id'], 'order.id');
  final platform = _enumByName(
    CommissionPlatform.values,
    _asString(json['platform'], 'order.platform'),
    'order.platform',
  );

  final currentNodeProgress = _asInt(
    json['currentNodeProgress'],
    'order.currentNodeProgress',
  );
  if (currentNodeProgress < 0 || currentNodeProgress > 100) {
    throw FormatException(
      'order.currentNodeProgress 超出范围：$currentNodeProgress',
    );
  }

  return QueueOrder(
    id: id,
    platform: platform,
    title: _asString(json['title'], 'order.title'),
    clientName: _asText(json['clientName'], 'order.clientName'),
    deadline: _asNullableDateTime(json['deadline'], 'order.deadline'),
    nodePresetId: _asString(json['nodePresetId'], 'order.nodePresetId'),
    nodePresetSnapshot: _presetFromJson(
      _asMap(json['nodePresetSnapshot'], 'order.nodePresetSnapshot'),
    ),
    currentNodeId: _asString(json['currentNodeId'], 'order.currentNodeId'),
    currentNodeProgress: currentNodeProgress,
    price: _asDouble(json['price'], 'order.price'),
    feeEnabled: _asBool(json['feeEnabled'], 'order.feeEnabled'),
    huajiaLoveLevel: _enumByName(
      HuajiaLoveLevel.values,
      _asString(json['huajiaLoveLevel'], 'order.huajiaLoveLevel'),
      'order.huajiaLoveLevel',
    ),
    onlinePercent: _asDouble(json['onlinePercent'], 'order.onlinePercent'),
    supplementAmount: _asDouble(
      json['supplementAmount'],
      'order.supplementAmount',
    ),
    supplementFeeEnabled: _asBool(
      json['supplementFeeEnabled'],
      'order.supplementFeeEnabled',
    ),
    deductionAmount: _asDouble(
      json['deductionAmount'],
      'order.deductionAmount',
    ),
    deductionFeeEnabled: _asBool(
      json['deductionFeeEnabled'],
      'order.deductionFeeEnabled',
    ),
    description: _asText(json['description'], 'order.description'),
    tags: normalizeOrderTags(<String>[
      for (final item in _asList(json['tags'] ?? <dynamic>[], 'order.tags'))
        _asString(item, 'order.tag'),
    ]),
    defaultOrder: json['defaultOrder'] == null
        ? 0
        : _asInt(json['defaultOrder'], 'order.defaultOrder'),
    referenceImages: json['referenceImages'] == null
        ? const <OrderReferenceImage>[]
        : <OrderReferenceImage>[
            for (final item in _asList(
              json['referenceImages'],
              'order.referenceImages',
            ))
              _referenceImageFromJson(
                _asMap(item, 'order.referenceImage'),
              ),
          ],
    completedAt: _asNullableDateTime(json['completedAt'], 'order.completedAt'),
    settledAt: _asNullableDateTime(json['settledAt'], 'order.settledAt'),
    settledIncome: _asNullableDouble(
      json['settledIncome'],
      'order.settledIncome',
    ),
    archiveOutcome: _archiveOutcomeFromJson(json['archiveOutcome']),
    settlementNodeId: _asNullableString(
      json['settlementNodeId'],
      'order.settlementNodeId',
    ),
    customRefundAmount: _asNullableDouble(
      json['customRefundAmount'],
      'order.customRefundAmount',
    ),
    isArchived: _asBool(json['isArchived'], 'order.isArchived'),
    isPinned: _asBool(json['isPinned'], 'order.isPinned'),
  );
}

OrderReferenceImage _referenceImageFromJson(
  Map<String, dynamic> json,
) {
  final sizeBytes = _asInt(json['sizeBytes'], 'order.referenceImage.sizeBytes');
  if (sizeBytes < 0) {
    throw const FormatException('参考图文件大小无效。');
  }

  return OrderReferenceImage(
    id: _asString(json['id'], 'order.referenceImage.id'),
    fileName: _asText(json['fileName'], 'order.referenceImage.fileName'),
    relativePath: _asString(
      json['relativePath'],
      'order.referenceImage.relativePath',
    ),
    addedAt: _asDateTime(json['addedAt'], 'order.referenceImage.addedAt'),
    sizeBytes: sizeBytes,
  );
}

Map<String, dynamic> _productToJson(FinishedProduct product) {
  return <String, dynamic>{
    'id': product.id,
    'title': product.title,
    'platform': product.platform.name,
    'saleType': product.saleType.name,
    'price': product.price,
    'feeEnabled': product.feeEnabled,
    'huajiaLoveLevel': product.huajiaLoveLevel.name,
    'onlinePercent': product.onlinePercent,
    'supplementAmount': product.supplementAmount,
    'supplementFeeEnabled': product.supplementFeeEnabled,
    'deductionAmount': product.deductionAmount,
    'deductionFeeEnabled': product.deductionFeeEnabled,
    'description': product.description,
    'referenceImages': [
      for (final image in product.referenceImages)
        <String, dynamic>{
          'id': image.id,
          'fileName': image.fileName,
          'relativePath': image.relativePath,
          'addedAt': image.addedAt.toUtc().toIso8601String(),
          'sizeBytes': image.sizeBytes,
        },
    ],
    if (product.defaultOrder != 0) 'defaultOrder': product.defaultOrder,
    'soldCount': product.soldCount,
    'saleRecords': [
      for (final soldAt in product.saleRecords)
        soldAt.toUtc().toIso8601String(),
    ],
    'saleReceipts': [
      for (final receipt in product.accountedSales) receipt.toJson(),
    ],
    'archivedAt': product.archivedAt?.toUtc().toIso8601String(),
    'isArchived': product.isArchived,
    'isPinned': product.isPinned,
  };
}

FinishedProduct _productFromJson(Map<String, dynamic> json) {
  final id = _asString(json['id'], 'product.id');
  final platform = _enumByName(
    CommissionPlatform.values,
    _asString(json['platform'], 'product.platform'),
    'product.platform',
  );

  return FinishedProduct(
    id: id,
    title: _asString(json['title'], 'product.title'),
    platform: platform,
    saleType: _enumByName(
      ProductSaleType.values,
      _asString(json['saleType'], 'product.saleType'),
      'product.saleType',
    ),
    price: _asDouble(json['price'], 'product.price'),
    feeEnabled: _asBool(json['feeEnabled'], 'product.feeEnabled'),
    huajiaLoveLevel: _enumByName(
      HuajiaLoveLevel.values,
      _asString(json['huajiaLoveLevel'], 'product.huajiaLoveLevel'),
      'product.huajiaLoveLevel',
    ),
    onlinePercent: _asDouble(json['onlinePercent'], 'product.onlinePercent'),
    supplementAmount: _asDouble(
      json['supplementAmount'],
      'product.supplementAmount',
    ),
    supplementFeeEnabled: _asBool(
      json['supplementFeeEnabled'],
      'product.supplementFeeEnabled',
    ),
    deductionAmount: _asDouble(
      json['deductionAmount'],
      'product.deductionAmount',
    ),
    deductionFeeEnabled: _asBool(
      json['deductionFeeEnabled'],
      'product.deductionFeeEnabled',
    ),
    description: _asText(json['description'], 'product.description'),
    referenceImages: <OrderReferenceImage>[
      for (final item in _asList(
        json['referenceImages'] ?? <dynamic>[],
        'product.referenceImages',
      ))
        _referenceImageFromJson(_asMap(item, 'product.referenceImage')),
    ],
    defaultOrder: json['defaultOrder'] == null
        ? 0
        : _asInt(json['defaultOrder'], 'product.defaultOrder'),
    soldCount: _asInt(json['soldCount'], 'product.soldCount'),
    saleRecords: [
      for (final item in _asList(json['saleRecords'], 'product.saleRecords'))
        _asDateTime(item, 'product.saleRecords'),
    ],
    saleReceipts: [
      for (final item in _asList(
        json['saleReceipts'] ?? <dynamic>[],
        'product.saleReceipts',
      ))
        SaleReceipt.fromJson(_asMap(item, 'product.saleReceipt')),
    ],
    archivedAt: _asNullableDateTime(json['archivedAt'], 'product.archivedAt'),
    isArchived: _asBool(json['isArchived'], 'product.isArchived'),
    isPinned: _asBool(json['isPinned'], 'product.isPinned'),
  );
}

Map<String, dynamic> _presetToJson(NodePreset preset) {
  return <String, dynamic>{
    'id': preset.id,
    'name': preset.name,
    'nodes': [for (final node in preset.nodes) _nodeToJson(node)],
  };
}

NodePreset _presetFromJson(Map<String, dynamic> json) {
  final nodes = _asList(
    json['nodes'],
    'nodePreset.nodes',
  ).map((item) => _nodeFromJson(_asMap(item, 'node'))).toList();

  if (nodes.isEmpty) {
    throw const FormatException('节点预设不能为空。');
  }
  _requireUniqueIds(nodes.map((item) => item.id), '节点');

  return NodePreset(
    id: _asString(json['id'], 'nodePreset.id'),
    name: _asString(json['name'], 'nodePreset.name'),
    nodes: nodes,
  );
}

Map<String, dynamic> _nodeToJson(NodeDefinition node) {
  return <String, dynamic>{
    'id': node.id,
    'name': node.name,
    'iconKey': node.iconKey,
    'colorValue': node.colorValue,
    'progressPercent': node.progressPercent,
    'builtIn': node.builtIn,
  };
}

NodeDefinition _nodeFromJson(Map<String, dynamic> json) {
  final progress = _asInt(json['progressPercent'], 'node.progressPercent');
  if (progress < 0 || progress > 100) {
    throw FormatException('节点百分比超出范围：$progress');
  }

  return NodeDefinition(
    id: _asString(json['id'], 'node.id'),
    name: _asString(json['name'], 'node.name'),
    iconKey: _asString(json['iconKey'], 'node.iconKey'),
    colorValue: _asInt(json['colorValue'], 'node.colorValue'),
    progressPercent: progress,
    builtIn: _asBool(json['builtIn'], 'node.builtIn'),
  );
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$field 格式无效。');
}

List<dynamic> _asList(Object? value, String field) {
  if (value is List) return value;
  throw FormatException('$field 格式无效。');
}

String _asString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field 缺失或格式无效。');
}

String _asText(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 缺失或格式无效。');
}

String? _asNullableString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$field 格式无效。');
}

int _asInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field 缺失或格式无效。');
}

double _asDouble(Object? value, String field) {
  if (value is num) return value.toDouble();
  throw FormatException('$field 缺失或格式无效。');
}

double? _asNullableDouble(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('$field 格式无效。');
}

bool _asBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('$field 缺失或格式无效。');
}

DateTime _asDateTime(Object? value, String field) {
  final parsed = DateTime.tryParse(_asString(value, field));
  if (parsed == null) throw FormatException('$field 时间格式无效。');
  return parsed.toLocal();
}

DateTime? _asNullableDateTime(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field 时间格式无效。');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$field 时间格式无效。');
  return parsed.toLocal();
}

OrderArchiveOutcome? _archiveOutcomeFromJson(Object? value) {
  final name = _asNullableString(value, 'order.archiveOutcome');
  if (name == null) return null;
  return _enumByName(OrderArchiveOutcome.values, name, 'order.archiveOutcome');
}

T _enumByName<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$field 包含未知值：$name');
}

void _requireUniqueIds(Iterable<String> ids, String label) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      throw FormatException('$label ID 重复：$id');
    }
  }
}
