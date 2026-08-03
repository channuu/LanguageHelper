import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models/sentence.dart';
import 'models/word.dart';

class MergeResult {
  final int newWords;
  final int newSentences;
  const MergeResult({required this.newWords, required this.newSentences});
}

class InvalidBackupFileException implements Exception {
  final String message;
  const InvalidBackupFileException(this.message);
  @override
  String toString() => 'InvalidBackupFileException: $message';
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
  Future<MergeResult> mergeFromFile(String filePath);
  Future<String> getDatabasePath();
}

class LocalSQLiteRepository extends ChangeNotifier implements LearningRepository {
  final Future<Database> Function() _openDb;
  Database? _db;

  LocalSQLiteRepository({Future<Database> Function()? openDb})
      : _openDb = openDb ?? _defaultOpenDb;

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
    notifyListeners();
  }

  @override
  Future<void> deleteSentence(String id) async {
    final db = await _database;
    await db.delete('sentences', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  @override
  Future<void> markWordReviewed(String id) async {
    final db = await _database;
    final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final word = Word.fromMap(rows.single);
    final updated = word.copyWith(
      reviewCount: word.reviewCount + 1,
      nextReviewAt: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
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
    final updated = sentence.copyWith(
      reviewCount: sentence.reviewCount + 1,
      nextReviewAt: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
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

    final wordRows = await importDb.query('words');
    for (final row in wordRows) {
      final rowId = await db.insert('words', row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (rowId != 0) newWords++;
    }

    final sentenceRows = await importDb.query('sentences');
    for (final row in sentenceRows) {
      final rowId = await db.insert('sentences', row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (rowId != 0) newSentences++;
    }

    await importDb.close();
    notifyListeners();
    return MergeResult(newWords: newWords, newSentences: newSentences);
  }
}
