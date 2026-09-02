import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models/last_import_summary.dart';
import 'models/sentence.dart';
import 'models/word.dart';
import 'review_schedule.dart';
import 'timestamps.dart';

class MergeResult {
  final int newWords;
  final int newSentences;
  final int skippedWords;
  final int skippedSentences;
  const MergeResult({
    required this.newWords,
    required this.newSentences,
    required this.skippedWords,
    required this.skippedSentences,
  });
}

class InvalidBackupFileException implements Exception {
  final String message;
  const InvalidBackupFileException(this.message);
  @override
  String toString() => 'InvalidBackupFileException: $message';
}

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
  Future<MergeResult> mergeFromFile(String filePath);
  Future<String> getDatabasePath();
  Future<LastImportSummary?> getLastImportSummary();
  Future<List<SyncQueueEntry>> getSyncQueue();
  Future<void> queueDelete(String entity, String docId);
  Future<void> clearSyncQueueEntry(String entity, String docId);
  Future<void> clearAllLocalData();
  Future<void> close();
}

class LocalSQLiteRepository extends ChangeNotifier implements LearningRepository {
  static const _lastImportKey = 'last_import_summary';

  final Future<Database> Function() _openDb;
  final Future<SharedPreferences> Function() _getPrefs;
  Database? _db;

  LocalSQLiteRepository({
    Future<Database> Function()? openDb,
    Future<SharedPreferences> Function()? getPrefs,
  })  : _openDb = openDb ?? _defaultOpenDb,
        _getPrefs = getPrefs ?? SharedPreferences.getInstance;

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
  Future<MergeResult> mergeFromFile(String filePath) async {
    final importDb = await databaseFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(readOnly: true),
    );

    if (!await hasValidSchema(importDb)) {
      await importDb.close();
      throw const InvalidBackupFileException(
        '올바른 English Helper 백업 파일이 아닙니다',
      );
    }

    final db = await _database;
    var newWords = 0;
    var newSentences = 0;
    var skippedWords = 0;
    var skippedSentences = 0;

    try {
      final wordRows = await importDb.query('words');
      for (final row in wordRows) {
        final rowId = await db.insert('words', row,
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (rowId != 0) {
          newWords++;
        } else {
          skippedWords++;
        }
      }

      final sentenceRows = await importDb.query('sentences');
      for (final row in sentenceRows) {
        final rowId = await db.insert('sentences', row,
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (rowId != 0) {
          newSentences++;
        } else {
          skippedSentences++;
        }
      }
    } finally {
      await importDb.close();
    }

    final summary = LastImportSummary(
      importedAt: DateTime.now(),
      newWords: newWords,
      newSentences: newSentences,
      skippedWords: skippedWords,
      skippedSentences: skippedSentences,
    );
    final prefs = await _getPrefs();
    await prefs.setString(_lastImportKey, jsonEncode(summary.toJson()));

    notifyListeners();
    return MergeResult(
      newWords: newWords,
      newSentences: newSentences,
      skippedWords: skippedWords,
      skippedSentences: skippedSentences,
    );
  }

  @override
  Future<LastImportSummary?> getLastImportSummary() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_lastImportKey);
    if (raw == null) return null;
    return LastImportSummary.fromJson(jsonDecode(raw) as Map<String, Object?>);
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
    await db.delete('study_sessions');
    await db.delete('weekly_goals');
    await db.delete('sync_queue');
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
