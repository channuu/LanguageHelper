import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/review_schedule.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('markWordReviewed increments reviewCount, bumps reviewLevel, and schedules nextReviewAt', () async {
    await repo.saveWord(_word('w1', reviewCount: 2));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewCount, 3);
    expect(word.reviewLevel, 1);
    expect(word.lastReviewedAt, isNotNull);
    expect(word.nextReviewAt, isNotNull);
  });

  test('markWordReviewed caps reviewLevel at kMaxReviewLevel', () async {
    await repo.saveWord(_word('w1').copyWith(reviewLevel: kMaxReviewLevel));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, kMaxReviewLevel);
  });

  test('markSentenceReviewed increments reviewCount, bumps reviewLevel, and schedules nextReviewAt', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.markSentenceReviewed('s1');
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewCount, 1);
    expect(sentence.reviewLevel, 1);
    expect(sentence.lastReviewedAt, isNotNull);
    expect(sentence.nextReviewAt, isNotNull);
  });

  test('setWordReviewLevel sets an arbitrary level directly', () async {
    await repo.saveWord(_word('w1'));
    await repo.setWordReviewLevel('w1', 3);
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 3);
    expect(word.lastReviewedAt, isNotNull);
    expect(word.nextReviewAt, isNotNull);
  });

  test('setWordReviewLevel(id, 0) clears a pre-existing nextReviewAt', () async {
    await repo.saveWord(_word('w1').copyWith(
      reviewLevel: 2,
      nextReviewAt: '2026-08-08T00:00:00.000Z',
    ));
    await repo.setWordReviewLevel('w1', 0);
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 0);
    expect(word.nextReviewAt, isNull);
  });

  test('setSentenceReviewLevel sets an arbitrary level directly', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.setSentenceReviewLevel('s1', 0);
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewLevel, 0);
    expect(sentence.nextReviewAt, isNull); // level 0 has no schedule
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
      // plus one new sentence. Create a backup-compatible database
      // (without review_level columns) for the import.
      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await databaseFactory.openDatabase(
        importPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS words (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                definition TEXT,
                sentence TEXT,
                translation TEXT,
                platform TEXT,
                content_title TEXT,
                content_id TEXT,
                timestamp REAL,
                saved_at TEXT,
                review_count INTEGER DEFAULT 0,
                next_review_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sentences (
                id TEXT PRIMARY KEY,
                original TEXT NOT NULL,
                translation TEXT,
                platform TEXT,
                content_title TEXT,
                content_id TEXT,
                timestamp REAL,
                saved_at TEXT,
                review_count INTEGER DEFAULT 0,
                next_review_at TEXT
              )
            ''');
          },
        ),
      );
      // Insert without review_level/last_reviewed_at to simulate a Chrome
      // extension backup file (which doesn't know about those columns).
      final w1Map = _word('w1', reviewCount: 0).toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      final w2Map = _word('w2').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      final s1Map = _sentence('s1').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');

      await importDb.insert('words', w1Map);
      await importDb.insert('words', w2Map);
      await importDb.insert('sentences', s1Map);
      await importDb.close();

      final result = await repo.mergeFromFile(importPath);

      expect(result.newWords, 1);
      expect(result.newSentences, 1);
      expect(result.skippedWords, 1); // w1 was a duplicate
      expect(result.skippedSentences, 0);

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

    test('throws InvalidBackupFileException for a file whose words table has an extra column', () async {
      final extraColsPath = '${tempDir.path}/extra_cols.sqlite';
      final extraColsDb = await openAppDatabase(extraColsPath);
      await extraColsDb.execute('ALTER TABLE words ADD COLUMN extra_column TEXT');
      await extraColsDb.close();

      expect(
        () => repo.mergeFromFile(extraColsPath),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });
  });

  group('getLastImportSummary', () {
    test('returns null before any import has happened', () async {
      final summary = await repo.getLastImportSummary();
      expect(summary, isNull);
    });

    test('returns the most recent import summary after a successful merge', () async {
      final tempDir = await Directory.systemTemp.createTemp('eh_last_import_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await databaseFactory.openDatabase(
        importPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS words (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                definition TEXT,
                sentence TEXT,
                translation TEXT,
                platform TEXT,
                content_title TEXT,
                content_id TEXT,
                timestamp REAL,
                saved_at TEXT,
                review_count INTEGER DEFAULT 0,
                next_review_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sentences (
                id TEXT PRIMARY KEY,
                original TEXT NOT NULL,
                translation TEXT,
                platform TEXT,
                content_title TEXT,
                content_id TEXT,
                timestamp REAL,
                saved_at TEXT,
                review_count INTEGER DEFAULT 0,
                next_review_at TEXT
              )
            ''');
          },
        ),
      );
      final w1Map = _word('w1').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      final s1Map = _sentence('s1').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      await importDb.insert('words', w1Map);
      await importDb.insert('sentences', s1Map);
      await importDb.close();

      await repo.mergeFromFile(importPath);
      final summary = await repo.getLastImportSummary();

      expect(summary, isNotNull);
      expect(summary!.newWords, 1);
      expect(summary.newSentences, 1);
      expect(summary.skippedWords, 0);
      expect(summary.skippedSentences, 0);
      expect(summary.importedAt.difference(DateTime.now()).abs() < const Duration(seconds: 5), isTrue);
    });

    test('a failed import (invalid backup file) does not update the summary', () async {
      final tempDir = await Directory.systemTemp.createTemp('eh_last_import_fail_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final badPath = '${tempDir.path}/bad.sqlite';
      final badDb = await databaseFactory.openDatabase(badPath);
      await badDb.execute('CREATE TABLE not_words (id TEXT)');
      await badDb.close();

      await expectLater(
        () => repo.mergeFromFile(badPath),
        throwsA(isA<InvalidBackupFileException>()),
      );

      final summary = await repo.getLastImportSummary();
      expect(summary, isNull);
    });
  });
}
