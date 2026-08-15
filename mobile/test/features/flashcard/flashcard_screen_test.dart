import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/flashcard/flashcard_screen.dart';

Word _dueWord({String id = 'w1', int reviewLevel = 0, String? lastReviewedAt}) => Word(
      id: id, word: 'ephemeral', definition: 'lasting for a very short time',
      translation: '덧없는', platform: 'netflix', contentTitle: 'Title',
      contentId: 'c1', timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: reviewLevel, lastReviewedAt: lastReviewedAt,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildApp(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: FlashcardScreen()),
    );
  }

  testWidgets('shows empty state when there is nothing saved', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('shows the prompt (not the raw word) on the front of a due card', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('덧없는'), findsOneWidget); // prompt = translation
    expect(find.text('ephemeral'), findsNothing); // answer not shown yet
  });

  testWidgets('typing the correct answer and submitting shows correct feedback', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ephemeral'); // case-insensitive match
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('정답'), findsWidgets);
  });

  testWidgets('typing a wrong answer shows the correct answer inline', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrongword');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('오답'), findsWidgets);
    expect(find.textContaining('ephemeral'), findsWidgets); // correct answer revealed
  });

  testWidgets('submitting an empty answer does not grade', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('정답'), findsNothing);
    expect(find.textContaining('오답'), findsNothing);
  });

  testWidgets('알아요 is only visible after flipping to the back', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('알아요'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('flashcard-body')));
    await tester.pumpAndSettle();

    expect(find.text('알아요'), findsOneWidget);
  });

  testWidgets('알아요 marks the word reviewed and does not show the typed answer on the back', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'my typed guess');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flashcard-body')));
    await tester.pumpAndSettle();

    // Back view shows the correct detail, never the user's raw input string.
    expect(find.text('my typed guess'), findsNothing);
    expect(find.text('lasting for a very short time'), findsOneWidget);

    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 1);
  });

  testWidgets('다시 requeues without touching the database', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('다시'));
    await tester.pumpAndSettle();

    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 0);
    expect(word.lastReviewedAt, isNull);
    // Single-item queue: 다시 requeues it, so it's still showing.
    expect(find.text('덧없는'), findsOneWidget);
  });

  testWidgets('an item not yet due is excluded from the queue', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
    await repo.saveWord(Word(
      id: 'w1', word: 'ephemeral', translation: '덧없는', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: 2, nextReviewAt: future,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
  });

  testWidgets('reloads the queue automatically after an import while empty', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);

    await repo.saveWord(_dueWord());
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsNothing);
    expect(find.text('덧없는'), findsOneWidget);
  });
}
