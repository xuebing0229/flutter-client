import 'dart:convert';

import 'sync_models.dart';

class SyncMergeEngine {
  int _operationSequence = 0;

  static const Set<String> additiveFields = <String>{
    'supplementAmount',
    'deductionAmount',
    'soldCount',
  };

  SyncRecord merge(SyncRecord left, SyncRecord right) {
    if (left.kind != right.kind || left.id != right.id) {
      throw const FormatException('不能合并不同对象的同步记录。');
    }
    if (left.accountId != null &&
        right.accountId != null &&
        left.accountId != right.accountId) {
      throw const FormatException('不能合并不同账号的同步记录。');
    }
    final accountId = left.accountId ?? right.accountId;

    final fields = <String, SyncFieldValue>{};
    final generatedConflicts = <String, SyncConflict>{};
    final fieldNames = <String>{...left.fields.keys, ...right.fields.keys};

    for (final fieldName in fieldNames) {
      final a = left.fields[fieldName];
      final b = right.fields[fieldName];
      if (a == null) {
        fields[fieldName] = b!;
        continue;
      }
      if (b == null) {
        fields[fieldName] = a;
        continue;
      }

      final relation = a.clock.compare(b.clock);
      switch (relation) {
        case SyncClockRelation.before:
          fields[fieldName] = b;
        case SyncClockRelation.after:
          fields[fieldName] = a;
        case SyncClockRelation.equal:
          if (syncJsonEquals(a.value, b.value)) {
            fields[fieldName] = SyncFieldValue(
              value: a.value,
              clock: a.clock.merge(b.clock),
              updatedBy: _deterministicDevice(a.updatedBy, b.updatedBy),
            );
          } else {
            final conflict = _createConflict(left.id, fieldName, a, b);
            generatedConflicts[conflict.id] = conflict;
            fields[fieldName] = _deterministicField(a, b).withClock(
              a.clock.merge(b.clock),
            );
          }
        case SyncClockRelation.concurrent:
          if (syncJsonEquals(a.value, b.value)) {
            fields[fieldName] = SyncFieldValue(
              value: a.value,
              clock: a.clock.merge(b.clock),
              updatedBy: _deterministicDevice(a.updatedBy, b.updatedBy),
            );
          } else {
            final conflict = _createConflict(left.id, fieldName, a, b);
            generatedConflicts[conflict.id] = conflict;
            fields[fieldName] = _deterministicField(a, b).withClock(
              a.clock.merge(b.clock),
            );
          }
      }
    }

    final deletionConflict = _deletionVsEditConflict(
      left: left,
      right: right,
      existingConflicts: generatedConflicts,
    );
    if (deletionConflict != null) {
      generatedConflicts[deletionConflict.id] = deletionConflict;
    }

    final operations = <String, SyncOperation>{...left.operations};
    for (final entry in right.operations.entries) {
      final existing = operations[entry.key];
      if (existing == null ||
          (!existing.compacted && entry.value.compacted)) {
        // A compacted marker always wins over the full historical operation
        // with the same ID. This prevents a stale peer from re-applying an
        // operation that has already been folded into the base snapshot.
        operations[entry.key] = entry.value;
      }
    }

    final conflicts = <String, SyncConflict>{
      ...left.conflicts,
      ...right.conflicts,
      ...generatedConflicts,
    };

    conflicts.removeWhere((_, conflict) {
      final current = fields[conflict.field];
      if (current == null) return true;
      return current.clock.compare(conflict.mergedClock) ==
          SyncClockRelation.after;
    });

    return SyncRecord(
      accountId: accountId,
      kind: left.kind,
      id: left.id,
      fields: fields,
      operations: operations,
      conflicts: conflicts,
    );
  }

