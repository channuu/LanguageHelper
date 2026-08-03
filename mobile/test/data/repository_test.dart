import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/repository.dart';

Word _word(String id, {int reviewCount = 0}) => Word(
      id: id,
      word: 'w-$id',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
      reviewCount: reviewCount,
    );

Sentence _sentence(String id) => Sentence(
      id: id,
      original: 's-$id',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalSQLiteRepository repo;

  setUp(() {
    repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
  });

  tearDown(() async {
    await repo.close();
  });

  test('saveWord then getWords returns the saved word', () async {
    await repo.saveWord(_word('w1'));
    final words = await repo.getWords();
    expect(words, hasLength(1));
    expect(words.first.id, 'w1');
  });

  test('saveSentence then getSentences returns the saved sentence', () async {
    await repo.saveSentence(_sentence('s1'));
    final sentences = await repo.getSentences();
    expect(sentences, hasLength(1));
    expect(sentences.first.id, 's1');
  });

  test('deleteWord removes only the matching word', () async {
    await repo.saveWord(_word('w1'));
    await repo.saveWord(_word('w2'));
    await repo.deleteWord('w1');
    final words = await repo.getWords();
    expect(words.map((w) => w.id), ['w2']);
  });

  test('deleteSentence removes only the matching sentence', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.saveSentence(_sentence('s2'));
    await repo.deleteSentence('s1');
    final sentences = await repo.getSentences();
    expect(sentences.map((s) => s.id), ['s2']);
  });

  test('markWordReviewed increments reviewCount and sets nextReviewAt', () async {
    await repo.saveWord(_word('w1', reviewCount: 2));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewCount, 3);
    expect(word.nextReviewAt, isNotNull);
  });

  test('markSentenceReviewed increments reviewCount and sets nextReviewAt', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.markSentenceReviewed('s1');
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewCount, 1);
    expect(sentence.nextReviewAt, isNotNull);
  });

  test('getDatabasePath returns the path of the open database', () async {
    final path = await repo.getDatabasePath();
    expect(path, inMemoryDatabasePath);
  });

  test('notifies listeners on save, delete, and markReviewed', () async {
    var notifications = 0;
    repo.addListener(() => notifications++);

    await repo.saveWord(_word('w1'));
    expect(notifications, 1);

    await repo.markWordReviewed('w1');
    expect(notifications, 2);

    await repo.deleteWord('w1');
    expect(notifications, 3);
  });

  group('mergeFromFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eh_import_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('merges new rows and ignores duplicate ids, counts correctly', () async {
      // Local DB already has w1 with progress.
      await repo.saveWord(_word('w1', reviewCount: 5));

      // Import file has w1 (duplicate, should be ignored) and w2 (new),
      // plus one new sentence.
      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await openAppDatabase(importPath);
      await importDb.insert('words', _word('w1', reviewCount: 0).toMap());
      await importDb.insert('words', _word('w2').toMap());
      await importDb.insert('sentences', _sentence('s1').toMap());
      await importDb.close();

      final result = await repo.mergeFromFile(importPath);

      expect(result.newWords, 1);
      expect(result.newSentences, 1);

      final words = await repo.getWords();
      expect(words.map((w) => w.id).toSet(), {'w1', 'w2'});
      // Local progress on w1 must be untouched by the import.
      expect(words.firstWhere((w) => w.id == 'w1').reviewCount, 5);
    });

    test('throws InvalidBackupFileException for a file with the wrong schema', () async {
      final badPath = '${tempDir.path}/bad.sqlite';
      final badDb = await databaseFactory.openDatabase(badPath);
      await badDb.execute('CREATE TABLE not_words (id TEXT)');
      await badDb.close();

      expect(
        () => repo.mergeFromFile(badPath),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });
  });
}
