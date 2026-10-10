import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../orders/domain/queue_order.dart';
import '../domain/focus_session.dart';

class FocusStore extends ChangeNotifier {
  final List<FocusSession> _sessions = <FocusSession>[];
  final Random _random = Random.secure();

  UnmodifiableListView<FocusSession> get sessions =>
      UnmodifiableListView(_sessions);

  FocusSession? get activeSession {
    FocusSession? active;
    for (final session in _sessions) {
      if (!session.isActive) continue;
      if (active == null || session.startedAt.isAfter(active.startedAt)) {
        active = session;
      }
    }
    return active;
  }

  bool contains(String id) => _sessions.any((session) => session.id == id);

  FocusSession byId(String id) =>
      _sessions.firstWhere((session) => session.id == id);

  FocusSession start({QueueOrder? order}) {
    if (activeSession != null) {
      throw StateError('已有正在进行的专注。');
    }
    final now = DateTime.now();
    final session = FocusSession(
      id: 'focus_${now.toUtc().microsecondsSinceEpoch.toRadixString(36)}_${_random.nextInt(1 << 32).toRadixString(36)}',
      startedAt: now,
      endedAt: null,
      orderId: order?.id,
      orderTitleSnapshot: order?.title,
    );
    _sessions.add(session);
    _sort();
    notifyListeners();
    return session;
  }

  FocusSession? stopActive() => stopActiveAt(DateTime.now());

  FocusSession? stopActiveAt(DateTime requestedEnd) {
    final active = activeSession;
    if (active == null) return null;
    final index = _sessions.indexWhere((item) => item.id == active.id);
    if (index < 0) return null;
    final end = requestedEnd.isAfter(active.startedAt)
        ? requestedEnd
        : active.startedAt.add(const Duration(seconds: 1));
    _sessions[index] = active.copyWith(endedAt: end);
    _sort();
    notifyListeners();
    return _sessions[index];
  }

  FocusSession? discardActive() {
    final active = activeSession;
    if (active == null) return null;
    _sessions.removeWhere((session) => session.id == active.id);
    notifyListeners();
    return active;
  }

  void replaceAll(Iterable<FocusSession> sessions) {
    final byId = <String, FocusSession>{};
    for (final session in sessions) {
      byId[session.id] = session;
    }

    // Two devices can both start while offline. Resolve that deterministically
    // when their records meet: the later start remains active, and every older
    // active session ends at that later start so synced history never overlaps.
    final active = byId.values.where((session) => session.isActive).toList()
      ..sort((a, b) {
        final byTime = a.startedAt.compareTo(b.startedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    if (active.length > 1) {
      final keep = active.last;
      for (final session in active.take(active.length - 1)) {
        final end = keep.startedAt.isAfter(session.startedAt)
            ? keep.startedAt
            : session.startedAt.add(const Duration(seconds: 1));
        byId[session.id] = session.copyWith(endedAt: end);
      }
    }

    _sessions
      ..clear()
      ..addAll(byId.values);
    _sort();
    notifyListeners();
  }

  bool removeById(String id) {
    final index = _sessions.indexWhere((session) => session.id == id);
    if (index < 0 || _sessions[index].isActive) return false;
    _sessions.removeAt(index);
    notifyListeners();
    return true;
  }

  int removeStartedInRange({
    DateTime? start,
    DateTime? end,
  }) {
    if (start == null && end == null) {
      throw ArgumentError('清理专注记录必须指定时间范围。');
    }
    final before = _sessions.length;
    _sessions.removeWhere((session) {
      if (session.isActive) return false;
      if (start != null && session.startedAt.isBefore(start)) return false;
      if (end != null && session.startedAt.isAfter(end)) return false;
      return true;
    });
    final removed = before - _sessions.length;
    if (removed > 0) notifyListeners();
    return removed;
  }

  int countStartedInRange({
    DateTime? start,
    DateTime? end,
  }) {
    if (start == null && end == null) return 0;
    var count = 0;
    for (final session in _sessions) {
      if (session.isActive) continue;
      if (start != null && session.startedAt.isBefore(start)) continue;
      if (end != null && session.startedAt.isAfter(end)) continue;
      count += 1;
    }
    return count;
  }

  void _sort() {
    _sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
}
