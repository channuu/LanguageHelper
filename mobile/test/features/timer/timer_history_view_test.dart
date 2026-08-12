import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
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
