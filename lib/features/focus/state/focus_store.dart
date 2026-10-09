import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

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

  FocusSession byId(String id) {
    return _sessions.firstWhere((session) => session.id == id);
  }

  void replaceAll(Iterable<FocusSession> sessions) {
    _sessions
      ..clear()
      ..addAll(sessions);
    _normalizeConcurrentActiveSessions();
    _sort();
    notifyListeners();
  }

  void _normalizeConcurrentActiveSessions() {
    final active = <FocusSession>[
      for (final session in _sessions)
        if (session.isActive) session,
    ];
    if (active.length <= 1) return;

    active.sort((left, right) {
      final byStart = left.startedAt.compareTo(right.startedAt);
      if (byStart != 0) return byStart;
      return left.id.compareTo(right.id);
    });
    final keep = active.last;

    for (final session in active) {
      if (session.id == keep.id) continue;
      final index = _sessions.indexWhere((item) => item.id == session.id);
      if (index < 0) continue;
      final endedAt = keep.startedAt.isBefore(session.startedAt)
          ? session.startedAt
          : keep.startedAt;
      _sessions[index] = session.copyWith(endedAt: endedAt);
    }
  }

  FocusSession start({
    String? orderId,
    String? orderTitleSnapshot,
    DateTime? startedAt,
  }) {
    if (activeSession != null) {
      throw StateError('已有正在进行的专注。');
    }
    final now = startedAt ?? DateTime.now();
    final entropy = _random.nextInt(1 << 32).toRadixString(36);
    final session = FocusSession(
      id: 'focus_${now.toUtc().microsecondsSinceEpoch.toRadixString(36)}_$entropy',
      startedAt: now,
      orderId: orderId,
      orderTitleSnapshot: orderId == null ? null : orderTitleSnapshot,
    );
    _sessions.add(session);
    _sort();
    notifyListeners();
    return session;
  }

  FocusSession? stop({DateTime? endedAt}) {
    final active = activeSession;
    if (active == null) return null;
    final end = endedAt ?? DateTime.now();
    final safeEnd = end.isBefore(active.startedAt) ? active.startedAt : end;
    final index = _sessions.indexWhere((session) => session.id == active.id);
    if (index < 0) return null;
    final updated = active.copyWith(endedAt: safeEnd);
    _sessions[index] = updated;
    _sort();
    notifyListeners();
    return updated;
  }

  void _sort() {
    _sessions.sort((left, right) {
      final byStart = left.startedAt.compareTo(right.startedAt);
      if (byStart != 0) return byStart;
      return left.id.compareTo(right.id);
    });
  }
}
