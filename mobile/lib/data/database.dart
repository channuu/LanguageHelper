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
      saved_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_goals (
      id TEXT PRIMARY KEY,
      target_minutes INTEGER NOT NULL,
      effective_from TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');
}

Future<void> _addReviewLevelColumns(Database db) async {
  await db.execute('ALTER TABLE words ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0');
  await db.execute('ALTER TABLE words ADD COLUMN last_reviewed_at TEXT');
  await db.execute('ALTER TABLE sentences ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0');
  await db.execute('ALTER TABLE sentences ADD COLUMN last_reviewed_at TEXT');
}

const List<String> _syncedTables = [
  'words', 'sentences', 'study_sessions', 'weekly_goals',
];

/// 각 테이블에서 "이 행이 생긴 시각"으로 볼 컬럼. 기존 행의 updated_at을
/// 여기서 채운다 — 그 결과 마이그레이션 자체가 전량 업로드 대상 표시가 된다.
const Map<String, String> _createdAtColumn = {
  'words': 'saved_at',
  'sentences': 'saved_at',
  'study_sessions': 'saved_at',
  'weekly_goals': 'created_at',
};

Future<void> _createSyncQueueTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_queue (
      entity TEXT NOT NULL,
      doc_id TEXT NOT NULL,
      PRIMARY KEY (entity, doc_id)
    )
  ''');
}

Future<Database> openAppDatabase(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
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
            next_review_at TEXT,
            review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT,
            updated_at TEXT,
            synced_at TEXT
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
            next_review_at TEXT,
            review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT,
            updated_at TEXT,
            synced_at TEXT
          )
        ''');
        await _createTimerTables(db);
        await _createSyncQueueTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTimerTables(db);
        }
        if (oldVersion < 3) {
          await _addReviewLevelColumns(db);
        }
        if (oldVersion < 4) {
          // v2 미만에서 올라온 경우 타이머 테이블은 방금 새 스키마로
          // 만들어졌으니 words/sentences에만 컬럼을 붙인다.
          final tables = oldVersion < 2
              ? ['words', 'sentences']
              : _syncedTables;
          for (final table in tables) {
            await db.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT');
            await db.execute('ALTER TABLE $table ADD COLUMN synced_at TEXT');
            await db.execute(
              'UPDATE $table SET updated_at = ${_createdAtColumn[table]}',
            );
          }
          await _createSyncQueueTable(db);
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
