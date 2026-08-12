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
