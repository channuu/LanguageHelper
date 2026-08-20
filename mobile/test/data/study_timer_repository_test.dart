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

  tearDown(() async {
    // sqflite caches connections by path (singleInstance: true), and
    // inMemoryDatabasePath is the same literal every test — without
    // closing, all tests in this file would silently share one database.
    await repo.close();
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

    test('changing the goal a second time within the same week returns the newest value', () async {
      // Both calls have the same effective_from (mondayOf the current week),
      // so the read query must break the tie by recency, not leave it to
      // SQLite's unspecified same-key ordering.
      await repo.setWeeklyGoal(300);
      await repo.setWeeklyGoal(360);
      final thisWeek = await repo.getWeeklyGoalMinutes(mondayOf(clock.current));
      expect(thisWeek, 360);
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