  SyncRecord applyLocalSnapshot({
    required SyncRecord record,
    required Map<String, dynamic> previousValues,
    required Map<String, dynamic> nextValues,
    required String deviceId,
  }) {
    final fields = <String, SyncFieldValue>{...record.fields};
    final operations = <String, SyncOperation>{...record.operations};
    final conflicts = <String, SyncConflict>{...record.conflicts};
    final changed = <String>{...previousValues.keys, ...nextValues.keys}
      ..remove('id');

    final deletedField = fields[SyncRecord.deletedField];
    if (deletedField?.value == true) {
      fields[SyncRecord.deletedField] = SyncFieldValue(
        value: false,
        clock: deletedField!.clock.tick(deviceId),
        updatedBy: deviceId,
      );
      _clearFieldConflicts(conflicts, SyncRecord.deletedField);
    }

    for (final field in changed) {
      final previous = previousValues[field];
      final next = nextValues[field];
      if (syncJsonEquals(previous, next)) continue;

      if (field == 'referenceImages' &&
          previous is List &&
          next is List) {
        if (!fields.containsKey(field)) {
          fields[field] = SyncFieldValue(
            value: List<dynamic>.from(previous),
            clock: SyncClock.empty().tick(deviceId),
            updatedBy: deviceId,
          );
        }

        final metadata = _referenceImageDelta(previous, next);
        if (metadata.isNotEmpty) {
          final operation = _operation(
            field: field,
            kind: 'reference-image-delta',
            deviceId: deviceId,
            metadata: metadata,
          );
          operations[operation.id] = operation;
        }
        _clearFieldConflicts(conflicts, field);
        continue;
      }

      if (field == 'soldCount' &&
          nextValues['saleType'] == 'single' &&
          previous is num &&
          next is num) {
        final current = fields[field];
        final baseClock = current?.clock ?? SyncClock.empty();
        fields[field] = SyncFieldValue(
          value: next.clamp(0, 1),
          clock: baseClock.tick(deviceId),
          updatedBy: deviceId,
        );
        _clearFieldConflicts(conflicts, field);

        final operation = _operation(
          field: field,
          kind: 'single-sale-state',
          deviceId: deviceId,
          metadata: <String, dynamic>{
            'soldCount': next.clamp(0, 1),
          },
        );
        operations[operation.id] = operation;
        continue;
      }

      if (additiveFields.contains(field) &&
          previous is num &&
          next is num) {
        final delta = next - previous;
        if (delta != 0) {
          final metadata = <String, dynamic>{};
          if (field == 'soldCount') {
            metadata.addAll(
              _saleRecordDelta(
                previousValues['saleRecords'],
                nextValues['saleRecords'],
              ),
            );
          }
          final operation = _operation(
            field: field,
            kind: field == 'soldCount' ? 'sale-delta' : 'amount-delta',
            deviceId: deviceId,
            delta: delta,
            metadata: metadata,
          );
          operations[operation.id] = operation;
        }
        continue;
      }

      if (field == 'saleRecords' &&
          nextValues['saleType'] != 'single' &&
          !syncJsonEquals(
            previousValues['soldCount'],
            nextValues['soldCount'],
          )) {
        continue;
      }

      if (field == 'currentNodeProgress' &&
          previous is num &&
          next is num &&
          syncJsonEquals(
            previousValues['currentNodeId'],
            nextValues['currentNodeId'],
          )) {
        final operation = _operation(
          field: field,
          kind: 'progress-delta',
          deviceId: deviceId,
          delta: next - previous,
          metadata: <String, dynamic>{
            'nodeId': nextValues['currentNodeId'],
          },
        );
        operations[operation.id] = operation;
        continue;
      }

      final current = fields[field];
      final baseClock = current?.clock ?? SyncClock.empty();
      fields[field] = SyncFieldValue(
        value: next,
        clock: baseClock.tick(deviceId),
        updatedBy: deviceId,
      );
      _clearFieldConflicts(conflicts, field);

      if (field == 'currentNodeId') {
        final operation = _operation(
          field: field,
          kind: 'node-transition',
          deviceId: deviceId,
          metadata: <String, dynamic>{
            'from': previous,
            'to': next,
          },
        );
        operations[operation.id] = operation;
      }
    }

    return record.copyWith(
      fields: fields,
      operations: operations,
      conflicts: conflicts,
    );
  }

  SyncRecord markDeleted(
    SyncRecord record, {
    required String deviceId,
  }) {
    final fields = <String, SyncFieldValue>{...record.fields};
    final conflicts = <String, SyncConflict>{...record.conflicts};
    final current = fields[SyncRecord.deletedField];
    if (current?.value == true) return record;

    fields[SyncRecord.deletedField] = SyncFieldValue(
      value: true,
      clock: (current?.clock ?? SyncClock.empty()).tick(deviceId),
      updatedBy: deviceId,
    );
    _clearFieldConflicts(conflicts, SyncRecord.deletedField);

    final operation = _operation(
      field: SyncRecord.deletedField,
      kind: 'delete',
      deviceId: deviceId,
    );
    final operations = <String, SyncOperation>{
      ...record.operations,
      operation.id: operation,
    };

    return record.copyWith(
      fields: fields,
      operations: operations,
      conflicts: conflicts,
    );
  }

