import 'package:flutter/foundation.dart' show setEquals;
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

Future<void> _createTimerTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS study_sessions (
      id TEXT PRIMARY KEY,
      started_at TEXT NOT NULL,
      ended_at TEXT NOT NULL,
      duration_seconds INTEGER NOT NULL,
      saved_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_goals (
      id TEXT PRIMARY KEY,
      target_minutes INTEGER NOT NULL,
      effective_from TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}

Future<Database> openAppDatabase(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
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
        await _createTimerTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTimerTables(db);
        }
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
  if (!setEquals(wordsCols, kWordsColumns.toSet())) return false;

  final sentencesCols = (await db.rawQuery('PRAGMA table_info(sentences)'))
      .map((r) => r['name'] as String)
      .toSet();
  if (!setEquals(sentencesCols, kSentencesColumns.toSet())) return false;

  return true;
}
