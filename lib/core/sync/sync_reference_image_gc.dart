import '../../features/orders/domain/queue_order.dart';
import 'sync_merge_engine.dart';
import 'sync_models.dart';

List<OrderReferenceImage> syncGcHistoricalReferenceImages(SyncRecord record) {
  if (record.kind != SyncEntityKind.order &&
      record.kind != SyncEntityKind.product) {
    return const <OrderReferenceImage>[];
  }

  final byPath = <String, OrderReferenceImage>{};

  void collect(Object? raw) {
    if (raw is! Map) return;
    final id = raw['id'];
    final fileName = raw['fileName'];
    final relativePath = raw['relativePath'];
    final addedAtRaw = raw['addedAt'];
    final sizeBytes = raw['sizeBytes'];
    final addedAt = addedAtRaw is String ? DateTime.tryParse(addedAtRaw) : null;
    if (id is! String ||
        id.isEmpty ||
        fileName is! String ||
        fileName.isEmpty ||
        relativePath is! String ||
        relativePath.isEmpty ||
        addedAt == null ||
        sizeBytes is! int ||
        sizeBytes < 0) {
      return;
    }
    byPath[relativePath] = OrderReferenceImage(
      id: id,
      fileName: fileName,
      relativePath: relativePath,
      addedAt: addedAt,
      sizeBytes: sizeBytes,
    );
  }

  final base = record.fields['referenceImages']?.value;
  if (base is List) {
    for (final item in base) {
      collect(item);
    }
  }

  for (final operation in record.operations.values) {
    if (operation.kind != 'reference-image-delta') continue;
    final added = operation.metadata['added'];
    if (added is List) {
      for (final item in added) {
        collect(item);
      }
    }
    final removedImages = operation.metadata['removedImages'];
    if (removedImages is List) {
      for (final item in removedImages) {
        collect(item);
      }
    }
  }

  return List<OrderReferenceImage>.unmodifiable(byPath.values);
}

Set<String> syncGcCurrentReferencePaths(
  SyncRecord record,
  SyncMergeEngine mergeEngine,
) {
  if (record.isDeleted) return const <String>{};
  final values = mergeEngine.materialize(record);
  final raw = values?['referenceImages'];
  if (raw is! List) return const <String>{};

  return <String>{
    for (final item in raw)
      if (item is Map && item['relativePath'] is String)
        item['relativePath'] as String,
  };
}

Set<String> syncGcProtectedReferencePaths({
  required Map<SyncEntityKind, Map<String, SyncRecord>> recordsByKind,
  required SyncMergeEngine mergeEngine,
}) {
  final protected = <String>{};
  for (final kind in const <SyncEntityKind>[
    SyncEntityKind.order,
    SyncEntityKind.product,
  ]) {
    for (final record in recordsByKind[kind]?.values ?? const <SyncRecord>[]) {
      if (record.conflicts.isNotEmpty) {
        protected.addAll(
          syncGcHistoricalReferenceImages(record).map((image) => image.relativePath),
        );
        continue;
      }
      protected.addAll(syncGcCurrentReferencePaths(record, mergeEngine));
    }
  }
  return protected;
}

List<OrderReferenceImage> syncGcOrphanReferenceImages({
  required SyncRecord record,
  required Set<String> protectedPaths,
}) {
  return <OrderReferenceImage>[
    for (final image in syncGcHistoricalReferenceImages(record))
      if (!protectedPaths.contains(image.relativePath)) image,
  ];
}