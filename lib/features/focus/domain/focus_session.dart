class FocusSession {
  const FocusSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.orderId,
    this.orderTitleSnapshot,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? orderId;
  final String? orderTitleSnapshot;

  bool get isActive => endedAt == null;

  String get displayTitle {
    if (orderId == null) return '自由专注';
    final title = orderTitleSnapshot?.trim() ?? '';
    return title.isEmpty ? '排单' : title;
  }

  Duration elapsedAt(DateTime now) {
    final end = endedAt ?? now;
    final duration = end.difference(startedAt);
    return duration.isNegative ? Duration.zero : duration;
  }

  FocusSession copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    String? orderId,
    String? orderTitleSnapshot,
    bool clearEndedAt = false,
    bool clearOrder = false,
  }) {
    return FocusSession(
      id: id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      orderId: clearOrder ? null : (orderId ?? this.orderId),
      orderTitleSnapshot:
          clearOrder ? null : (orderTitleSnapshot ?? this.orderTitleSnapshot),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'orderId': orderId,
        'orderTitleSnapshot': orderTitleSnapshot,
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startedAtRaw = json['startedAt'];
    if (id is! String || id.trim().isEmpty || startedAtRaw is! String) {
      throw const FormatException('专注记录格式无效。');
    }
    final startedAt = DateTime.tryParse(startedAtRaw);
    if (startedAt == null) {
      throw const FormatException('专注开始时间格式无效。');
    }

    DateTime? endedAt;
    final endedAtRaw = json['endedAt'];
    if (endedAtRaw != null) {
      if (endedAtRaw is! String) {
        throw const FormatException('专注结束时间格式无效。');
      }
      endedAt = DateTime.tryParse(endedAtRaw);
      if (endedAt == null) {
        throw const FormatException('专注结束时间格式无效。');
      }
    }

    final orderIdRaw = json['orderId'];
    final orderTitleRaw = json['orderTitleSnapshot'];
    if (orderIdRaw != null && orderIdRaw is! String) {
      throw const FormatException('专注排单 ID 格式无效。');
    }
    if (orderTitleRaw != null && orderTitleRaw is! String) {
      throw const FormatException('专注排单标题格式无效。');
    }

    return FocusSession(
      id: id,
      startedAt: startedAt.toLocal(),
      endedAt: endedAt?.toLocal(),
      orderId: orderIdRaw as String?,
      orderTitleSnapshot: orderTitleRaw as String?,
    );
  }
}