  SyncRecord compactAcknowledgedOperations(
    SyncRecord record, {
    required String deviceId,
  }) {
    if (record.isDeleted ||
        record.conflicts.isNotEmpty ||
        !record.operations.values.any((operation) => !operation.compacted)) {
      return record;
    }

    final materialized = _materialize(record);
    if (materialized == null) return record;

    final fields = <String, SyncFieldValue>{...record.fields};
    final foldFields = <String>{};

    for (final operation in record.operations.values) {
      if (operation.compacted) continue;
      switch (operation.kind) {
        case 'amount-delta':
          foldFields.add(operation.field);
        case 'sale-delta':
        case 'single-sale-state':
          foldFields
            ..add('soldCount')
            ..add('saleRecords');
        case 'progress-delta':
          foldFields.add('currentNodeProgress');
        case 'reference-image-delta':
          foldFields.add('referenceImages');
      }
    }

    for (final field in foldFields) {
      if (!materialized.containsKey(field)) continue;
      final current = fields[field];
      fields[field] = SyncFieldValue(
        value: materialized[field],
        clock: (current?.clock ?? SyncClock.empty()).tick(deviceId),
        updatedBy: deviceId,
      );
    }

    final operations = <String, SyncOperation>{
      for (final entry in record.operations.entries)
        entry.key: entry.value.compacted
            ? entry.value
            : SyncOperation(
                id: entry.value.id,
                field: entry.value.field,
                kind: entry.value.kind,
                deviceId: entry.value.deviceId,
                occurredAt: entry.value.occurredAt,
                compacted: true,
              ),
    };

    return record.copyWith(
      fields: fields,
      operations: operations,
    );
  }

  SyncRecord resolveConflict({
    required SyncRecord record,
    required String conflictId,
    required int candidateIndex,
    required String deviceId,
  }) {
    final conflict = record.conflicts[conflictId];
    if (conflict == null) return record;
    if (candidateIndex < 0 ||
        candidateIndex >= conflict.candidates.length) {
      throw RangeError.index(
        candidateIndex,
        conflict.candidates,
        'candidateIndex',
      );
    }

    final candidate = conflict.candidates[candidateIndex];
    final fields = <String, SyncFieldValue>{...record.fields};
    fields[conflict.field] = SyncFieldValue(
      value: candidate.value,
      clock: conflict.mergedClock.tick(deviceId),
      updatedBy: deviceId,
    );

    final conflicts = <String, SyncConflict>{...record.conflicts}
      ..removeWhere((_, item) => item.field == conflict.field);

    final operation = _operation(
      field: conflict.field,
      kind: 'conflict-resolution',
      deviceId: deviceId,
      metadata: <String, dynamic>{
        'conflictId': conflictId,
        'selectedDeviceId': candidate.deviceId,
      },
    );
    final operations = <String, SyncOperation>{
      ...record.operations,
      operation.id: operation,
    };

    return record.copyWith(
      fields: fields,
      operations: operations,
      conflicts: conflicts,
    );
  }

  Map<String, dynamic>? materialize(SyncRecord record) {
    return _materialize(record);
  }

