import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models/active_session_state.dart';
import 'models/study_session.dart';
import 'models/weekly_goal.dart';
import 'timestamps.dart';

/// The Monday (00:00) of the week containing [date].
DateTime mondayOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

String _generateId() {
  final rand = Random();
  return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
}

abstract class StudyTimerRepository extends ChangeNotifier {
  /// Loads any previously-persisted active session from storage into
  /// [activeSession]. Must be awaited once before reading [activeSession]
  /// on app startup — [activeSession] itself is a synchronous getter and
  /// will not trigger this on its own. Safe to call more than once (a
  /// no-op after the first successful load).
  Future<void> load();
  ActiveSessionState? get activeSession;
  Future<void> startSession();
  Future<void> pauseSession();
  Future<void> resumeSession();
  Future<StudySession> endSession();
  Future<List<StudySession>> getSessionsBetween(DateTime start, DateTime end);
  Future<int?> getWeeklyGoalMinutes(DateTime forWeekStart);
  Future<void> setWeeklyGoal(int targetMinutes);
  Future<List<StudySession>> getAllSessions();
  Future<List<WeeklyGoal>> getAllGoals();
  Future<void> upsertSession(StudySession session);
  Future<void> upsertGoal(WeeklyGoal goal);
  Future<void> clearAllLocalData();
  Future<void> close();
}

class LocalStudyTimerRepository extends ChangeNotifier implements StudyTimerRepository {
  static const _prefsKey = 'timer_active_session';

  final Future<Database> Function() _openDb;
  final Future<SharedPreferences> Function() _getPrefs;
  final DateTime Function() _now;

  Database? _db;
  ActiveSessionState? _activeSession;
  bool _loaded = false;

  LocalStudyTimerRepository({
    Future<Database> Function()? openDb,
    Future<SharedPreferences> Function()? getPrefs,
    DateTime Function()? now,
  })  : _openDb = openDb ?? _defaultOpenDb,
        _getPrefs = getPrefs ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  static Future<Database> _defaultOpenDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return openAppDatabase(p.join(dir.path, 'english_helper.sqlite'));
  }

  Future<Database> get _database async => _db ??= await _openDb();

  @override
  ActiveSessionState? get activeSession => _activeSession;

  @override
  Future<void> load() => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await _getPrefs();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      _activeSession =
          ActiveSessionState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await _getPrefs();
    if (_activeSession == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(_activeSession!.toJson()));
    }
  }

  @override
  Future<void> startSession() async {
    await _ensureLoaded();
    _activeSession = ActiveSessionState(startedAt: _now());
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> pauseSession() async {
    await _ensureLoaded();
    final current = _activeSession;
    if (current == null || current.isPaused) return;
    _activeSession = current.copyWith(pausedAt: _now());
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> resumeSession() async {
    await _ensureLoaded();
    final current = _activeSession;
    if (current == null || !current.isPaused) return;
    final pausedDuration = _now().difference(current.pausedAt!).inSeconds;
    _activeSession = current.copyWith(
      clearPausedAt: true,
      accumulatedPausedSeconds: current.accumulatedPausedSeconds + pausedDuration,
    );
    await _persist();
    notifyListeners();
  }

  @override
  Future<StudySession> endSession() async {
    await _ensureLoaded();
    final current = _activeSession;
    if (current == null) {
      throw StateError('No active session to end');
    }
    final now = _now();
    final rawDuration = current.elapsedSeconds(now: now);
    final session = StudySession(
      id: _generateId(),
      startedAt: current.startedAt,
      endedAt: now,
      durationSeconds: rawDuration < 0 ? 0 : rawDuration,
      savedAt: now.toIso8601String(),
      updatedAt: utcNowIso(),
    );

    final db = await _database;
    await db.insert('study_sessions', session.toMap());

    _activeSession = null;
    await _persist();
    notifyListeners();
    return session;
  }

  @override
  Future<List<StudySession>> getSessionsBetween(DateTime start, DateTime end) async {
    final db = await _database;
    final rows = await db.query(
      'study_sessions',
      where: 'started_at >= ? AND started_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'started_at ASC',
    );
    return rows.map(StudySession.fromMap).toList();
  }

  @override
  Future<int?> getWeeklyGoalMinutes(DateTime forWeekStart) async {
    final db = await _database;
    final rows = await db.query(
      'weekly_goals',
      where: 'effective_from <= ?',
      whereArgs: [forWeekStart.toIso8601String()],
      // Ties on effective_from (multiple goals set within the same week)
      // must resolve to the most recently inserted row — SQLite otherwise
      // leaves same-key ordering unspecified. created_at isn't a reliable
      // tiebreaker on its own (millisecond/clock resolution can tie too),
      // so fall back to the table's implicit rowid, which strictly
      // increases with insertion order.
      orderBy: 'effective_from DESC, rowid DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['target_minutes'] as int;
  }

  @override
  Future<void> setWeeklyGoal(int targetMinutes) async {
    final db = await _database;
    final now = _now();
    final goal = WeeklyGoal(
      id: _generateId(),
      targetMinutes: targetMinutes,
      effectiveFrom: mondayOf(now),
      createdAt: now.toIso8601String(),
      updatedAt: utcNowIso(),
    );
    await db.insert('weekly_goals', goal.toMap());
    notifyListeners();
  }

  @override
  Future<List<StudySession>> getAllSessions() async {
    final db = await _database;
    final rows = await db.query('study_sessions', orderBy: 'started_at DESC');
    return rows.map(StudySession.fromMap).toList();
  }

  @override
  Future<List<WeeklyGoal>> getAllGoals() async {
    final db = await _database;
    final rows = await db.query('weekly_goals', orderBy: 'effective_from DESC');
    return rows.map(WeeklyGoal.fromMap).toList();
  }

  @override
  Future<void> upsertSession(StudySession session) async {
    final db = await _database;
    await db.insert('study_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> upsertGoal(WeeklyGoal goal) async {
    final db = await _database;
    await db.insert('weekly_goals', goal.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> clearAllLocalData() async {
    final db = await _database;
    await db.delete('study_sessions');
    await db.delete('weekly_goals');
    notifyListeners();
  }

  @override
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      _db = null;
      await db.close();
    }
  }
}
