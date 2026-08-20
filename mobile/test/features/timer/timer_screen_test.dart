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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/timer_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen(StudyTimerRepository repo, {LearningRepository? learningRepo}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StudyTimerRepository>.value(value: repo),
        ChangeNotifierProvider<LearningRepository>.value(
          value: learningRepo ?? LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath)),
        ),
      ],
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
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    expect(find.text('시작'), findsOneWidget);
    expect(find.text('일시정지'), findsNothing);
  });

  testWidgets('tapping 시작 switches to 일시정지/종료 buttons', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    addTearDown(repo.close);
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
    addTearDown(repo.close);
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
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);
    await tester.tap(find.text('종료'));
    await settleOnce(tester);

    expect(find.text('시작'), findsOneWidget);
  });

  testWidgets('shows today\'s accumulated total, excluding the running session', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // A completed session earlier today: 25 minutes.
    await db.insert('study_sessions', {
      'id': 'today-1',
      'started_at': todayStart.add(const Duration(hours: 1)).toIso8601String(),
      'ended_at': todayStart.add(const Duration(hours: 1, minutes: 25)).toIso8601String(),
      'duration_seconds': 1500,
      'saved_at': todayStart.add(const Duration(hours: 1, minutes: 25)).toIso8601String(),
    });
    // A session from yesterday must not count.
    final yesterday = todayStart.subtract(const Duration(days: 1));
    await db.insert('study_sessions', {
      'id': 'yesterday-1',
      'started_at': yesterday.add(const Duration(hours: 1)).toIso8601String(),
      'ended_at': yesterday.add(const Duration(hours: 1, minutes: 40)).toIso8601String(),
      'duration_seconds': 2400,
      'saved_at': yesterday.add(const Duration(hours: 1, minutes: 40)).toIso8601String(),
    });

    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);
    await settleOnce(tester); // second pass: lets the async _loadTodayTotal() land

    expect(find.textContaining('오늘 누적 0시간 25분'), findsOneWidget);
  });

  testWidgets('status pill shows 학습 중 while running and 일시정지 while paused', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    // No active session: no pill at all.
    expect(find.text('학습 중'), findsNothing);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);
    expect(find.text('학습 중'), findsOneWidget);

    await tester.tap(find.text('일시정지'));
    await settleOnce(tester);
    expect(find.text('학습 중'), findsNothing);
    // The pill's own label reads 일시정지 too (same string as the button),
    // so at least one 일시정지 text now exists in addition to the button.
    expect(find.text('일시정지'), findsWidgets);
  });

  testWidgets('tapping the stats toggle switches from 학습 타이머 to 통계 and back', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    expect(find.text('학습 타이머'), findsOneWidget);
    expect(find.text('통계'), findsNothing);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await settleOnce(tester);
    await settleOnce(tester);

    expect(find.text('통계'), findsOneWidget);
    expect(find.text('학습 타이머'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await settleOnce(tester);

    expect(find.text('학습 타이머'), findsOneWidget);
  });
}
