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
    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('목표'), findsWidgets);
  });

  testWidgets('shows a 7-day bar chart with H:MM totals once a goal is set', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
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
    await repo.setWeeklyGoal(1); // 1 minute — trivially achievable

    final monday = mondayOf(DateTime.now());
    await db.insert('study_sessions', {
      'id': 's2',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 9, minutes: 5)).toIso8601String(),
      'duration_seconds': 300,
      'saved_at': monday.add(const Duration(hours: 9, minutes: 5)).toIso8601String(),
    });

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('달성했어요'), findsOneWidget);
  });
}
