import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/weekly_goal_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    addTearDown(repo.close);
    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('목표'), findsWidgets);
  });

  testWidgets('shows a 7-day bar chart with H:MM totals once a goal is set', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);
    await repo.setWeeklyGoal(300); // 5 hours

    final monday = mondayOf(DateTime.now());
    // 1h12m on Monday.
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 10, minutes: 12)).toIso8601String(),
      'duration_seconds': 4320,
      'saved_at': monday.add(const Duration(hours: 10, minutes: 12)).toIso8601String(),
    });

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    // Header shows H:MM total / H:MM goal.
    expect(find.textContaining('1:12'), findsOneWidget);
    expect(find.textContaining('5:00'), findsOneWidget);
    // 7 day-of-week labels.
    for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('shows the achieved message once the goal is met', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);
    await repo.setWeeklyGoal(60); // 1 hour — goals are whole hours now

    final monday = mondayOf(DateTime.now());
    await db.insert('study_sessions', {
      'id': 's2',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 10, minutes: 5)).toIso8601String(),
      'duration_seconds': 3900, // 1h05m, over the 1-hour goal
      'saved_at': monday.add(const Duration(hours: 10, minutes: 5)).toIso8601String(),
    });

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('달성했습니다'), findsOneWidget);
  });

  testWidgets('tapping the card opens the goal sheet with the current goal preselected', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.setWeeklyGoal(420); // 7 hours

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주 목표'));
    await tester.pumpAndSettle();

    expect(find.text('주간 학습 목표'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // preselected draft hours
    expect(find.text('7시간'), findsOneWidget); // matching preset highlighted
  });

  testWidgets('adjusting with +/- and saving updates the goal', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.setWeeklyGoal(300); // 5 hours

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주 목표'));
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await repo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 360);
    expect(find.textContaining('6:00'), findsOneWidget);
  });

  testWidgets('tapping 취소 discards the draft change', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.setWeeklyGoal(300); // 5 hours

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주 목표'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(await repo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 300);
    expect(find.textContaining('5:00'), findsOneWidget);
  });

  testWidgets('a preset button jumps the draft directly to that value', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.setWeeklyGoal(300); // 5 hours

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주 목표'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10시간'));
    await tester.pumpAndSettle();

    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await repo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 600);
  });

  testWidgets('the empty-state "목표 설정" prompt also opens the goal sheet', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주 목표를 설정해보세요'));
    await tester.pumpAndSettle();

    expect(find.text('주간 학습 목표'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // default draft when no goal exists yet

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await repo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 300);
  });
}
