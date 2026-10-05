import 'dart:convert';

enum SyncEntityKind {
  order('orders'),
  product('products'),
  nodePreset('node-presets'),
  settings('settings');

  const SyncEntityKind(this.directoryName);
  final String directoryName;
}

enum SyncClockRelation {
  before,
  after,
  equal,
  concurrent,
}

class SyncClock {
  const SyncClock(this.counters);

  final Map<String, int> counters;

  factory SyncClock.empty() => const SyncClock(<String, int>{});

  factory SyncClock.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('同步时钟格式无效。');
    }
    final counters = <String, int>{};
    for (final entry in value.entries) {
      final deviceId = entry.key;
      final count = entry.value;
      if (deviceId is! String || deviceId.isEmpty || count is! int || count < 0) {
        throw const FormatException('同步时钟内容无效。');
      }
      counters[deviceId] = count;
    }
    return SyncClock(Map.unmodifiable(counters));
  }

  Map<String, int> toJson() => <String, int>{...counters};

  SyncClock tick(String deviceId) {
    final next = <String, int>{...counters};
    next[deviceId] = (next[deviceId] ?? 0) + 1;
    return SyncClock(Map.unmodifiable(next));
  }

  SyncClock merge(SyncClock other) {
    final next = <String, int>{...counters};
    for (final entry in other.counters.entries) {
      final current = next[entry.key] ?? 0;
      if (entry.value > current) next[entry.key] = entry.value;
    }
    return SyncClock(Map.unmodifiable(next));
  }

  SyncClockRelation compare(SyncClock other) {
    var less = false;
    var greater = false;
    final devices = <String>{...counters.keys, ...other.counters.keys};

    for (final device in devices) {
      final left = counters[device] ?? 0;
      final right = other.counters[device] ?? 0;
      if (left < right) less = true;
      if (left > right) greater = true;
    }

    if (!less && !greater) return SyncClockRelation.equal;
    if (less && !greater) return SyncClockRelation.before;
    if (!less && greater) return SyncClockRelation.after;
    return SyncClockRelation.concurrent;
  }
}

class SyncFieldValue {
  const SyncFieldValue({
    required this.value,
    required this.clock,
    required this.updatedBy,
  });

  final Object? value;
  final SyncClock clock;
  final String updatedBy;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
        'clock': clock.toJson(),
        'updatedBy': updatedBy,
      };

  factory SyncFieldValue.fromJson(Map<String, dynamic> json) {
    return SyncFieldValue(
      value: json['value'],
      clock: SyncClock.fromJson(json['clock']),
      updatedBy: _requiredString(json, 'updatedBy'),
    );
  }

  SyncFieldValue withClock(SyncClock nextClock) {
    return SyncFieldValue(
      value: value,
      clock: nextClock,
      updatedBy: updatedBy,
    );
  }
}

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.field,
    required this.kind,
    required this.deviceId,
    required this.occurredAt,
    this.delta,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String field;
  final String kind;
  final String deviceId;
  final DateTime occurredAt;
  final num? delta;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'field': field,
        'kind': kind,
        'deviceId': deviceId,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (delta != null) 'delta': delta,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    if (rawDelta != null && rawDelta is! num) {
      throw const FormatException('同步操作增量格式无效。');
    }
    final rawMetadata = json['metadata'];
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const FormatException('同步操作附加数据格式无效。');
    }
    return SyncOperation(
      id: _requiredString(json, 'id'),
      field: _requiredString(json, 'field'),
      kind: _requiredString(json, 'kind'),
      deviceId: _requiredString(json, 'deviceId'),
      occurredAt: _requiredDateTime(json, 'occurredAt'),
      delta: rawDelta as num?,
      metadata: rawMetadata == null
          ? const <String, dynamic>{}
          : rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
    );
  }
}

class SyncConflictCandidate {
  const SyncConflictCandidate({
    required this.value,
    required this.clock,
    required this.deviceId,
  });

  final Object? value;
  final SyncClock clock;
  final String deviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
        'clock': clock.toJson(),
        'deviceId': deviceId,
      };

  factory SyncConflictCandidate.fromField(SyncFieldValue field) {
    return SyncConflictCandidate(
      value: field.value,
      clock: field.clock,
      deviceId: field.updatedBy,
    );
  }

  factory SyncConflictCandidate.fromJson(Map<String, dynamic> json) {
    return SyncConflictCandidate(
      value: json['value'],
      clock: SyncClock.fromJson(json['clock']),
      deviceId: _requiredString(json, 'deviceId'),
    );
  }
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.recordId,
    required this.field,
    required this.candidates,
    required this.mergedClock,
    required this.createdAt,
  });

  final String id;
  final String recordId;
  final String field;
  final List<SyncConflictCandidate> candidates;
  final SyncClock mergedClock;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'recordId': recordId,
        'field': field,
        'candidates': [
          for (final candidate in candidates) candidate.toJson(),
        ],
        'mergedClock': mergedClock.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    final rawCandidates = json['candidates'];
    if (rawCandidates is! List) {
      throw const FormatException('同步冲突候选项格式无效。');
    }
    final candidates = <SyncConflictCandidate>[];
    for (final item in rawCandidates) {
      if (item is! Map) {
        throw const FormatException('同步冲突候选项格式无效。');
      }
      candidates.add(
        SyncConflictCandidate.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }

    return SyncConflict(
      id: _requiredString(json, 'id'),
      recordId: _requiredString(json, 'recordId'),
      field: _requiredString(json, 'field'),
      candidates: candidates,
      mergedClock: SyncClock.fromJson(json['mergedClock']),
      createdAt: _requiredDateTime(json, 'createdAt'),
    );
  }
}

