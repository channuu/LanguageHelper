import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/study_session.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/timer_history_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    addTearDown(repo.close);
    await tester.pumpWidget(buildView(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('기록된 공부 시간이 없어요'), findsOneWidget);
  });

  testWidgets('switching to list view shows minutes for a recorded session', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    addTearDown(repo.close);
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

  testWidgets('year period list view aggregates sessions by month, not by day', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);

    final year = DateTime.now().year;
    // Two sessions in January, spread over different days, plus one in July.
    final sessions = [
      StudySession(
        id: 'jan-1',
        startedAt: DateTime(year, 1, 5, 10),
        endedAt: DateTime(year, 1, 5, 10, 30),
        durationSeconds: 1800,
        savedAt: DateTime(year, 1, 5, 10, 30).toIso8601String(),
      ),
      StudySession(
        id: 'jan-2',
        startedAt: DateTime(year, 1, 20, 10),
        endedAt: DateTime(year, 1, 20, 10, 30),
        durationSeconds: 1800,
        savedAt: DateTime(year, 1, 20, 10, 30).toIso8601String(),
      ),
      StudySession(
        id: 'jul-1',
        startedAt: DateTime(year, 7, 15, 10),
        endedAt: DateTime(year, 7, 15, 10, 30),
        durationSeconds: 1800,
        savedAt: DateTime(year, 7, 15, 10, 30).toIso8601String(),
      ),
    ];
    for (final s in sessions) {
      await db.insert('study_sessions', s.toMap());
    }

    await tester.pumpWidget(buildView(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('년간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('숫자'));
    await tester.pumpAndSettle();

    // 2 different months of sessions should collapse into exactly 2 rows,
    // not one row per day (which would be 3, one per distinct day).
    expect(find.byType(ListTile), findsNWidgets(2));
    final janLabel = '$year-01';
    final julLabel = '$year-07';
    expect(find.textContaining(janLabel), findsOneWidget);
    expect(find.textContaining(julLabel), findsOneWidget);
  });
}
