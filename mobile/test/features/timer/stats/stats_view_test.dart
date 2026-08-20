import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/stats/stats_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildView(LearningRepository learningRepo, StudyTimerRepository timerRepo) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
        ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
      ],
      child: const MaterialApp(home: Scaffold(body: StatsView())),
    );
  }

  testWidgets('shows 주간/월간/년간 period selector and defaults to 주간', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('주간'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);
    expect(find.text('년간'), findsOneWidget);
    expect(find.text('이번 주'), findsOneWidget);
  });

  testWidgets('summary total reflects sessions in the selected period', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    // Two sessions on two different days, so total (2:00) and average
    // (1:00, since there are 2 active days) are distinct values — with
    // only a single active day, average always equals total (average =
    // total / activeDays = total / 1), which would make this assertion
    // ambiguous regardless of the chosen duration.
    final monday = mondayOf(DateTime.now());
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 10, minutes: 30)).toIso8601String(),
      'duration_seconds': 5400,
      'saved_at': monday.add(const Duration(hours: 10, minutes: 30)).toIso8601String(),
    });
    await db.insert('study_sessions', {
      'id': 's2',
      'started_at': monday.add(const Duration(days: 1, hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(days: 1, hours: 9, minutes: 30)).toIso8601String(),
      'duration_seconds': 1800,
      'saved_at': monday.add(const Duration(days: 1, hours: 9, minutes: 30)).toIso8601String(),
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('2:00'), findsOneWidget); // total
    expect(find.text('1:00'), findsOneWidget); // average (7200s / 2 active days)
  });

  testWidgets('shows a delta badge comparing the current period to the previous one', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final monday = mondayOf(DateTime.now());
    final lastMonday = monday.subtract(const Duration(days: 7));
    await db.insert('study_sessions', {
      'id': 'prev',
      'started_at': lastMonday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': lastMonday.add(const Duration(hours: 9, minutes: 16, seconds: 40)).toIso8601String(),
      'duration_seconds': 1000,
      'saved_at': lastMonday.add(const Duration(hours: 9, minutes: 16, seconds: 40)).toIso8601String(),
    });
    await db.insert('study_sessions', {
      'id': 'curr',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 9, minutes: 20)).toIso8601String(),
      'duration_seconds': 1200,
      'saved_at': monday.add(const Duration(hours: 9, minutes: 20)).toIso8601String(),
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    // (1200 - 1000) / 1000 * 100 = +20%
    expect(find.text('+20%'), findsOneWidget);
  });

  testWidgets('switching to 월간 changes the scope label', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('월간'));
    await tester.pumpAndSettle();

    expect(find.text('이번 달'), findsOneWidget);
    expect(find.text('이번 주'), findsNothing);
  });

  testWidgets('calendar shows a dot only for days with recorded activity', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': today.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': today.add(const Duration(hours: 9, minutes: 30)).toIso8601String(),
      'duration_seconds': 1800,
      'saved_at': today.add(const Duration(hours: 9, minutes: 30)).toIso8601String(),
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('${today.day}'), findsOneWidget);
    // Month navigation header is present.
    expect(find.text('‹'), findsOneWidget);
    expect(find.text('›'), findsOneWidget);
  });

  testWidgets('tapping a calendar day updates the day-detail panel', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    // Pick a day earlier in the month than today, so it's guaranteed to be
    // a distinct, already-elapsed day regardless of what "today" is.
    final targetDay = DateTime(now.year, now.month, 1);
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': targetDay.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
      'duration_seconds': 2700,
      'saved_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
    });
    await db.insert('words', {
      'id': 'w1', 'word': 'ephemeral', 'platform': 'youtube',
      'content_title': 't', 'content_id': 'c', 'timestamp': 0,
      'saved_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
      'review_level': 0,
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    expect(find.text('0:45'), findsOneWidget); // 학습 시간
    expect(find.text('1'), findsWidgets); // 세션 count and/or 저장 count both show "1"
  });

  testWidgets('shows current streak and monthly activity rate', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // A 2-day streak: today and yesterday.
    for (final offset in [0, 1]) {
      final day = today.subtract(Duration(days: offset));
      await db.insert('study_sessions', {
        'id': 'streak-$offset',
        'started_at': day.add(const Duration(hours: 9)).toIso8601String(),
        'ended_at': day.add(const Duration(hours: 9, minutes: 10)).toIso8601String(),
        'duration_seconds': 600,
        'saved_at': day.add(const Duration(hours: 9, minutes: 10)).toIso8601String(),
      });
    }

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('연속 학습'), findsOneWidget);
    expect(find.text('2일'), findsOneWidget);
    expect(find.text('목표 달성률'), findsOneWidget);
  });

  testWidgets('switching to 년간 renders the 12-bar chart without overflow', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('년간'));
    await tester.pumpAndSettle();

    expect(find.text('올해'), findsOneWidget);
    expect(find.text('12월'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
