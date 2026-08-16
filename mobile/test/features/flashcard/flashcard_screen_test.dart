import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/review_schedule.dart';
import 'package:english_helper_app/features/flashcard/flashcard_screen.dart';
import 'package:english_helper_app/data/models/sentence.dart';

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

  testWidgets('list mode shows all saved items regardless of due date', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
    await repo.saveWord(_dueWord(id: 'w1'));
    await repo.saveWord(Word(
      id: 'w2', word: 'brief', translation: '짧은', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z', reviewLevel: 2, nextReviewAt: future,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget); // not-yet-due item still shows in list mode
  });

  testWidgets('level filter chip narrows the list', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(id: 'w1', reviewLevel: 0));
    await repo.saveWord(Word(
      id: 'w2', word: 'brief', translation: '짧은', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z', reviewLevel: 2,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget);

    // find.text(kReviewLevelNames[2]) would be ambiguous here: the level-2
    // filter chip AND the "brief" list item's own level badge both render
    // '복습 필요' simultaneously. Target the chip by its key instead.
    await tester.tap(find.byKey(const ValueKey('level-chip-2')));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(find.text('brief'), findsOneWidget);
  });

  testWidgets('type filter narrows both card and list mode', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(id: 'w1'));
    await repo.saveSentence(Sentence(
      id: 's1', original: 'Nothing in life is ephemeral.', translation: '인생에서 덧없지 않은 것은 없다.',
      platform: 'youtube', contentTitle: 'Video', contentId: 'c2',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('Nothing in life is ephemeral.'), findsOneWidget);

    await tester.tap(find.text('단어'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('Nothing in life is ephemeral.'), findsNothing);
  });

  testWidgets('tapping + opens the add sheet, saving creates a new word', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(find.text('새 항목'), findsWidgets); // sheet title or level-0 row

    await tester.enterText(find.byKey(const ValueKey('edit-en-field')), 'ephemeral');
    await tester.enterText(find.byKey(const ValueKey('edit-ko-field')), '덧없는');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words, hasLength(1));
    expect(words.single.word, 'ephemeral');
    expect(words.single.translation, '덧없는');
  });

  testWidgets('tapping a list item opens the edit sheet pre-filled, saving updates it', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('항목 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ephemeral'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('edit-ko-field')), '수정된 뜻');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words.single.translation, '수정된 뜻');
    expect(words.single.id, 'w1'); // same id, upserted not duplicated
  });

  testWidgets('editing an existing word preserves nextReviewAt, reviewCount, and definition', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(Word(
      id: 'w1', word: 'ephemeral', definition: 'lasting for a very short time',
      translation: '덧없는', platform: 'netflix', contentTitle: 'Title',
      contentId: 'c1', timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: 3, reviewCount: 5,
      nextReviewAt: '2099-01-01T00:00:00.000Z',
      lastReviewedAt: '2026-08-10T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('edit-ko-field')), '수정된 뜻');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final word = (await repo.getWords()).single;
    expect(word.translation, '수정된 뜻'); // the edited field
    expect(word.definition, 'lasting for a very short time'); // preserved
    expect(word.reviewCount, 5); // preserved
    expect(word.nextReviewAt, '2099-01-01T00:00:00.000Z'); // preserved
    expect(word.lastReviewedAt, '2026-08-10T00:00:00.000Z'); // preserved
  });

  testWidgets('delete button only shows when editing, and deletes the item', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(find.text('삭제'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();
    expect(find.text('삭제'), findsOneWidget);

    // The sheet's content overflows the visible viewport, so the delete
    // button sits below the fold inside the SingleChildScrollView.
    await tester.ensureVisible(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words, isEmpty);
  });

  testWidgets('tapping a review level in the sheet applies it immediately', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(reviewLevel: 0));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    // find.text(kReviewLevelNames[3]) alone would be ambiguous: the
    // level-filter chip row in the (still-mounted) list behind the sheet
    // uses the same label. Scope the tap to inside the modal bottom sheet.
    final levelRowInSheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(kReviewLevelNames[3]),
    );
    await tester.ensureVisible(levelRowInSheet);
    await tester.pumpAndSettle();
    await tester.tap(levelRowInSheet);
    await tester.pumpAndSettle();

    // Applied immediately, independent of 저장/취소.
    final words = await repo.getWords();
    expect(words.single.reviewLevel, 3);
  });
}
