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
    _sort();
    notifyListeners();
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
    FocusSession? primary;
    for (var index = 0; index < _sessions.length; index++) {
      final session = _sessions[index];
      if (!session.isActive) continue;
      final safeEnd = end.isBefore(session.startedAt) ? session.startedAt : end;
      final updated = session.copyWith(endedAt: safeEnd);
      _sessions[index] = updated;
      if (session.id == active.id) primary = updated;
    }
    _sort();
    notifyListeners();
    return primary;
  }

  void _sort() {
    _sessions.sort((left, right) {
      final byStart = left.startedAt.compareTo(right.startedAt);
      if (byStart != 0) return byStart;
      return left.id.compareTo(right.id);
    });
  }
}
