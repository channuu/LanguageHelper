// mobile/test/main_test.dart
//
// IMPORTANT: app.dart's IndexedStack builds all 5 screens up front,
// including TimerScreen — so its Timer.periodic is running from the very
// first pumpWidget() call in this test, before any tab is even tapped.
// `pumpAndSettle()` pumps until no frame is scheduled, and a periodic
// timer that fires forever can make that loop until it hits its internal
// cap and throws "pumpAndSettle timed out". This file uses a bounded
// settleOnce() helper everywhere instead — never pumpAndSettle().
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
