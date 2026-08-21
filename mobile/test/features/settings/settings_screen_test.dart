import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/settings/settings_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen(LearningRepository repo, StudyTimerRepository timerRepo) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>.value(value: repo),
        ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets('defaults to Korean and persists a new selection via the choice sheet', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);

    await tester.tap(find.text('모국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('native_lang'), 'ja');
    expect(find.text('日本語'), findsOneWidget);
  });

  testWidgets('shows the DB path from the repository', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text(inMemoryDatabasePath), findsOneWidget);
  });

  testWidgets('shows the saved item count from the repository', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalSQLiteRepository(openDb: () async => db);
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    await repo.saveWord(const Word(
      id: 'w1', word: 'x', platform: 'youtube', contentTitle: 't', contentId: 'c', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
    ));
    await repo.saveSentence(const Sentence(
      id: 's1', original: 'x', platform: 'youtube', contentTitle: 't', contentId: 'c', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('editing 하루 복습 목표 via the stepper persists the new value', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('20개'), findsOneWidget); // default

    await tester.tap(find.text('하루 복습 목표'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('21개'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('daily_review_goal'), 21);
  });

  testWidgets('앞면에 표시 opens a choice sheet and persists the selection', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('영어'), findsOneWidget); // default

    await tester.tap(find.text('앞면에 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한글'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('flashcard_front'), 'ko');
  });

  testWidgets('출처 문장 함께 보기 toggles and persists immediately', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_source_sentence'), false); // default true, toggled off
  });

  testWidgets('주간 학습 목표 row opens the shared GoalSheet and saving updates StudyTimerRepository', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await timerRepo.setWeeklyGoal(300); // 5 hours

    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('5시간'), findsOneWidget);

    await tester.tap(find.text('주간 학습 목표'));
    await tester.pumpAndSettle();
    expect(find.text('주간 학습 목표'), findsWidgets); // sheet title + row label both present

    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await timerRepo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 360);
    expect(find.text('6시간'), findsOneWidget);
  });
}