  Map<String, dynamic>? _materialize(
    SyncRecord record, {
    bool ignoreDeletion = false,
  }) {
    if (record.isDeleted && !ignoreDeletion) return null;

    final values = <String, dynamic>{
      for (final entry in record.fields.entries)
        if (entry.key != SyncRecord.deletedField)
          entry.key: entry.value.value,
    };

    for (final field in additiveFields) {
      if (field == 'soldCount') continue;
      final base = values[field];
      if (base is! num) continue;
      num value = base;
      for (final operation in record.operations.values) {
        if (!operation.compacted &&
            operation.field == field &&
            operation.delta != null) {
          value += operation.delta!;
        }
      }
      values[field] = value.toDouble();
    }

    final baseProgress = values['currentNodeProgress'];
    final currentNodeId = values['currentNodeId'];
    if (baseProgress is num && currentNodeId is String) {
      num progress = baseProgress;
      for (final operation in record.operations.values) {
        if (operation.compacted ||
            operation.kind != 'progress-delta' ||
            operation.field != 'currentNodeProgress' ||
            operation.delta == null ||
            operation.metadata['nodeId'] != currentNodeId) {
          continue;
        }
        progress += operation.delta!;
      }
      values['currentNodeProgress'] = progress.round().clamp(0, 100);
    }

    final rawReferenceImages = values['referenceImages'];
    final imageOperations = record.operations.values
        .where(
          (operation) =>
              !operation.compacted &&
              operation.kind == 'reference-image-delta',
        )
        .toList()
      ..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    if (rawReferenceImages is List || imageOperations.isNotEmpty) {
      final images = <String, Map<String, dynamic>>{};
      for (final item in rawReferenceImages is List
          ? rawReferenceImages
          : const <dynamic>[]) {
        if (item is! Map) continue;
        final mapped = item.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final id = mapped['id'];
        if (id is String && id.isNotEmpty) {
          images[id] = mapped;
        }
      }

      for (final operation in imageOperations) {
        final added = operation.metadata['added'];
        if (added is List) {
          for (final item in added) {
            if (item is! Map) continue;
            final mapped = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final id = mapped['id'];
            if (id is String && id.isNotEmpty) {
              images.putIfAbsent(id, () => mapped);
            }
          }
        }

        final removed = operation.metadata['removed'];
        if (removed is List) {
          for (final item in removed) {
            if (item is String) images.remove(item);
          }
        }
      }

      values['referenceImages'] = images.values.toList(growable: false);
    }

    final rawSaleRecords = values['saleRecords'];
    if (rawSaleRecords is List) {
      final records = <String>[
        for (final item in rawSaleRecords)
          if (item is String) item,
      ];

      if (values['saleType'] == 'single') {
        final soldCount = values['soldCount'];
        final sold = soldCount is num && soldCount > 0;
        records.sort();
        if (!sold) {
          records.clear();
        } else if (records.length > 1) {
          records.removeRange(1, records.length);
        }
        values['soldCount'] = sold ? 1 : 0;
        values['saleRecords'] = records;
      } else {
        final saleOperations = record.operations.values
            .where(
              (operation) =>
                  !operation.compacted && operation.kind == 'sale-delta',
            )
            .toList()
          ..sort((a, b) {
            final byTime = a.occurredAt.compareTo(b.occurredAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });

        for (final operation in saleOperations) {
          final added = operation.metadata['added'];
          if (added is List) {
            for (final item in added) {
              if (item is String) records.add(item);
            }
          }

          final removed = operation.metadata['removed'];
          if (removed is List) {
            for (final item in removed) {
              if (item is! String) continue;
              final index = records.indexOf(item);
              if (index != -1) records.removeAt(index);
            }
          }
        }

        values['soldCount'] = records.length;
        values['saleRecords'] = records;
      }
    }

    return values;
  }

  Map<String, dynamic>? materializeKeepingLocalConflicts(
    SyncRecord record,
    Map<String, dynamic>? currentLocal,
  ) {
    if (currentLocal == null) return materialize(record);

    final hasDeletionConflict = record.conflicts.values.any(
      (conflict) =>
          conflict.field == SyncRecord.deletedField &&
          conflict.candidates.any((candidate) => candidate.value == false),
    );
    final values = _materialize(
      record,
      ignoreDeletion: hasDeletionConflict,
    );
    if (values == null) return null;

    for (final conflict in record.conflicts.values) {
      if (conflict.field == SyncRecord.deletedField) continue;
      final local = currentLocal[conflict.field];
      final isCandidate = conflict.candidates.any(
        (candidate) => syncJsonEquals(candidate.value, local),
      );
      if (isCandidate) values[conflict.field] = local;
    }
    return values;
  }

  SyncOperation _operation({
    required String field,
    required String kind,
    required String deviceId,
    num? delta,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final now = DateTime.now().toUtc();
    final sequence = _operationSequence++;
    return SyncOperation(
      id: '$deviceId-${now.microsecondsSinceEpoch}-$sequence',
      field: field,
      kind: kind,
      deviceId: deviceId,
      occurredAt: now,
      delta: delta,
      metadata: metadata,
    );
  }

  Map<String, dynamic> _referenceImageDelta(
    List<dynamic> previousValue,
    List<dynamic> nextValue,
  ) {
    Map<String, dynamic>? asImage(Object? value) {
      if (value is! Map) return null;
      final mapped = value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
      final id = mapped['id'];
      return id is String && id.isNotEmpty ? mapped : null;
    }

    final previous = <String, Map<String, dynamic>>{};
    for (final item in previousValue) {
      final image = asImage(item);
      if (image != null) previous[image['id'] as String] = image;
    }

    final next = <String, Map<String, dynamic>>{};
    for (final item in nextValue) {
      final image = asImage(item);
      if (image != null) next[image['id'] as String] = image;
    }

    final added = <Map<String, dynamic>>[
      for (final entry in next.entries)
        if (!previous.containsKey(entry.key)) entry.value,
    ];
    final removed = <String>[
      for (final id in previous.keys)
        if (!next.containsKey(id)) id,
    ];

    return <String, dynamic>{
      if (added.isNotEmpty) 'added': added,
      if (removed.isNotEmpty) 'removed': removed,
    };
  }

  Map<String, dynamic> _saleRecordDelta(
    Object? previousValue,
    Object? nextValue,
  ) {
    final previous = <String>[
      if (previousValue is List)
        for (final item in previousValue)
          if (item is String) item,
    ];
    final next = <String>[
      if (nextValue is List)
        for (final item in nextValue)
          if (item is String) item,
    ];

    final remainingPrevious = <String>[...previous];
    final added = <String>[];
    for (final item in next) {
      final index = remainingPrevious.indexOf(item);
      if (index == -1) {
        added.add(item);
      } else {
        remainingPrevious.removeAt(index);
      }
    }

    return <String, dynamic>{
      if (added.isNotEmpty) 'added': added,
      if (remainingPrevious.isNotEmpty) 'removed': remainingPrevious,
    };
  }

  void _clearFieldConflicts(
    Map<String, SyncConflict> conflicts,
    String field,
  ) {
    conflicts.removeWhere((_, conflict) => conflict.field == field);
  }

  SyncConflict? _deletionVsEditConflict({
    required SyncRecord left,
    required SyncRecord right,
    required Map<String, SyncConflict> existingConflicts,
  }) {
    if (left.isDeleted == right.isDeleted) return null;
    if (existingConflicts.values.any(
      (conflict) => conflict.field == SyncRecord.deletedField,
    )) {
      return null;
    }

    final deleted = left.isDeleted ? left : right;
    final live = left.isDeleted ? right : left;
    final deleteField = deleted.fields[SyncRecord.deletedField];
    final liveDeletedField = live.fields[SyncRecord.deletedField];
    if (deleteField == null || liveDeletedField == null) return null;

    var evidenceClock = liveDeletedField.clock;
    var evidenceDevice = liveDeletedField.updatedBy;
    var hasConcurrentEdit = false;

    for (final entry in live.fields.entries) {
      if (entry.key == SyncRecord.deletedField) continue;
      if (deleteField.clock.compare(entry.value.clock) !=
          SyncClockRelation.concurrent) {
        continue;
      }
      hasConcurrentEdit = true;
      evidenceClock = evidenceClock.merge(entry.value.clock);
      evidenceDevice = _deterministicDevice(
        evidenceDevice,
        entry.value.updatedBy,
      );
    }

    // Additive/progress edits are represented as operations and deliberately
    // do not tick the base field clock. If the live branch has an operation
    // the deleting branch never saw, it is still a concurrent edit and must
    // not disappear behind the deletion tombstone.
    for (final operation in live.operations.values) {
      if (deleted.operations.containsKey(operation.id)) continue;
      hasConcurrentEdit = true;
      evidenceClock = evidenceClock.tick(operation.deviceId);
      evidenceDevice = _deterministicDevice(
        evidenceDevice,
        operation.deviceId,
      );
    }

    if (!hasConcurrentEdit) return null;

    final keepCandidate = SyncFieldValue(
      value: false,
      clock: evidenceClock,
      updatedBy: evidenceDevice,
    );
    return _createConflict(
      deleted.id,
      SyncRecord.deletedField,
      deleteField,
      keepCandidate,
    );
  }

  SyncConflict _createConflict(
    String recordId,
    String field,
    SyncFieldValue left,
    SyncFieldValue right,
  ) {
    final candidates = <SyncConflictCandidate>[
      SyncConflictCandidate.fromField(left),
      SyncConflictCandidate.fromField(right),
    ]..sort((a, b) => _candidateSignature(a).compareTo(
          _candidateSignature(b),
        ));
    final mergedClock = left.clock.merge(right.clock);
    final clockSignature = mergedClock.counters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rawId = '$recordId|$field|'
        '${clockSignature.map((entry) => '${entry.key}:${entry.value}').join(',')}';
    final id = base64Url
        .encode(utf8.encode(rawId))
        .replaceAll('=', '');

    return SyncConflict(
      id: id,
      recordId: recordId,
      field: field,
      candidates: candidates,
      mergedClock: mergedClock,
      createdAt: DateTime.now().toUtc(),
    );
  }

  SyncFieldValue _deterministicField(
    SyncFieldValue left,
    SyncFieldValue right,
  ) {
    return _fieldSignature(left).compareTo(_fieldSignature(right)) <= 0
        ? left
        : right;
  }

  String _deterministicDevice(String left, String right) {
    return left.compareTo(right) <= 0 ? left : right;
  }

  String _fieldSignature(SyncFieldValue field) {
    return '${stableJsonSignature(field.value)}|${field.updatedBy}';
  }

  String _candidateSignature(SyncConflictCandidate candidate) {
    return '${stableJsonSignature(candidate.value)}|${candidate.deviceId}';
  }
}
