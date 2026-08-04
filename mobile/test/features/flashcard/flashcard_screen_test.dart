import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/flashcard/flashcard_screen.dart';

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

  testWidgets('shows empty state when there is nothing to review', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('tapping the card flips it to show the back', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('lasting for a very short time'), findsNothing);

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('lasting for a very short time'), findsOneWidget);
  });

  testWidgets('알아요 removes the card and marks it reviewed', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral')); // flip
    await tester.pumpAndSettle();
    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
    final words = await repo.getWords();
    expect(words.single.reviewCount, 1);
  });
}
