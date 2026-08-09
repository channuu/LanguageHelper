# Study Timer Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone focus timer to the Phase B Flutter app (`mobile/`) — start/pause/resume/end, week/month/year aggregation with graph and list views, and a weekly goal that applies only from the week it was set.

**Architecture:** A new `StudyTimerRepository` (separate from `LearningRepository`, same sqflite database file, two new tables) backs a new 5th "타이머" tab. Active-session state (for surviving app restarts) lives in `shared_preferences`, not the database — only completed sessions are persisted to SQL.

**Tech Stack:** Existing stack (sqflite, shared_preferences, provider) plus a new dependency: `fl_chart` for the bar-graph view.

## Global Constraints

- Timer is independent of the Flashcard screen — no auto-start/stop tied to review sessions.
- Paused time is excluded from the recorded `duration_seconds` — this is the single most important invariant, test it directly.
- Changing the weekly goal only affects weeks from the change onward; past weeks keep whatever goal was in effect then. Implemented via `weekly_goals.effective_from`, never by mutating an existing row.
- The app must keep measuring while backgrounded/killed and restarted — implemented by persisting `startedAt`/`pausedAt`/`accumulatedPausedSeconds` to `shared_preferences` on every state change, never by a background service.
- No new columns beyond what's specified below; no migration/versioning logic — this is a pre-release app, `onCreate` only.
- Widget test coverage stays minimal, matching the rest of Phase B: one smoke test per screen/widget, not exhaustive UI coverage. Repository logic (the timing math, the goal-lookup logic) gets full unit test coverage — that's where the real risk is.
- All time-dependent repository logic must be tested with an injected fake clock (`DateTime Function() now` parameter), never real `sleep`/`delay` calls — this matches the existing codebase's preference for deterministic tests and avoids flaky timing assertions.

---

### Task 1: Data models — StudySession, ActiveSessionState, WeeklyGoal

**Files:**
- Create: `mobile/lib/data/models/study_session.dart`
- Create: `mobile/lib/data/models/active_session_state.dart`
- Create: `mobile/lib/data/models/weekly_goal.dart`
- Test: `mobile/test/data/models/study_session_test.dart`
- Test: `mobile/test/data/models/active_session_state_test.dart`
- Test: `mobile/test/data/models/weekly_goal_test.dart`

