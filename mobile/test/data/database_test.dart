// mobile/test/data/database_test.dart
import 'package:flutter_test/flutter_test.dart';
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
  });
}
