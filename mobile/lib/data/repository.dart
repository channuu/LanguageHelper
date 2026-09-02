import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models/sentence.dart';
import 'models/word.dart';
import 'review_schedule.dart';
import 'timestamps.dart';

class SyncQueueEntry {
  final String entity;
  final String docId;
  const SyncQueueEntry({required this.entity, required this.docId});
}

abstract class LearningRepository extends ChangeNotifier {
  Future<List<Word>> getWords();
  Future<List<Sentence>> getSentences();
  Future<void> saveWord(Word word);
  Future<void> saveSentence(Sentence sentence);
  Future<void> deleteWord(String id);
  Future<void> deleteSentence(String id);
  Future<void> markWordReviewed(String id);
  Future<void> markSentenceReviewed(String id);
  Future<void> setWordReviewLevel(String id, int level);
  Future<void> setSentenceReviewLevel(String id, int level);
  Future<String> getDatabasePath();
  Future<List<SyncQueueEntry>> getSyncQueue();
  Future<void> queueDelete(String entity, String docId);
  Future<void> clearSyncQueueEntry(String entity, String docId);
  Future<void> clearAllLocalData();
  Future<void> close();
}

class LocalSQLiteRepository extends ChangeNotifier implements LearningRepository {

  final Future<Database> Function() _openDb;
  Database? _db;

  LocalSQLiteRepository({
    Future<Database> Function()? openDb,
  }) : _openDb = openDb ?? _defaultOpenDb;

  static Future<Database> _defaultOpenDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return openAppDatabase(p.join(dir.path, 'english_helper.sqlite'));
  }

  Future<Database> get _database async => _db ??= await _openDb();

  @override
  Future<List<Word>> getWords() async {
    final db = await _database;
    final rows = await db.query('words', orderBy: 'saved_at DESC');
    return rows.map(Word.fromMap).toList();
  }

  @override
  Future<List<Sentence>> getSentences() async {
    final db = await _database;
    final rows = await db.query('sentences', orderBy: 'saved_at DESC');
    return rows.map(Sentence.fromMap).toList();
  }

  @override
  Future<void> saveWord(Word word) async {
    final db = await _database;
    await db.insert('words', word.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> saveSentence(Sentence sentence) async {
    final db = await _database;
    await db.insert('sentences', sentence.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> deleteWord(String id) async {
    final db = await _database;
    await db.delete('words', where: 'id = ?', whereArgs: [id]);
    await queueDelete('words', id);
    notifyListeners();
  }

  @override
  Future<void> deleteSentence(String id) async {
    final db = await _database;
    await db.delete('sentences', where: 'id = ?', whereArgs: [id]);
    await queueDelete('sentences', id);
    notifyListeners();
  }

  @override
  Future<void> markWordReviewed(String id) async {
    final db = await _database;
    final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final word = Word.fromMap(rows.single);
    final newLevel = (word.reviewLevel + 1).clamp(0, kMaxReviewLevel);
    final now = DateTime.now();
    final updated = word.copyWith(
      reviewCount: word.reviewCount + 1,
      reviewLevel: newLevel,
      lastReviewedAt: now.toIso8601String(),
      nextReviewAt: nextReviewAtForLevel(newLevel, now),
      updatedAt: utcNowIso(),
      syncedAt: null,
    );
    await db.insert('words', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> markSentenceReviewed(String id) async {
    final db = await _database;
    final rows = await db.query('sentences', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final sentence = Sentence.fromMap(rows.single);
    final newLevel = (sentence.reviewLevel + 1).clamp(0, kMaxReviewLevel);
    final now = DateTime.now();
    final updated = sentence.copyWith(
      reviewCount: sentence.reviewCount + 1,
      reviewLevel: newLevel,
      lastReviewedAt: now.toIso8601String(),
      nextReviewAt: nextReviewAtForLevel(newLevel, now),
      updatedAt: utcNowIso(),
      syncedAt: null,
    );
    await db.insert('sentences', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> setWordReviewLevel(String id, int level) async {
    final db = await _database;
    final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final word = Word.fromMap(rows.single);
    final now = DateTime.now();
    final updated = word.copyWith(
      reviewLevel: level,
      lastReviewedAt: now.toIso8601String(),
      nextReviewAt: nextReviewAtForLevel(level, now),
      updatedAt: utcNowIso(),
      syncedAt: null,
    );
    await db.insert('words', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> setSentenceReviewLevel(String id, int level) async {
    final db = await _database;
    final rows = await db.query('sentences', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final sentence = Sentence.fromMap(rows.single);
    final now = DateTime.now();
    final updated = sentence.copyWith(
      reviewLevel: level,
      lastReviewedAt: now.toIso8601String(),
      nextReviewAt: nextReviewAtForLevel(level, now),
      updatedAt: utcNowIso(),
      syncedAt: null,
    );
    await db.insert('sentences', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<String> getDatabasePath() async {
    final db = await _database;
    return db.path;
  }

  @override
  Future<List<SyncQueueEntry>> getSyncQueue() async {
    final db = await _database;
    final rows = await db.query('sync_queue');
    return rows
        .map((r) => SyncQueueEntry(
              entity: r['entity'] as String,
              docId: r['doc_id'] as String,
            ))
        .toList();
  }

  @override
  Future<void> queueDelete(String entity, String docId) async {
    final db = await _database;
    await db.insert(
      'sync_queue',
      {'entity': entity, 'doc_id': docId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearSyncQueueEntry(String entity, String docId) async {
    final db = await _database;
    await db.delete('sync_queue',
        where: 'entity = ? AND doc_id = ?', whereArgs: [entity, docId]);
  }

  @override
  Future<void> clearAllLocalData() async {
    final db = await _database;
    await db.delete('words');
    await db.delete('sentences');
    await db.delete('sync_queue');
    // study_sessions·weekly_goals는 StudyTimerRepository의 것이다. 계정
    // 전환과 로그아웃은 두 저장소의 clearAllLocalData를 나란히 부른다.
    notifyListeners();
  }

  @override
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      _db = null;
      await db.close();
    }
  }
}