**Interfaces:**
- Produces: `StudySession` (`toMap()`/`fromMap()`, snake_case keys `started_at`/`ended_at`/`duration_seconds`/`saved_at` matching Task 2's schema), `ActiveSessionState` (`toJson()`/`fromJson()` for `shared_preferences`, `isPaused` getter, `elapsedSeconds({DateTime? now})`, `copyWith({DateTime? pausedAt, bool clearPausedAt, int? accumulatedPausedSeconds})`), `WeeklyGoal` (`toMap()`/`fromMap()`, snake_case keys `target_minutes`/`effective_from`/`created_at`). Used by Task 2 (schema) and Task 3 (repository).

- [ ] **Step 1: Write the failing tests**

```dart
// mobile/test/data/models/study_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/study_session.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final session = StudySession(
      id: 'sess1',
      startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
      endedAt: DateTime.parse('2026-08-10T09:30:00.000Z'),
      durationSeconds: 1500,
      savedAt: '2026-08-10T09:30:00.000Z',
    );

    final restored = StudySession.fromMap(session.toMap());

    expect(restored.id, 'sess1');
    expect(restored.startedAt, DateTime.parse('2026-08-10T09:00:00.000Z'));
    expect(restored.endedAt, DateTime.parse('2026-08-10T09:30:00.000Z'));
    expect(restored.durationSeconds, 1500);
    expect(restored.savedAt, '2026-08-10T09:30:00.000Z');
  });

  test('toMap uses snake_case keys matching the SQL schema', () {
    final session = StudySession(
      id: 'sess1',
      startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
      endedAt: DateTime.parse('2026-08-10T09:30:00.000Z'),
      durationSeconds: 1500,
      savedAt: '2026-08-10T09:30:00.000Z',
    );

    final map = session.toMap();

    expect(map.keys.toSet(), {
      'id', 'started_at', 'ended_at', 'duration_seconds', 'saved_at',
    });
  });
}
```

```dart
// mobile/test/data/models/active_session_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/active_session_state.dart';

void main() {
  group('ActiveSessionState', () {
    test('isPaused is false when pausedAt is null', () {
      final state = ActiveSessionState(startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'));
      expect(state.isPaused, isFalse);
    });

    test('isPaused is true when pausedAt is set', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
      );
      expect(state.isPaused, isTrue);
    });

    test('elapsedSeconds while running subtracts accumulated paused time from now-started', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        accumulatedPausedSeconds: 60,
      );
      final now = DateTime.parse('2026-08-10T09:10:00.000Z'); // 600s since start
      expect(state.elapsedSeconds(now: now), 540); // 600 - 60
    });

    test('elapsedSeconds while paused uses pausedAt, not now', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
        accumulatedPausedSeconds: 0,
      );
      final now = DateTime.parse('2026-08-10T09:30:00.000Z'); // way later, should be ignored
      expect(state.elapsedSeconds(now: now), 300); // 09:05 - 09:00
    });

    test('toJson/fromJson round-trips all fields', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
        accumulatedPausedSeconds: 42,
      );
      final restored = ActiveSessionState.fromJson(state.toJson());

      expect(restored.startedAt, state.startedAt);
      expect(restored.pausedAt, state.pausedAt);
      expect(restored.accumulatedPausedSeconds, 42);
    });

    test('toJson/fromJson round-trips a null pausedAt', () {
      final state = ActiveSessionState(startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'));
      final restored = ActiveSessionState.fromJson(state.toJson());
      expect(restored.pausedAt, isNull);
    });

    test('copyWith(pausedAt: x) sets pausedAt without touching other fields', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        accumulatedPausedSeconds: 10,
      );
      final updated = state.copyWith(pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'));

      expect(updated.pausedAt, DateTime.parse('2026-08-10T09:05:00.000Z'));
      expect(updated.startedAt, state.startedAt);
      expect(updated.accumulatedPausedSeconds, 10);
    });

    test('copyWith(clearPausedAt: true) clears pausedAt even if a new one is also passed', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
      );
      final updated = state.copyWith(clearPausedAt: true, accumulatedPausedSeconds: 300);

      expect(updated.pausedAt, isNull);
      expect(updated.accumulatedPausedSeconds, 300);
    });
  });
}
```

```dart
// mobile/test/data/models/weekly_goal_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/weekly_goal.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final goal = WeeklyGoal(
      id: 'goal1',
      targetMinutes: 300,
      effectiveFrom: DateTime.parse('2026-08-10T00:00:00.000Z'),
      createdAt: '2026-08-10T00:00:00.000Z',
    );

    final restored = WeeklyGoal.fromMap(goal.toMap());

    expect(restored.id, 'goal1');
    expect(restored.targetMinutes, 300);
    expect(restored.effectiveFrom, DateTime.parse('2026-08-10T00:00:00.000Z'));
    expect(restored.createdAt, '2026-08-10T00:00:00.000Z');
  });

  test('toMap uses snake_case keys matching the SQL schema', () {
    final goal = WeeklyGoal(
      id: 'goal1',
      targetMinutes: 300,
      effectiveFrom: DateTime.parse('2026-08-10T00:00:00.000Z'),
      createdAt: '2026-08-10T00:00:00.000Z',
    );

    expect(goal.toMap().keys.toSet(), {
      'id', 'target_minutes', 'effective_from', 'created_at',
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd mobile && flutter test test/data/models/study_session_test.dart test/data/models/active_session_state_test.dart test/data/models/weekly_goal_test.dart
```
Expected: FAIL — none of the three source files exist yet.

- [ ] **Step 3: Implement StudySession**

```dart
// mobile/lib/data/models/study_session.dart
class StudySession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String savedAt;

  const StudySession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.savedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'saved_at': savedAt,
      };

  factory StudySession.fromMap(Map<String, Object?> map) => StudySession(
        id: map['id'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        durationSeconds: map['duration_seconds'] as int,
        savedAt: map['saved_at'] as String,
      );
}
```

- [ ] **Step 4: Implement ActiveSessionState**

```dart
// mobile/lib/data/models/active_session_state.dart
class ActiveSessionState {
  final DateTime startedAt;
  final DateTime? pausedAt;
  final int accumulatedPausedSeconds;

  const ActiveSessionState({
    required this.startedAt,
    this.pausedAt,
    this.accumulatedPausedSeconds = 0,
  });

  bool get isPaused => pausedAt != null;

  /// Seconds of actual focus time so far, excluding paused time.
  /// While paused, uses [pausedAt] as the reference point (not [now]) so the
  /// displayed time freezes during a pause.
  int elapsedSeconds({DateTime? now}) {
    final reference = pausedAt ?? (now ?? DateTime.now());
    return reference.difference(startedAt).inSeconds - accumulatedPausedSeconds;
  }

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'pausedAt': pausedAt?.toIso8601String(),
        'accumulatedPausedSeconds': accumulatedPausedSeconds,
      };

  factory ActiveSessionState.fromJson(Map<String, Object?> json) => ActiveSessionState(
        startedAt: DateTime.parse(json['startedAt'] as String),
        pausedAt: json['pausedAt'] != null
            ? DateTime.parse(json['pausedAt'] as String)
            : null,
        accumulatedPausedSeconds: json['accumulatedPausedSeconds'] as int? ?? 0,
      );

  ActiveSessionState copyWith({
    DateTime? pausedAt,
    bool clearPausedAt = false,
    int? accumulatedPausedSeconds,
  }) =>
      ActiveSessionState(
        startedAt: startedAt,
        pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
        accumulatedPausedSeconds: accumulatedPausedSeconds ?? this.accumulatedPausedSeconds,
      );
}
```

- [ ] **Step 5: Implement WeeklyGoal**

```dart
// mobile/lib/data/models/weekly_goal.dart
class WeeklyGoal {
  final String id;
  final int targetMinutes;
  final DateTime effectiveFrom;
  final String createdAt;

  const WeeklyGoal({
    required this.id,
    required this.targetMinutes,
    required this.effectiveFrom,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'target_minutes': targetMinutes,
        'effective_from': effectiveFrom.toIso8601String(),
        'created_at': createdAt,
      };

  factory WeeklyGoal.fromMap(Map<String, Object?> map) => WeeklyGoal(
        id: map['id'] as String,
        targetMinutes: map['target_minutes'] as int,
        effectiveFrom: DateTime.parse(map['effective_from'] as String),
        createdAt: map['created_at'] as String,
      );
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd mobile && flutter test test/data/models/study_session_test.dart test/data/models/active_session_state_test.dart test/data/models/weekly_goal_test.dart
```
Expected: all pass (2 + 8 + 2 = 12 tests, `All tests passed!`).

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/data/models/study_session.dart mobile/lib/data/models/active_session_state.dart mobile/lib/data/models/weekly_goal.dart mobile/test/data/models/study_session_test.dart mobile/test/data/models/active_session_state_test.dart mobile/test/data/models/weekly_goal_test.dart
git commit -m "feat: add StudySession, ActiveSessionState, WeeklyGoal models"
```

---

### Task 2: database.dart — add study_sessions and weekly_goals tables

**Files:**
- Modify: `mobile/lib/data/database.dart`
- Modify: `mobile/test/data/database_test.dart`

**Interfaces:**
- Consumes: nothing new from Task 1 (this task works with raw SQL, not the model classes).
- Produces: `openAppDatabase()` now also creates `study_sessions` (columns: `id`, `started_at`, `ended_at`, `duration_seconds`, `saved_at`) and `weekly_goals` (columns: `id`, `target_minutes`, `effective_from`, `created_at`). Used by Task 3's repository. Does NOT change `hasValidSchema()` — that function only validates `words`/`sentences` (the Chrome-extension export schema) and must keep doing exactly that; the two new tables are irrelevant to import validation and must not be added to `hasValidSchema`'s checks.

- [ ] **Step 1: Write the failing test**

Add to the existing `mobile/test/data/database_test.dart`, inside the `group('openAppDatabase', ...)` block (after the existing tests, before the closing `});`):

```dart
    test('creates study_sessions and weekly_goals tables with expected columns', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);

      final sessionsCols = (await db.rawQuery('PRAGMA table_info(study_sessions)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(sessionsCols, {'id', 'started_at', 'ended_at', 'duration_seconds', 'saved_at'});

      final goalsCols = (await db.rawQuery('PRAGMA table_info(weekly_goals)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(goalsCols, {'id', 'target_minutes', 'effective_from', 'created_at'});

      await db.close();
    });
```

Also add this test in the `group('hasValidSchema', ...)` block, to lock in that the new tables must NOT affect import validation:

```dart
    test('ignores study_sessions/weekly_goals when validating an import file', () async {
      // A file with only words/sentences (like a real Chrome-extension export)
      // must still validate, even though the app's own DB also has the two
      // timer tables — hasValidSchema must not require them.
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE words (
          id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT, sentence TEXT,
          translation TEXT, platform TEXT, content_title TEXT, content_id TEXT,
          timestamp REAL, saved_at TEXT, review_count INTEGER DEFAULT 0, next_review_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE sentences (
          id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT, platform TEXT,
          content_title TEXT, content_id TEXT, timestamp REAL, saved_at TEXT,
          review_count INTEGER DEFAULT 0, next_review_at TEXT
        )
      ''');
      expect(await hasValidSchema(db), isTrue);
      await db.close();
    });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd mobile && flutter test test/data/database_test.dart
```
Expected: FAIL on the new `study_sessions`/`weekly_goals` columns test (`PRAGMA table_info` returns empty sets — tables don't exist yet). The `hasValidSchema` addition should already pass since it doesn't depend on anything new — confirm it passes even before Step 3 (proves it's testing current, correct behavior, not something Step 3 needs to fix).

- [ ] **Step 3: Add the two CREATE TABLE statements to openAppDatabase's onCreate**

In `mobile/lib/data/database.dart`, inside the `onCreate: (db, version) async { ... }` callback, after the existing `sentences` table creation (before the closing `},` of `onCreate`), add:

```dart
        await db.execute('''
          CREATE TABLE IF NOT EXISTS study_sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            saved_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS weekly_goals (
            id TEXT PRIMARY KEY,
            target_minutes INTEGER NOT NULL,
            effective_from TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
```

Do not touch `hasValidSchema` or `kWordsColumns`/`kSentencesColumns` — those must keep validating only the extension-export schema.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd mobile && flutter test test/data/database_test.dart
```
Expected: all pass (previous 6 + 2 new = 8 tests, `All tests passed!`).

- [ ] **Step 5: Run the full suite to confirm no regression**

```bash
cd mobile && flutter test
```
Expected: all existing Phase B tests plus this task's still pass.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/data/database.dart mobile/test/data/database_test.dart
git commit -m "feat: add study_sessions and weekly_goals tables"
```

---

### Task 3: StudyTimerRepository

**Files:**
- Create: `mobile/lib/data/study_timer_repository.dart`
- Test: `mobile/test/data/study_timer_repository_test.dart`

**Interfaces:**
- Consumes: `StudySession`, `ActiveSessionState`, `WeeklyGoal` (Task 1); `openAppDatabase` (Task 2, via the module-level `study_sessions`/`weekly_goals` tables it now creates).
- Produces: `mondayOf(DateTime date) -> DateTime` (top-level function, also used by Task 5's history view for period-range calculation), `StudyTimerRepository` (abstract, extends `ChangeNotifier`) with `Future<void> load()` (must be awaited once before reading `activeSession` — see the interface doc comment below for why), `ActiveSessionState? get activeSession`, `Future<void> startSession()`, `Future<void> pauseSession()`, `Future<void> resumeSession()`, `Future<StudySession> endSession()`, `Future<List<StudySession>> getSessionsBetween(DateTime start, DateTime end)`, `Future<int?> getWeeklyGoalMinutes(DateTime forWeekStart)`, `Future<void> setWeeklyGoal(int targetMinutes)`. `LocalStudyTimerRepository({Future<Database> Function()? openDb, Future<SharedPreferences> Function()? getPrefs, DateTime Function()? now})` — production omits all three; tests inject an in-memory FFI `openDb`, a mocked-prefs `getPrefs` (or rely on `SharedPreferences.setMockInitialValues` + the default `SharedPreferences.getInstance`), and a fake clock via `now`. Used by Tasks 4-7 — Task 6's `TimerScreen` MUST call `load()` in `initState` before trusting `activeSession`, otherwise a restored app misses a persisted in-progress session.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/data/study_timer_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';

class _FakeClock {
  DateTime current;
  _FakeClock(this.current);
  DateTime call() => current;
  void advance(Duration d) => current = current.add(d);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late _FakeClock clock;
  late LocalStudyTimerRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = _FakeClock(DateTime.parse('2026-08-10T09:00:00.000Z')); // a Monday
    repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
      now: clock.call,
    );
  });

  group('mondayOf', () {
    test('returns the same date when already Monday', () {
      expect(mondayOf(DateTime.parse('2026-08-10T15:00:00.000Z')),
          DateTime(2026, 8, 10));
    });

    test('returns the preceding Monday for a mid-week date', () {
      expect(mondayOf(DateTime.parse('2026-08-13T15:00:00.000Z')), // Thursday
          DateTime(2026, 8, 10));
    });

    test('returns the preceding Monday for a Sunday', () {
      expect(mondayOf(DateTime.parse('2026-08-16T15:00:00.000Z')), // Sunday
          DateTime(2026, 8, 10));
    });
  });

  group('session lifecycle', () {
    test('startSession sets activeSession with the injected clock time', () async {
      await repo.startSession();
      expect(repo.activeSession, isNotNull);
      expect(repo.activeSession!.startedAt, clock.current);
      expect(repo.activeSession!.isPaused, isFalse);
    });

    test('pauseSession sets pausedAt to the current clock time', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 5));
      await repo.pauseSession();
      expect(repo.activeSession!.isPaused, isTrue);
      expect(repo.activeSession!.pausedAt, clock.current);
    });

    test('resumeSession accumulates the paused duration and clears pausedAt', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 5));
      await repo.pauseSession();
      clock.advance(const Duration(minutes: 2)); // paused for 2 minutes
      await repo.resumeSession();

      expect(repo.activeSession!.isPaused, isFalse);
      expect(repo.activeSession!.accumulatedPausedSeconds, 120);
    });

    test('endSession excludes paused time from duration_seconds', () async {
      await repo.startSession(); // t=0
      clock.advance(const Duration(minutes: 10)); // t=10m, running
      await repo.pauseSession();
      clock.advance(const Duration(minutes: 3)); // t=13m, paused for 3m
      await repo.resumeSession();
      clock.advance(const Duration(minutes: 5)); // t=18m, running again
      final session = await repo.endSession();

      // Total wall time 18m, minus 3m paused = 15m = 900s
      expect(session.durationSeconds, 900);
      expect(repo.activeSession, isNull);
    });

    test('endSession persists the session to the database', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 25));
      await repo.endSession();

      final sessions = await repo.getSessionsBetween(
        DateTime.parse('2026-08-10T00:00:00.000Z'),
        DateTime.parse('2026-08-11T00:00:00.000Z'),
      );
      expect(sessions, hasLength(1));
      expect(sessions.first.durationSeconds, 1500);
    });

    test('pauseSession is a no-op when there is no active session', () async {
      await repo.pauseSession();
      expect(repo.activeSession, isNull);
    });

    test('pauseSession is a no-op when already paused', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 1));
      await repo.pauseSession();
      final firstPausedAt = repo.activeSession!.pausedAt;
      clock.advance(const Duration(minutes: 1));
      await repo.pauseSession(); // should not move pausedAt forward
      expect(repo.activeSession!.pausedAt, firstPausedAt);
    });

    test('activeSession is null before load() even if a session was persisted', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 5));
      await repo.pauseSession();

      // Simulate an app restart: a brand-new repository instance reading the
      // same (mocked) SharedPreferences store, before calling load().
      final restarted = LocalStudyTimerRepository(
        openDb: () => openAppDatabase(inMemoryDatabasePath),
        now: clock.call,
      );
      expect(restarted.activeSession, isNull);
    });

    test('load() restores a persisted active session without any other call', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 5));
      await repo.pauseSession();

      final restarted = LocalStudyTimerRepository(
        openDb: () => openAppDatabase(inMemoryDatabasePath),
        now: clock.call,
      );
      await restarted.load();

      expect(restarted.activeSession, isNotNull);
      expect(restarted.activeSession!.startedAt, DateTime.parse('2026-08-10T09:00:00.000Z'));
      expect(restarted.activeSession!.isPaused, isTrue);
    });

    test('load() is a no-op when there is nothing persisted', () async {
      final fresh = LocalStudyTimerRepository(
        openDb: () => openAppDatabase(inMemoryDatabasePath),
        now: clock.call,
      );
      await fresh.load();
      expect(fresh.activeSession, isNull);
    });

    test('notifies listeners on start, pause, resume, and end', () async {
      var notifications = 0;
      repo.addListener(() => notifications++);

      await repo.startSession();
      expect(notifications, 1);
      clock.advance(const Duration(minutes: 1));
      await repo.pauseSession();
      expect(notifications, 2);
      await repo.resumeSession();
      expect(notifications, 3);
      clock.advance(const Duration(minutes: 1));
      await repo.endSession();
      expect(notifications, 4);
    });
  });

  group('getSessionsBetween', () {
    test('only returns sessions whose startedAt falls within [start, end)', () async {
      await repo.startSession();
      clock.advance(const Duration(minutes: 10));
      await repo.endSession(); // session at 2026-08-10T09:00

      clock.current = DateTime.parse('2026-08-20T09:00:00.000Z');
      await repo.startSession();
      clock.advance(const Duration(minutes: 10));
      await repo.endSession(); // session at 2026-08-20T09:00

      final sessions = await repo.getSessionsBetween(
        DateTime.parse('2026-08-10T00:00:00.000Z'),
        DateTime.parse('2026-08-11T00:00:00.000Z'),
      );
      expect(sessions, hasLength(1));
      expect(sessions.first.startedAt, DateTime.parse('2026-08-10T09:00:00.000Z'));
    });
  });

  group('weekly goals', () {
    test('getWeeklyGoalMinutes returns null when no goal has ever been set', () async {
      final goal = await repo.getWeeklyGoalMinutes(mondayOf(clock.current));
      expect(goal, isNull);
    });

    test('setWeeklyGoal makes the goal effective from the current week onward', () async {
      await repo.setWeeklyGoal(300);
      final thisWeek = await repo.getWeeklyGoalMinutes(mondayOf(clock.current));
      expect(thisWeek, 300);
    });

    test('changing the goal does not retroactively change a past week', () async {
      // Week of Aug 10: goal 300
      await repo.setWeeklyGoal(300);

      // Move to the following week and change the goal
      clock.current = DateTime.parse('2026-08-17T09:00:00.000Z');
      await repo.setWeeklyGoal(600);

      final pastWeek = await repo.getWeeklyGoalMinutes(DateTime.parse('2026-08-10T00:00:00.000Z'));
      final newWeek = await repo.getWeeklyGoalMinutes(DateTime.parse('2026-08-17T00:00:00.000Z'));

      expect(pastWeek, 300);
      expect(newWeek, 600);
    });

    test('a future goal change does not affect the current week before it takes effect', () async {
      await repo.setWeeklyGoal(300); // effective from week of Aug 10

      final futureWeek = mondayOf(DateTime.parse('2026-08-24T09:00:00.000Z'));
      final result = await repo.getWeeklyGoalMinutes(futureWeek);
      // No goal was ever set *for or after* Aug 24, but the Aug 10 goal is
      // still the most recent one at or before that date, so it applies.
      expect(result, 300);
    });

    test('notifies listeners on setWeeklyGoal', () async {
      var notifications = 0;
      repo.addListener(() => notifications++);
      await repo.setWeeklyGoal(300);
      expect(notifications, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/study_timer_repository_test.dart
```
Expected: FAIL — `mobile/lib/data/study_timer_repository.dart` doesn't exist yet.

- [ ] **Step 3: Implement study_timer_repository.dart**

```dart
// mobile/lib/data/study_timer_repository.dart
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
      orderBy: 'effective_from DESC',
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
    );
    await db.insert('weekly_goals', goal.toMap());
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/study_timer_repository_test.dart
```
Expected: all pass (3 `mondayOf` + 10 session-lifecycle + 1 `getSessionsBetween` + 4 weekly-goal = 18 tests, `All tests passed!`).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/study_timer_repository.dart mobile/test/data/study_timer_repository_test.dart
git commit -m "feat: add StudyTimerRepository with pause-aware duration tracking"
```

---

### Task 4: fl_chart dependency + WeeklyGoalCard widget

**Files:**
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/features/timer/weekly_goal_card.dart`
- Test: `mobile/test/features/timer/weekly_goal_card_test.dart`

**Interfaces:**
- Consumes: `StudyTimerRepository` (Task 3, via `provider`), `mondayOf` (Task 3).
- Produces: `WeeklyGoalCard` widget (`StatefulWidget`, no constructor params) — mounted by Task 6's `TimerScreen`.

- [ ] **Step 1: Add the fl_chart dependency**

```bash
cd mobile && flutter pub add fl_chart
```
Expected: `fl_chart` added under `dependencies:` in `pubspec.yaml`. (This task's own widget doesn't use charts, but adding the dependency here keeps Task 5 from needing its own pubspec-only step.)

- [ ] **Step 2: Write the failing test**

```dart
// mobile/test/features/timer/weekly_goal_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/weekly_goal_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildCard(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: Scaffold(body: WeeklyGoalCard())),
    );
  }

  testWidgets('shows "목표를 설정해보세요" when no goal is set', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('목표'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows progress against the goal once one is set', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.setWeeklyGoal(300);
    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('300'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/timer/weekly_goal_card_test.dart
```
Expected: FAIL — `mobile/lib/features/timer/weekly_goal_card.dart` doesn't exist yet.

- [ ] **Step 4: Implement WeeklyGoalCard**

```dart
// mobile/lib/features/timer/weekly_goal_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({super.key});

  Future<void> _showSetGoalDialog(BuildContext context, StudyTimerRepository repo) async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주간 목표 (분)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await repo.setWeeklyGoal(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudyTimerRepository>();
    final weekStart = mondayOf(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 7));

    return FutureBuilder<List<Object?>>(
      future: Future.wait([
        repo.getWeeklyGoalMinutes(weekStart),
        repo.getSessionsBetween(weekStart, weekEnd),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final goalMinutes = snapshot.data?[0] as int?;
        final sessions = (snapshot.data?[1] as List<StudySession>?) ?? const [];
        final totalMinutes = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds ~/ 60);

        if (goalMinutes == null) {
          return Card(
            child: ListTile(
              title: const Text('이번 주 목표를 설정해보세요'),
              trailing: TextButton(
                onPressed: () => _showSetGoalDialog(context, repo),
                child: const Text('목표 설정'),
              ),
            ),
          );
        }

        final progress = goalMinutes == 0 ? 0.0 : (totalMinutes / goalMinutes).clamp(0.0, 1.0);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('이번 주 $totalMinutes / $goalMinutes분'),
                    TextButton(
                      onPressed: () => _showSetGoalDialog(context, repo),
                      child: const Text('목표 수정'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/timer/weekly_goal_card_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/features/timer/weekly_goal_card.dart mobile/test/features/timer/weekly_goal_card_test.dart
git commit -m "feat: add fl_chart dependency and WeeklyGoalCard widget"
```

---

### Task 5: TimerHistoryView — period selector, graph/list toggle

**Files:**
- Create: `mobile/lib/features/timer/timer_history_view.dart`
- Test: `mobile/test/features/timer/timer_history_view_test.dart`

**Interfaces:**
- Consumes: `StudyTimerRepository` (Task 3, via `provider`), `mondayOf` (Task 3), `EmptyState` (`mobile/lib/shared/widgets/empty_state.dart`, existing Phase B widget), `fl_chart`'s `BarChart`/`BarChartData`/`BarChartGroupData`/`BarChartRodData` (Task 4's dependency).
- Produces: `TimerPeriod` enum (`week`, `month`, `year`), `TimerViewMode` enum (`graph`, `list`), `TimerHistoryView` widget (`StatefulWidget`, no constructor params) — mounted by Task 6's `TimerScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/features/timer/timer_history_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/timer_history_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildView(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: Scaffold(body: TimerHistoryView())),
    );
  }

  testWidgets('shows empty state when there are no sessions this week', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildView(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('기록된 공부 시간이 없어요'), findsOneWidget);
  });

  testWidgets('switching to list view shows minutes for a recorded session', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.startSession();
    await repo.endSession(); // a 0-minute session is fine for existence, but let's give it real time

    await tester.pumpWidget(buildView(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('숫자'));
    await tester.pumpAndSettle();

    // With 0 duration the list still renders a row for today (0분) rather
    // than the empty state, since a session record exists.
    expect(find.textContaining('분'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/timer/timer_history_view_test.dart
```
Expected: FAIL — `mobile/lib/features/timer/timer_history_view.dart` doesn't exist yet.

- [ ] **Step 3: Implement TimerHistoryView**

```dart
// mobile/lib/features/timer/timer_history_view.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';
import '../../shared/widgets/empty_state.dart';

enum TimerPeriod { week, month, year }

enum TimerViewMode { graph, list }

class TimerHistoryView extends StatefulWidget {
  const TimerHistoryView({super.key});

  @override
  State<TimerHistoryView> createState() => _TimerHistoryViewState();
}

class _TimerHistoryViewState extends State<TimerHistoryView> {
  TimerPeriod _period = TimerPeriod.week;
  TimerViewMode _viewMode = TimerViewMode.graph;

  ({DateTime start, DateTime end}) _rangeFor(TimerPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case TimerPeriod.week:
        final start = mondayOf(now);
        return (start: start, end: start.add(const Duration(days: 7)));
      case TimerPeriod.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start: start, end: end);
      case TimerPeriod.year:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);
        return (start: start, end: end);
    }
  }

  Map<DateTime, int> _groupByDay(List<StudySession> sessions) {
    final map = <DateTime, int>{};
    for (final s in sessions) {
      final day = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      map[day] = (map[day] ?? 0) + s.durationSeconds;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudyTimerRepository>();
    final range = _rangeFor(_period);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<TimerPeriod>(
          segments: const [
            ButtonSegment(value: TimerPeriod.week, label: Text('주간')),
            ButtonSegment(value: TimerPeriod.month, label: Text('월간')),
            ButtonSegment(value: TimerPeriod.year, label: Text('년간')),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<TimerViewMode>(
          segments: const [
            ButtonSegment(value: TimerViewMode.graph, label: Text('그래프')),
            ButtonSegment(value: TimerViewMode.list, label: Text('숫자')),
          ],
          selected: {_viewMode},
          onSelectionChanged: (s) => setState(() => _viewMode = s.first),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<StudySession>>(
          future: repo.getSessionsBetween(range.start, range.end),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final sessions = snapshot.data ?? const [];
            if (sessions.isEmpty) {
              return const EmptyState(message: '이 기간에 기록된 공부 시간이 없어요');
            }
            final byDay = _groupByDay(sessions);
            return _viewMode == TimerViewMode.graph ? _buildGraph(byDay) : _buildList(byDay);
          },
        ),
      ],
    );
  }

  Widget _buildGraph(Map<DateTime, int> byDay) {
    final days = byDay.keys.toList()..sort();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: byDay[days[i]]! / 60),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Map<DateTime, int> byDay) {
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      children: [
        for (final day in days)
          ListTile(
            title: Text(
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
            ),
            trailing: Text('${byDay[day]! ~/ 60}분'),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/timer/timer_history_view_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/timer/timer_history_view.dart mobile/test/features/timer/timer_history_view_test.dart
git commit -m "feat: add TimerHistoryView with week/month/year graph and list toggle"
```

---

### Task 6: TimerScreen — ticking display, start/pause/resume/end controls

**Files:**
- Create: `mobile/lib/features/timer/timer_screen.dart`
- Test: `mobile/test/features/timer/timer_screen_test.dart`

**Interfaces:**
- Consumes: `StudyTimerRepository` (Task 3, via `provider`), `ActiveSessionState` (Task 1), `WeeklyGoalCard` (Task 4), `TimerHistoryView` (Task 5).
- Produces: `TimerScreen` widget (`StatefulWidget`, no constructor params) — mounted by Task 7's `app.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/features/timer/timer_screen_test.dart
//
// IMPORTANT: TimerScreen starts a `Timer.periodic` once its initial
// `load()` completes. `pumpAndSettle()` pumps frames until none are
// scheduled — a periodic timer that keeps firing forever can make it loop
// until it hits its internal iteration cap and throw "pumpAndSettle timed
// out". So this file never calls `pumpAndSettle()` — it uses a bounded
// `settleOnce()` helper (a fixed number of short `pump()` calls) instead,
// both for flushing the initial async `load()` and after each tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/timer_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildScreen(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: TimerScreen()),
    );
  }

  Future<void> settleOnce(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('shows a 시작 button when there is no active session', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    expect(find.text('시작'), findsOneWidget);
    expect(find.text('일시정지'), findsNothing);
  });

  testWidgets('tapping 시작 switches to 일시정지/종료 buttons', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);

    expect(find.text('일시정지'), findsOneWidget);
    expect(find.text('종료'), findsOneWidget);
    expect(find.text('시작'), findsNothing);
  });

  testWidgets('tapping 일시정지 then 재개 returns to running state', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);
    await tester.tap(find.text('일시정지'));
    await settleOnce(tester);

    expect(find.text('재개'), findsOneWidget);

    await tester.tap(find.text('재개'));
    await settleOnce(tester);

    expect(find.text('일시정지'), findsOneWidget);
  });

  testWidgets('tapping 종료 returns to the initial 시작 state', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);
    await tester.tap(find.text('종료'));
    await settleOnce(tester);

    expect(find.text('시작'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/timer/timer_screen_test.dart
```
Expected: FAIL — `mobile/lib/features/timer/timer_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement TimerScreen**

```dart
// mobile/lib/features/timer/timer_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/active_session_state.dart';
import '../../data/study_timer_repository.dart';
import 'timer_history_view.dart';
import 'weekly_goal_card.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _ticker;
  int _displaySeconds = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // load() restores a persisted active session (e.g. the app was killed
    // mid-session) — activeSession is a sync getter and won't do this on
    // its own, so this must run before the first _tick().
    await context.read<StudyTimerRepository>().load();
    if (!mounted) return;
    setState(() => _loaded = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  void _tick() {
    if (!mounted) return;
    final active = context.read<StudyTimerRepository>().activeSession;
    setState(() => _displaySeconds = active?.elapsedSeconds() ?? 0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildButtons(StudyTimerRepository repo, ActiveSessionState? active) {
    if (active == null) {
      return [
        ElevatedButton(onPressed: () => repo.startSession(), child: const Text('시작')),
      ];
    }
    if (active.isPaused) {
      return [
        ElevatedButton(onPressed: () => repo.resumeSession(), child: const Text('재개')),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: () => repo.endSession(), child: const Text('종료')),
      ];
    }
    return [
      ElevatedButton(onPressed: () => repo.pauseSession(), child: const Text('일시정지')),
      const SizedBox(width: 12),
      OutlinedButton(onPressed: () => repo.endSession(), child: const Text('종료')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = context.watch<StudyTimerRepository>();
    final active = repo.activeSession;

    return Scaffold(
      appBar: AppBar(title: const Text('타이머')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              _format(active?.elapsedSeconds() ?? _displaySeconds),
              style: Theme.of(context).textTheme.displayMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildButtons(repo, active),
          ),
          const SizedBox(height: 24),
          const WeeklyGoalCard(),
          const SizedBox(height: 24),
          const TimerHistoryView(),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/timer/timer_screen_test.dart
```
Expected: `00:0X +4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/timer/timer_screen.dart mobile/test/features/timer/timer_screen_test.dart
git commit -m "feat: add TimerScreen with start/pause/resume/end controls"
```

---

### Task 7: Wire the 5th tab into app.dart and main.dart

**Files:**
- Modify: `mobile/lib/app.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/test/main_test.dart`

**Interfaces:**
- Consumes: `TimerScreen` (Task 6), `StudyTimerRepository`/`LocalStudyTimerRepository` (Task 3), `LearningRepository`/`LocalSQLiteRepository` (existing).
- Produces: nothing further — this is the final integration point for this feature.

- [ ] **Step 1: Write the failing test**

In `mobile/test/main_test.dart`, the existing smoke test wraps `EnglishHelperApp` with a single `ChangeNotifierProvider<LearningRepository>`. Since `app.dart` will now also require a `StudyTimerRepository` in scope (for `TimerScreen`), update the test's provider setup to a `MultiProvider` and extend the assertions to cover the new 5th tab. Replace the existing test file's `testWidgets` body with:

```dart
// mobile/test/main_test.dart
//
// IMPORTANT: app.dart's IndexedStack builds all 5 screens up front,
// including TimerScreen — so its Timer.periodic is running from the very
// first pumpWidget() call in this test, before any tab is even tapped.
// `pumpAndSettle()` pumps until no frame is scheduled, and a periodic
// timer that fires forever can make that loop until it hits its internal
// cap and throws "pumpAndSettle timed out". This file uses a bounded
// settleOnce() helper everywhere instead — never pumpAndSettle().
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> settleOnce(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('bottom navigation switches between all 5 screens', (tester) async {
    final learningRepo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final timerRepo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
          ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
        ],
        child: const EnglishHelperApp(),
      ),
    );
    await settleOnce(tester);

    expect(find.text('저장한 단어/문장'), findsOneWidget);

    await tester.tap(find.text('플래시카드'));
    await settleOnce(tester);
    expect(find.text('플래시카드'), findsWidgets);

    await tester.tap(find.text('가져오기'));
    await settleOnce(tester);
    expect(find.text('SQLite 파일 선택'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await settleOnce(tester);
    expect(find.text('모국어 (Native Language)'), findsOneWidget);

    await tester.tap(find.text('타이머'));
    await settleOnce(tester);
    expect(find.text('시작'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/main_test.dart
```
Expected: FAIL — `app.dart` doesn't yet import/mount `TimerScreen`, and there's no 5th `NavigationDestination` to tap.

- [ ] **Step 3: Update app.dart**

Replace the full contents of `mobile/lib/app.dart` with:

```dart
// mobile/lib/app.dart
import 'package:flutter/material.dart';

import 'features/flashcard/flashcard_screen.dart';
import 'features/home/home_screen.dart';
import 'features/import/import_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/timer/timer_screen.dart';

class EnglishHelperApp extends StatelessWidget {
  const EnglishHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Helper',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _RootShell(),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    FlashcardScreen(),
    ImportScreen(),
    SettingsScreen(),
    TimerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.style), label: '플래시카드'),
          NavigationDestination(icon: Icon(Icons.file_download), label: '가져오기'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
          NavigationDestination(icon: Icon(Icons.timer), label: '타이머'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Update main.dart**

Replace the full contents of `mobile/lib/main.dart` with:

```dart
// mobile/lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';
import 'data/study_timer_repository.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(),
        ),
      ],
      child: const EnglishHelperApp(),
    ),
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/main_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 6: Run the full suite**

