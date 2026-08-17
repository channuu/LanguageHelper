import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/home/home_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // Use the no-isolate FFI factory: the isolate-based `databaseFactoryFfi`
    // communicates via a background Isolate, whose messages never get
    // flushed inside flutter_test's FakeAsync zone (used by testWidgets),
    // so a FutureBuilder awaiting a query would hang forever under
    // pumpAndSettle. The no-isolate variant runs queries synchronously in
    // zone, which FakeAsync can flush like any other Future.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // Every test in this file uses inMemoryDatabasePath, and the no-isolate
  // ffi factory caches connections by path (singleInstance: true) — without
  // closing each repo, data from one test leaks into the next. See
  // test/data/study_timer_repository_test.dart and
  // test/features/flashcard/flashcard_screen_test.dart for the same pattern.
  Future<LocalSQLiteRepository> makeRepo() async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    addTearDown(repo.close);
    return repo;
  }

  Widget buildApp(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('shows empty state when there are no saved items', (tester) async {
    final repo = await makeRepo();

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('tapping a word list tile navigates to its detail screen', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'youtube',
      contentTitle: 'Some Video',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 142.5,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsOneWidget);
  });

  testWidgets('word/sentence segment toggle shows correct counts', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveSentence(Sentence(
      id: 's1',
      original: 'Nothing in life is ephemeral.',
      platform: 'youtube',
      contentTitle: 'V',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveSentence(Sentence(
      id: 's2',
      original: 'Another saved line.',
      platform: 'netflix',
      contentTitle: 'W',
      contentId: '81234567',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget); // 단어 count
    expect(find.text('2'), findsOneWidget); // 문장 count
  });

  testWidgets('platform filter chip narrows the word list', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveWord(Word(
      id: 'w2',
      word: 'brief',
      platform: 'netflix',
      contentTitle: 'V2',
      contentId: '81234567',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget);

    await tester.tap(find.text('netflix'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(find.text('brief'), findsOneWidget);
  });

  testWidgets('search narrows the word list by headline substring', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveWord(Word(
      id: 'w2',
      word: 'brief',
      platform: 'youtube',
      contentTitle: 'V2',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ephem');
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsNothing);
  });

  testWidgets('search with no matches shows the no-results empty state', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz_no_match');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과가 없어요'), findsOneWidget);
  });

  testWidgets('swipe still deletes a word', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('ephemeral'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(await repo.getWords(), isEmpty);
  });

  testWidgets('reloads list when repository notifies after mount (e.g. import from another tab)', (tester) async {
    final repo = await makeRepo();

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);

    // Simulate a word being imported while HomeScreen is already mounted
    // (e.g. the persistent IndexedStack keeps HomeScreen alive while the
    // user is on the Import tab), rather than being recreated.
    await repo.saveWord(Word(
      id: 'w1',
      word: 'newly-added-word',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await tester.pumpAndSettle();

    expect(find.text('newly-added-word'), findsOneWidget);
  });
}
