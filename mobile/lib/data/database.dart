import 'package:sqflite/sqflite.dart';

const List<String> kWordsColumns = [
  'id', 'word', 'definition', 'sentence', 'translation', 'platform',
  'content_title', 'content_id', 'timestamp', 'saved_at',
  'review_count', 'next_review_at',
];

const List<String> kSentencesColumns = [
  'id', 'original', 'translation', 'platform', 'content_title',
  'content_id', 'timestamp', 'saved_at', 'review_count', 'next_review_at',
];

Future<Database> openAppDatabase(String path) {
  return databaseFactory.openDatabase(
    path,
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
}

Future<bool> hasValidSchema(Database db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((r) => r['name'] as String).toSet();

  if (!tables.contains('words') || !tables.contains('sentences')) {
    return false;
  }

  final wordsCols = (await db.rawQuery('PRAGMA table_info(words)'))
      .map((r) => r['name'] as String)
      .toSet();
  if (!wordsCols.containsAll(kWordsColumns)) return false;

  final sentencesCols = (await db.rawQuery('PRAGMA table_info(sentences)'))
      .map((r) => r['name'] as String)
      .toSet();
  if (!sentencesCols.containsAll(kSentencesColumns)) return false;

  return true;
}
