// mobile/test/data/database_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('openAppDatabase', () {
    test('creates words and sentences tables with expected columns', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);

      final wordsCols = (await db.rawQuery('PRAGMA table_info(words)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        wordsCols,
        {
          'id', 'word', 'definition', 'sentence', 'translation', 'platform',
          'content_title', 'content_id', 'timestamp', 'saved_at',
          'review_count', 'next_review_at',
        },
      );

      final sentencesCols = (await db.rawQuery('PRAGMA table_info(sentences)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        sentencesCols,
        {
          'id', 'original', 'translation', 'platform', 'content_title',
          'content_id', 'timestamp', 'saved_at', 'review_count',
          'next_review_at',
        },
      );

      await db.close();
    });

    test('is idempotent — opening twice does not error', () async {
      final db1 = await openAppDatabase(inMemoryDatabasePath);
      await db1.close();
      final db2 = await openAppDatabase(inMemoryDatabasePath);
      await db2.close();
    });

    test('creates study_sessions and weekly_goals tables with expected columns', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);

      final sessionsCols = (await db.rawQuery('PRAGMA table_info(study_sessions)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(sessionsCols, {'id', 'started_at', 'ended_at', 'duration_seconds', 'saved_at'});

      final goalsCols = (await db.rawQuery('PRAGMA table_info(weekly_goals)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(goalsCols, {'id', 'target_minutes', 'effective_from', 'created_at'});

      await db.close();
    });
  });

  group('hasValidSchema', () {
    test('returns true for a database created by openAppDatabase', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);
      expect(await hasValidSchema(db), isTrue);
      await db.close();
    });

    test('returns false for a database missing the sentences table', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE words (id TEXT PRIMARY KEY, word TEXT)');
      expect(await hasValidSchema(db), isFalse);
      await db.close();
    });

    test('returns false for a words table missing a required column', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE words (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE sentences (id TEXT PRIMARY KEY, original TEXT)');
      expect(await hasValidSchema(db), isFalse);
      await db.close();
    });

    test('returns false for a words table with an extra column', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);
      await db.execute('ALTER TABLE words ADD COLUMN extra_column TEXT');
      expect(await hasValidSchema(db), isFalse);
      await db.close();
    });

    test('ignores study_sessions/weekly_goals when validating an import file', () async {
      // A file with only words/sentences (like a real Chrome-extension export)
      // must still validate, even though the app's own DB also has the two
      // timer tables — hasValidSchema must not require them.
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE words (
          id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT, sentence TEXT,
          translation TEXT, platform TEXT, content_title TEXT, content_id TEXT,
          timestamp REAL, saved_at TEXT, review_count INTEGER DEFAULT 0, next_review_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE sentences (
          id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT, platform TEXT,
          content_title TEXT, content_id TEXT, timestamp REAL, saved_at TEXT,
          review_count INTEGER DEFAULT 0, next_review_at TEXT
        )
      ''');
      expect(await hasValidSchema(db), isTrue);
      await db.close();
    });
  });

  group('schema migration', () {
    test('adds study_sessions/weekly_goals to a pre-existing v1 (Phase B) database', () async {
      // Use a real file on disk (not the in-memory path) because an
      // in-memory database does not persist data across close/reopen —
      // we need the "upgrade" to see the tables created by the first open.
      final tempDir = await Directory.systemTemp.createTemp('db_migration_test');
      final dbPath = p.join(tempDir.path, 'phase_b.sqlite');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // Simulate a pre-existing Phase B install: a v1 database with only
      // words/sentences, created the way the old openAppDatabase would have.
      final v1Db = await databaseFactory.openDatabase(
        dbPath,
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

      final tablesBefore = (await v1Db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(tablesBefore.contains('study_sessions'), isFalse);
      expect(tablesBefore.contains('weekly_goals'), isFalse);

      await v1Db.close();

      // Reopen the same database file with the current (v2) openAppDatabase,
      // which should trigger onUpgrade and add the two missing tables.
      final upgradedDb = await openAppDatabase(dbPath);

      final sessionsCols = (await upgradedDb.rawQuery('PRAGMA table_info(study_sessions)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(sessionsCols, {'id', 'started_at', 'ended_at', 'duration_seconds', 'saved_at'});

      final goalsCols = (await upgradedDb.rawQuery('PRAGMA table_info(weekly_goals)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(goalsCols, {'id', 'target_minutes', 'effective_from', 'created_at'});

      // words/sentences must still be intact.
      expect(await hasValidSchema(upgradedDb), isTrue);

      await upgradedDb.close();
    });
  });
}