class SyncRecord {
  const SyncRecord({
    this.accountId,
    required this.kind,
    required this.id,
    required this.fields,
    required this.operations,
    required this.conflicts,
  });

  static const int schemaVersion = 1;
  static const String deletedField = '__deleted';

  final String? accountId;
  final SyncEntityKind kind;
  final String id;
  final Map<String, SyncFieldValue> fields;
  final Map<String, SyncOperation> operations;
  final Map<String, SyncConflict> conflicts;

  bool get isDeleted => fields[deletedField]?.value == true;

  factory SyncRecord.bootstrap({
    required SyncEntityKind kind,
    required String id,
    required Map<String, dynamic> values,
    required String deviceId,
  }) {
    final clock = SyncClock.empty().tick(deviceId);
    final fields = <String, SyncFieldValue>{
      for (final entry in values.entries)
        entry.key: SyncFieldValue(
          value: entry.value,
          clock: clock,
          updatedBy: deviceId,
        ),
      deletedField: SyncFieldValue(
        value: false,
        clock: clock,
        updatedBy: deviceId,
      ),
    };
    return SyncRecord(
      accountId: null,
      kind: kind,
      id: id,
      fields: Map.unmodifiable(fields),
      operations: const <String, SyncOperation>{},
      conflicts: const <String, SyncConflict>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        if (accountId != null) 'accountId': accountId,
        'kind': kind.name,
        'id': id,
        'fields': <String, dynamic>{
          for (final entry in fields.entries)
            entry.key: entry.value.toJson(),
        },
        'operations': [
          for (final operation in operations.values) operation.toJson(),
        ],
        'conflicts': [
          for (final conflict in conflicts.values) conflict.toJson(),
        ],
      };

  String encode({bool pretty = false}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(toJson());
  }

  factory SyncRecord.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('同步记录格式无效。');
    }
    final json =
        decoded.map((key, value) => MapEntry(key.toString(), value));
    final schema = json['schemaVersion'];
    if (schema is! int || schema != schemaVersion) {
      throw const FormatException('不支持的同步记录版本。');
    }

    final kindName = _requiredString(json, 'kind');
    final kind = SyncEntityKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => throw const FormatException('未知同步记录类型。'),
    );
    final id = _requiredString(json, 'id');

    final rawFields = json['fields'];
    if (rawFields is! Map) {
      throw const FormatException('同步记录字段格式无效。');
    }
    final fields = <String, SyncFieldValue>{};
    for (final entry in rawFields.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty || entry.value is! Map) {
        throw const FormatException('同步记录字段格式无效。');
      }
      fields[entry.key as String] = SyncFieldValue.fromJson(
        (entry.value as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }

    final rawOperations = json['operations'];
    if (rawOperations is! List) {
      throw const FormatException('同步操作列表格式无效。');
    }
    final operations = <String, SyncOperation>{};
    for (final item in rawOperations) {
      if (item is! Map) {
        throw const FormatException('同步操作格式无效。');
      }
      final operation = SyncOperation.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (operations.containsKey(operation.id)) {
        throw const FormatException('同步操作 ID 重复。');
      }
      operations[operation.id] = operation;
    }

    final rawConflicts = json['conflicts'];
    if (rawConflicts is! List) {
      throw const FormatException('同步冲突列表格式无效。');
    }
    final conflicts = <String, SyncConflict>{};
    for (final item in rawConflicts) {
      if (item is! Map) {
        throw const FormatException('同步冲突格式无效。');
      }
      final conflict = SyncConflict.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (conflicts.containsKey(conflict.id)) {
        throw const FormatException('同步冲突 ID 重复。');
      }
      conflicts[conflict.id] = conflict;
    }

    final rawAccountId = json['accountId'];
    String? accountId;
    if (rawAccountId != null) {
      if (rawAccountId is! String || rawAccountId.isEmpty) {
        throw const FormatException('同步记录账号 ID 格式无效。');
      }
      accountId = rawAccountId;
    }

    return SyncRecord(
      accountId: accountId,
      kind: kind,
      id: id,
      fields: Map.unmodifiable(fields),
      operations: Map.unmodifiable(operations),
      conflicts: Map.unmodifiable(conflicts),
    );
  }

  SyncRecord copyWith({
    String? accountId,
    Map<String, SyncFieldValue>? fields,
    Map<String, SyncOperation>? operations,
    Map<String, SyncConflict>? conflicts,
  }) {
    return SyncRecord(
      accountId: accountId ?? this.accountId,
      kind: kind,
      id: id,
      fields: Map.unmodifiable(fields ?? this.fields),
      operations: Map.unmodifiable(operations ?? this.operations),
      conflicts: Map.unmodifiable(conflicts ?? this.conflicts),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('同步字段 $field 格式无效。');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw FormatException('同步字段 $field 时间格式无效。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('同步字段 $field 时间格式无效。');
  }
  return parsed;
}

bool syncJsonEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is num && right is num) return left == right;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!syncJsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key)) return false;
      if (!syncJsonEquals(left[key], right[key])) return false;
    }
    return true;
  }
  return left == right;
}

String stableJsonSignature(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: normalize(item[key]),
      };
    }
    if (item is List) return <Object?>[for (final value in item) normalize(value)];
    return item;
  }

  return jsonEncode(normalize(value));
}