```bash
cd mobile && flutter test
```
Expected: every test across the whole project (existing Phase B tests + this feature's tests) passes, 0 failures.

- [ ] **Step 7: Run the analyzer**

```bash
cd mobile && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/app.dart mobile/lib/main.dart mobile/test/main_test.dart
git commit -m "feat: wire the Timer tab into the app shell"
```

---

### Task 8: Run on a real simulator/emulator

**Files:** none (verification-only task).

**Interfaces:** none — this task drives the already-built app, it doesn't produce anything later tasks depend on.

- [ ] **Step 1: Launch the iOS simulator**

```bash
open -a Simulator
xcrun simctl list devices available | grep -i "iPhone 17\""
xcrun simctl boot <device-UUID-from-above> 2>&1 || true
```

- [ ] **Step 2: Run the app**

```bash
cd mobile && flutter run -d <device-UUID>
```
Expected: app builds, installs, and launches with 5 tabs visible in the bottom navigation, ending in "타이머".

- [ ] **Step 3: Manually verify the timer flow**

In the running simulator:
1. Tap the 타이머 tab — confirm the 00:00:00 display and a 시작 button.
2. Tap 시작 — confirm the display starts ticking up every second and the buttons switch to 일시정지/종료.
3. Tap 일시정지 — confirm the display freezes and the buttons switch to 재개/종료.
4. Wait a couple of seconds, tap 재개 — confirm the display resumes from where it froze (not from where it would be if it had kept running).
5. Tap 종료 — confirm it returns to the 00:00:00/시작 state, and that the 이번 주 목표 card and history section below now reflect the just-completed session (may need a moment/rebuild — confirm the numbers update without restarting the app).
6. Tap "목표 설정" and set a goal — confirm the progress bar appears and reflects the ratio of today's recorded time to the goal.
7. Switch between 주간/월간/년간 and between 그래프/숫자 — confirm no crashes and the displayed data changes appropriately.
8. Force-quit the app from the simulator's app switcher while a session is running, then relaunch — confirm the timer resumes counting from the correct elapsed time (not from zero).

- [ ] **Step 4: No commit** — this task only verifies Tasks 1–7's output runs; it makes no code changes.
