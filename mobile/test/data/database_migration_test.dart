import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v4 이전 스키마의 DB를 만든다 — 마이그레이션 경로를 실제로 태우기 위해서다.
Future<Database> openV3(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE words (
            id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT,
            sentence TEXT, translation TEXT, platform TEXT,
            content_title TEXT, content_id TEXT, timestamp REAL,
            saved_at TEXT, review_count INTEGER DEFAULT 0,
            next_review_at TEXT, review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sentences (
            id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT,
            platform TEXT, content_title TEXT, content_id TEXT,
            timestamp REAL, saved_at TEXT, review_count INTEGER DEFAULT 0,
            next_review_at TEXT, review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE study_sessions (
            id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL, saved_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE weekly_goals (
            id TEXT PRIMARY KEY, target_minutes INTEGER NOT NULL,
            effective_from TEXT NOT NULL, created_at TEXT NOT NULL
          )
        ''');
      },
    ),
  );
}

Future<Set<String>> columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v3 데이터가 있는 DB를 v4로 올리면 sync 컬럼이 채워진다', () async {
    // in-memory DB는 매번 새로 열리므로 마이그레이션 경로를 태울 수 없다 —
    // 실제 파일에 v3 스키마를 만들고 닫은 뒤 같은 경로를 다시 열어야 한다.
    final dir = await Directory.systemTemp.createTemp('eh_migration');
    final path = p.join(dir.path, 'test.sqlite');
    try {
      final v3db = await openV3(path);
      await v3db.insert('words', {
        'id': 'w1', 'word': 'ephemeral', 'platform': 'youtube',
        'content_title': 'T', 'content_id': 'v1', 'timestamp': 12.0,
        'saved_at': '2026-08-01T00:00:00.000Z', 'review_count': 0,
        'review_level': 0,
      });
      await v3db.insert('study_sessions', {
        'id': 's1', 'started_at': '2026-08-01T00:00:00.000Z',
        'ended_at': '2026-08-01T00:30:00.000Z', 'duration_seconds': 1800,
        'saved_at': '2026-08-01T00:30:00.000Z',
      });
      await v3db.close();

      final db = await openAppDatabase(path);

      expect(await columnsOf(db, 'words'), contains('updated_at'));
      expect(await columnsOf(db, 'words'), contains('synced_at'));
      expect(await columnsOf(db, 'sentences'), contains('updated_at'));
      expect(await columnsOf(db, 'study_sessions'), contains('updated_at'));
      expect(await columnsOf(db, 'weekly_goals'), contains('synced_at'));

      final word =
          (await db.query('words', where: 'id = ?', whereArgs: ['w1'])).single;
      expect(word['updated_at'], '2026-08-01T00:00:00.000Z');
      expect(word['synced_at'], isNull);

      final session = (await db.query(
        'study_sessions',
        where: 'id = ?',
        whereArgs: ['s1'],
      )).single;
      expect(session['updated_at'], '2026-08-01T00:30:00.000Z');
      expect(session['synced_at'], isNull);

      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('sync_queue 테이블이 생긴다', () async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    await db.insert('sync_queue', {'entity': 'words', 'doc_id': 'w1'});
    expect((await db.query('sync_queue')).length, 1);
    await db.close();
  });

  test('새 DB도 같은 컬럼을 갖는다', () async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    expect(await columnsOf(db, 'words'), contains('updated_at'));
    expect(await columnsOf(db, 'weekly_goals'), contains('updated_at'));
    await db.close();
  });
}
