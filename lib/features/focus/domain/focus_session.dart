class FocusSession {
  const FocusSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.orderId,
    required this.orderTitleSnapshot,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? orderId;
  final String? orderTitleSnapshot;

  bool get isActive => endedAt == null;
  bool get isFreeFocus => orderId == null;

  Duration durationAt([DateTime? now]) {
    final end = endedAt ?? now ?? DateTime.now();
    if (!end.isAfter(startedAt)) return Duration.zero;
    return end.difference(startedAt);
  }

  FocusSession copyWith({
    DateTime? endedAt,
    bool clearEndedAt = false,
    String? orderId,
    bool clearOrderId = false,
    String? orderTitleSnapshot,
    bool clearOrderTitleSnapshot = false,
  }) {
    return FocusSession(
      id: id,
      startedAt: startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      orderId: clearOrderId ? null : (orderId ?? this.orderId),
      orderTitleSnapshot: clearOrderTitleSnapshot
          ? null
          : (orderTitleSnapshot ?? this.orderTitleSnapshot),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'orderId': orderId,
        'orderTitleSnapshot': orderTitleSnapshot,
      };

  static FocusSession fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startedRaw = json['startedAt'];
    final endedRaw = json['endedAt'];
    final orderRaw = json['orderId'];
    final titleRaw = json['orderTitleSnapshot'];

    if (id is! String || id.trim().isEmpty || startedRaw is! String) {
      throw const FormatException('专注记录格式无效。');
    }
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) {
      throw const FormatException('专注开始时间无效。');
    }
    DateTime? endedAt;
    if (endedRaw != null) {
      if (endedRaw is! String) {
        throw const FormatException('专注结束时间无效。');
      }
      endedAt = DateTime.tryParse(endedRaw);
      if (endedAt == null || endedAt.isBefore(startedAt)) {
        throw const FormatException('专注结束时间无效。');
      }
    }
    if (orderRaw != null && orderRaw is! String) {
      throw const FormatException('专注排单 ID 无效。');
    }
    if (titleRaw != null && titleRaw is! String) {
      throw const FormatException('专注排单标题无效。');
    }

    return FocusSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      orderId: orderRaw as String?,
      orderTitleSnapshot: titleRaw as String?,
    );
  }
}
