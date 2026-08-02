# Phase B Flutter App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase B Flutter mobile app that imports the Chrome extension's SQLite export and drives flashcard review, per `docs/superpowers/specs/2026-08-02-phase-b-flutter-app-design.md`.

**Architecture:** A single Flutter app under `mobile/` with a `data/` layer (models, sqflite database, `LearningRepository`) shared via `provider`, and a `features/` layer with one file per screen (Home, Flashcard, Import, Settings) wired together by a bottom-navigation shell in `main.dart`.

**Tech Stack:** Flutter 3.44.8 (already verified via `flutter doctor`), `sqflite` (local DB), `path_provider` (app documents dir), `file_picker` (SQLite import), `provider` (state), `shared_preferences` (settings persistence), `sqflite_common_ffi` (dev-only, unit-tests the DB/repository without a device).

## Global Constraints

- Flutter project lives at `mobile/` (new subdirectory at repo root) — do not scaffold at the repo root, it already holds the Chrome extension's `manifest.json` etc.
- DB schema must exactly match the Chrome extension's export schema (`docs/superpowers/specs/2026-07-17-english-helper-design.md` §3.6) — column names, types, and both tables (`words`, `sentences`). No new columns.
- Import merge must ignore rows whose `id` already exists locally (design §5, "중복 id 무시") — never overwrite local `review_count`/`next_review_at` progress on import.
- No SM-2 or spaced-repetition scheduling logic in Phase B (design §2/§6) — `next_review_at` is written but nothing reads it yet.
- No Share Extension / Intent Filter import path (design §9) — `file_picker` only.
- Widget test coverage stays minimal per design §7: one empty-state test (Home), one flip-interaction test (Flashcard), one smoke test (main.dart nav). Do not add a full widget-test suite per screen.

---

### Task 1: Flutter project scaffold + dependencies

**Files:**
- Create: `mobile/` (via `flutter create`)
- Modify: `mobile/pubspec.yaml`
- Delete: `mobile/test/widget_test.dart` (default counter-app test, replaced in Task 10)

**Interfaces:**
- Produces: a `mobile/` Flutter project with `sqflite`, `path_provider`, `file_picker`, `provider`, `shared_preferences` as runtime deps and `sqflite_common_ffi` as a dev dep, ready for `flutter test` / `flutter analyze` to run cleanly.

- [ ] **Step 1: Scaffold the project**

Run from the repo root (`/Users/park/Project2/english-helper-extension`):
```bash
flutter create --platforms=android,ios --org com.englishhelper --project-name english_helper_app mobile
```
Expected: `mobile/` created with `pubspec.yaml`, `lib/main.dart`, `android/`, `ios/`, `test/widget_test.dart`.

- [ ] **Step 2: Add runtime dependencies**

```bash
cd mobile
flutter pub add sqflite path_provider file_picker provider shared_preferences
```
Expected: `pubspec.yaml` gains 5 entries under `dependencies:`, `pubspec.lock` updated.

- [ ] **Step 3: Add dev dependency for DB unit testing**

```bash
flutter pub add --dev sqflite_common_ffi
```
Expected: `sqflite_common_ffi` added under `dev_dependencies:`.

- [ ] **Step 4: Remove the default counter-app test (will be replaced in Task 10)**

```bash
rm mobile/test/widget_test.dart
```

- [ ] **Step 5: Verify the scaffold builds and analyzes cleanly**

```bash
cd mobile && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock
git add mobile --all
git commit -m "chore: scaffold Phase B Flutter app with core dependencies"
```

---

### Task 2: Data models — Word and Sentence

**Files:**
- Create: `mobile/lib/data/models/word.dart`
- Create: `mobile/lib/data/models/sentence.dart`
- Test: `mobile/test/data/models/word_test.dart`
- Test: `mobile/test/data/models/sentence_test.dart`

**Interfaces:**
- Produces: `Word` and `Sentence` classes with `toMap() -> Map<String, Object?>` and `fromMap(Map<String, Object?>) -> Word/Sentence` factory constructors, and a `copyWith({int? reviewCount, String? nextReviewAt})` method on each. Column keys in `toMap()`/`fromMap()` match the SQL schema built in Task 3 exactly (`content_title`, `content_id`, `saved_at`, `review_count`, `next_review_at`).

- [ ] **Step 1: Write the failing test for Word**

```dart
// mobile/test/data/models/word_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/word.dart';

void main() {
  group('Word', () {
    test('toMap/fromMap round-trips all fields', () {
      final word = Word(
        id: 'w1',
        word: 'ephemeral',
        definition: 'lasting for a very short time',
        sentence: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'netflix',
        contentTitle: 'Stranger Things S1E1',
        contentId: '70301898',
        timestamp: 142.5,
        savedAt: '2026-08-02T00:00:00.000Z',
        reviewCount: 2,
        nextReviewAt: '2026-08-03T00:00:00.000Z',
      );

      final restored = Word.fromMap(word.toMap());

      expect(restored.id, 'w1');
      expect(restored.word, 'ephemeral');
      expect(restored.definition, 'lasting for a very short time');
      expect(restored.sentence, 'Nothing in life is ephemeral.');
      expect(restored.translation, '인생에서 덧없지 않은 것은 없다.');
      expect(restored.platform, 'netflix');
      expect(restored.contentTitle, 'Stranger Things S1E1');
      expect(restored.contentId, '70301898');
      expect(restored.timestamp, 142.5);
      expect(restored.savedAt, '2026-08-02T00:00:00.000Z');
      expect(restored.reviewCount, 2);
      expect(restored.nextReviewAt, '2026-08-03T00:00:00.000Z');
    });

    test('fromMap defaults missing optional fields', () {
      final restored = Word.fromMap({
        'id': 'w2',
        'word': 'brief',
        'platform': 'youtube',
        'timestamp': 10,
        'saved_at': '2026-08-02T00:00:00.000Z',
      });

      expect(restored.definition, '');
      expect(restored.sentence, '');
      expect(restored.translation, '');
      expect(restored.contentTitle, '');
      expect(restored.contentId, '');
      expect(restored.reviewCount, 0);
      expect(restored.nextReviewAt, isNull);
    });

    test('copyWith updates only reviewCount and nextReviewAt', () {
      final word = Word(
        id: 'w1', word: 'ephemeral', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = word.copyWith(reviewCount: 1, nextReviewAt: '2026-08-03T00:00:00.000Z');

      expect(updated.reviewCount, 1);
      expect(updated.nextReviewAt, '2026-08-03T00:00:00.000Z');
      expect(updated.word, 'ephemeral');
      expect(updated.id, 'w1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/models/word_test.dart
```
Expected: FAIL — `Error: Couldn't resolve the package 'english_helper_app'` or `Target of URI doesn't exist` (file doesn't exist yet).

- [ ] **Step 3: Implement Word**

```dart
// mobile/lib/data/models/word.dart
class Word {
  final String id;
  final String word;
  final String definition;
  final String sentence;
  final String translation;
  final String platform;
  final String contentTitle;
  final String contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;

  const Word({
    required this.id,
    required this.word,
    this.definition = '',
    this.sentence = '',
    this.translation = '',
    required this.platform,
    required this.contentTitle,
    required this.contentId,
    required this.timestamp,
    required this.savedAt,
    this.reviewCount = 0,
    this.nextReviewAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'word': word,
        'definition': definition,
        'sentence': sentence,
        'translation': translation,
        'platform': platform,
        'content_title': contentTitle,
        'content_id': contentId,
        'timestamp': timestamp,
        'saved_at': savedAt,
        'review_count': reviewCount,
        'next_review_at': nextReviewAt,
      };

  factory Word.fromMap(Map<String, Object?> map) => Word(
        id: map['id'] as String,
        word: map['word'] as String,
        definition: (map['definition'] as String?) ?? '',
        sentence: (map['sentence'] as String?) ?? '',
        translation: (map['translation'] as String?) ?? '',
        platform: (map['platform'] as String?) ?? '',
        contentTitle: (map['content_title'] as String?) ?? '',
        contentId: (map['content_id'] as String?) ?? '',
        timestamp: (map['timestamp'] as num?)?.toDouble() ?? 0,
        savedAt: (map['saved_at'] as String?) ?? '',
        reviewCount: (map['review_count'] as int?) ?? 0,
        nextReviewAt: map['next_review_at'] as String?,
      );

  Word copyWith({int? reviewCount, String? nextReviewAt}) => Word(
        id: id,
        word: word,
        definition: definition,
        sentence: sentence,
        translation: translation,
        platform: platform,
        contentTitle: contentTitle,
        contentId: contentId,
        timestamp: timestamp,
        savedAt: savedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/models/word_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 5: Write the failing test for Sentence**

```dart
// mobile/test/data/models/sentence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';

void main() {
  group('Sentence', () {
    test('toMap/fromMap round-trips all fields', () {
      final sentence = Sentence(
        id: 's1',
        original: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'netflix',
        contentTitle: 'Stranger Things S1E1',
        contentId: '70301898',
        timestamp: 142.5,
        savedAt: '2026-08-02T00:00:00.000Z',
        reviewCount: 1,
        nextReviewAt: '2026-08-03T00:00:00.000Z',
      );

      final restored = Sentence.fromMap(sentence.toMap());

      expect(restored.id, 's1');
      expect(restored.original, 'Nothing in life is ephemeral.');
      expect(restored.translation, '인생에서 덧없지 않은 것은 없다.');
      expect(restored.platform, 'netflix');
      expect(restored.contentTitle, 'Stranger Things S1E1');
      expect(restored.contentId, '70301898');
      expect(restored.timestamp, 142.5);
      expect(restored.savedAt, '2026-08-02T00:00:00.000Z');
      expect(restored.reviewCount, 1);
      expect(restored.nextReviewAt, '2026-08-03T00:00:00.000Z');
    });

    test('fromMap defaults missing optional fields', () {
      final restored = Sentence.fromMap({
        'id': 's2',
        'original': 'Brief line.',
        'platform': 'youtube',
        'timestamp': 5,
        'saved_at': '2026-08-02T00:00:00.000Z',
      });

      expect(restored.translation, '');
      expect(restored.contentTitle, '');
      expect(restored.contentId, '');
      expect(restored.reviewCount, 0);
      expect(restored.nextReviewAt, isNull);
    });

    test('copyWith updates only reviewCount and nextReviewAt', () {
      final sentence = Sentence(
        id: 's1', original: 'x', platform: 'netflix',
        contentTitle: 'y', contentId: 'z', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = sentence.copyWith(reviewCount: 1, nextReviewAt: '2026-08-03T00:00:00.000Z');

      expect(updated.reviewCount, 1);
      expect(updated.nextReviewAt, '2026-08-03T00:00:00.000Z');
      expect(updated.original, 'x');
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/models/sentence_test.dart
```
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 7: Implement Sentence**

```dart
// mobile/lib/data/models/sentence.dart
class Sentence {
  final String id;
  final String original;
  final String translation;
  final String platform;
  final String contentTitle;
  final String contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;

  const Sentence({
    required this.id,
    required this.original,
    this.translation = '',
    required this.platform,
    required this.contentTitle,
    required this.contentId,
    required this.timestamp,
    required this.savedAt,
    this.reviewCount = 0,
    this.nextReviewAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'original': original,
        'translation': translation,
        'platform': platform,
        'content_title': contentTitle,
        'content_id': contentId,
        'timestamp': timestamp,
        'saved_at': savedAt,
        'review_count': reviewCount,
        'next_review_at': nextReviewAt,
      };

  factory Sentence.fromMap(Map<String, Object?> map) => Sentence(
        id: map['id'] as String,
        original: map['original'] as String,
        translation: (map['translation'] as String?) ?? '',
        platform: (map['platform'] as String?) ?? '',
        contentTitle: (map['content_title'] as String?) ?? '',
        contentId: (map['content_id'] as String?) ?? '',
        timestamp: (map['timestamp'] as num?)?.toDouble() ?? 0,
        savedAt: (map['saved_at'] as String?) ?? '',
        reviewCount: (map['review_count'] as int?) ?? 0,
        nextReviewAt: map['next_review_at'] as String?,
      );

  Sentence copyWith({int? reviewCount, String? nextReviewAt}) => Sentence(
        id: id,
        original: original,
        translation: translation,
        platform: platform,
        contentTitle: contentTitle,
        contentId: contentId,
        timestamp: timestamp,
        savedAt: savedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      );
}
```

- [ ] **Step 8: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/models/sentence_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 9: Commit**

```bash
git add mobile/lib/data/models mobile/test/data/models
git commit -m "feat: add Word and Sentence data models"
```

---

### Task 3: database.dart — schema creation + open + validation

**Files:**
- Create: `mobile/lib/data/database.dart`
- Test: `mobile/test/data/database_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (models are used by callers of this file, not by this file itself).
- Produces: `Future<Database> openAppDatabase(String path)` (creates `words`/`sentences` tables if missing, matching `docs/superpowers/specs/2026-07-17-english-helper-design.md` §3.6 exactly) and `Future<bool> hasValidSchema(Database db)` (returns true iff both tables exist with all expected columns). Both are used by `repository.dart` in Task 4.

- [ ] **Step 1: Write the failing test**

```dart
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/database_test.dart
```
Expected: FAIL — `mobile/lib/data/database.dart` doesn't exist yet.

- [ ] **Step 3: Implement database.dart**

```dart
// mobile/lib/data/database.dart
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/database_test.dart
```
Expected: `00:0X +5: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/database.dart mobile/test/data/database_test.dart
git commit -m "feat: add sqflite schema creation and validation"
```

---

### Task 4: repository.dart — LearningRepository + LocalSQLiteRepository

**Files:**
- Create: `mobile/lib/data/repository.dart`
- Test: `mobile/test/data/repository_test.dart`

**Interfaces:**
- Consumes: `Word`, `Sentence` (Task 2); `openAppDatabase`, `hasValidSchema` (Task 3).
- Produces: `LearningRepository` (abstract, extends `ChangeNotifier`), `LocalSQLiteRepository` (implementation), `MergeResult` (`{int newWords, int newSentences}`), `InvalidBackupFileException`. `LocalSQLiteRepository({Future<Database> Function()? openDb})` — production code omits `openDb` (resolves the app documents path itself); tests pass an in-memory FFI database opener. `LearningRepository.getDatabasePath()` exposes the open database's file path so `SettingsScreen` (Task 9) can display it without touching `path_provider` directly — keeps that screen mockable in widget tests via the same `openDb` injection point every other screen test already uses. Used by all 4 screens in Tasks 6–9 and wired into `main.dart` in Task 10.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/data/repository_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/repository.dart';

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

  late LocalSQLiteRepository repo;

  setUp(() {
    repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
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

  test('markWordReviewed increments reviewCount and sets nextReviewAt', () async {
    await repo.saveWord(_word('w1', reviewCount: 2));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewCount, 3);
    expect(word.nextReviewAt, isNotNull);
  });

  test('markSentenceReviewed increments reviewCount and sets nextReviewAt', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.markSentenceReviewed('s1');
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewCount, 1);
    expect(sentence.nextReviewAt, isNotNull);
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
      // plus one new sentence.
      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await openAppDatabase(importPath);
      await importDb.insert('words', _word('w1', reviewCount: 0).toMap());
      await importDb.insert('words', _word('w2').toMap());
      await importDb.insert('sentences', _sentence('s1').toMap());
      await importDb.close();

      final result = await repo.mergeFromFile(importPath);

      expect(result.newWords, 1);
      expect(result.newSentences, 1);

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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/repository_test.dart
```
Expected: FAIL — `mobile/lib/data/repository.dart` doesn't exist yet.

- [ ] **Step 3: Implement repository.dart**

```dart
// mobile/lib/data/repository.dart
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
```

- [ ] **Step 4: Add the `path` package used by repository.dart**

```bash
cd mobile && flutter pub add path
```
Expected: `path` added under `dependencies:` in `pubspec.yaml`.

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/repository_test.dart
```
Expected: `00:0X +10: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/data/repository.dart mobile/test/data/repository_test.dart mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "feat: add LearningRepository with merge-import support"
```

---

### Task 5: Shared empty-state widget

**Files:**
- Create: `mobile/lib/shared/widgets/empty_state.dart`
- Test: `mobile/test/shared/widgets/empty_state_test.dart`

**Interfaces:**
- Produces: `EmptyState` widget — `EmptyState({required String message})`. Used by Home (Task 6) and Flashcard (Task 8).

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/shared/widgets/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/widgets/empty_state.dart';

void main() {
  testWidgets('renders the given message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmptyState(message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요'),
      ),
    );

    expect(find.text('아직 저장된 항목이 없어요. Import 탭에서 불러오세요'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/shared/widgets/empty_state_test.dart
```
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 3: Implement EmptyState**

```dart
// mobile/lib/shared/widgets/empty_state.dart
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final String message;

  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/shared/widgets/empty_state_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/shared mobile/test/shared
git commit -m "feat: add shared EmptyState widget"
```

---

### Task 6: Home screen

**Files:**
- Create: `mobile/lib/features/home/home_screen.dart`
- Test: `mobile/test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `LearningRepository` (Task 4, via `provider`), `EmptyState` (Task 5).
- Produces: `HomeScreen` widget (`StatelessWidget`, no constructor params) — mounted by `main.dart` in Task 10.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/features/home/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/home/home_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('shows empty state when there are no saved items', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/home/home_screen_test.dart
```
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 3: Implement HomeScreen**

```dart
// mobile/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sentence.dart';
import '../../data/models/word.dart';
import '../../data/repository.dart';
import '../../shared/widgets/empty_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('저장한 단어/문장'),
          bottom: const TabBar(
            tabs: [Tab(text: '단어'), Tab(text: '문장')],
          ),
        ),
        body: const TabBarView(
          children: [_WordList(), _SentenceList()],
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  const _WordList();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LearningRepository>();
    return FutureBuilder<List<Word>>(
      future: repo.getWords(),
      builder: (context, snapshot) {
        final words = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && words.isEmpty) {
          return const EmptyState(
            message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요',
          );
        }
        return ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return Dismissible(
              key: ValueKey(word.id),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red),
              onDismissed: (_) => repo.deleteWord(word.id),
              child: ListTile(
                title: Text(word.word),
                subtitle: Text(
                  '${word.translation}\n${word.platform} · ${word.contentTitle}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _SentenceList extends StatelessWidget {
  const _SentenceList();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LearningRepository>();
    return FutureBuilder<List<Sentence>>(
      future: repo.getSentences(),
      builder: (context, snapshot) {
        final sentences = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && sentences.isEmpty) {
          return const EmptyState(
            message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요',
          );
        }
        return ListView.builder(
          itemCount: sentences.length,
          itemBuilder: (context, index) {
            final sentence = sentences[index];
            return Dismissible(
              key: ValueKey(sentence.id),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red),
              onDismissed: (_) => repo.deleteSentence(sentence.id),
              child: ListTile(
                title: Text(sentence.original),
                subtitle: Text(
                  '${sentence.translation}\n${sentence.platform} · ${sentence.contentTitle}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/home/home_screen_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home mobile/test/features/home
git commit -m "feat: add Home screen with word/sentence tabs and swipe-to-delete"
```

---

### Task 7: Import screen

**Files:**
- Create: `mobile/lib/features/import/import_screen.dart`

**Interfaces:**
- Consumes: `LearningRepository.mergeFromFile` (Task 4, via `provider`), `InvalidBackupFileException` (Task 4), `file_picker`'s `FilePicker.platform.pickFiles`.
- Produces: `ImportScreen` widget (`StatelessWidget`, no constructor params) — mounted by `main.dart` in Task 10.

No automated test for this screen — its only logic is delegating to `file_picker` (a plugin with platform channels that unit/widget tests can't exercise meaningfully) and `repository.mergeFromFile`, which already has full coverage in Task 4. This matches design §7's "위젯 테스트는 Provider 목업 정도만" scope — a screen that is pure plumbing over already-tested and already-plugin-owned behavior gets no additional test.

- [ ] **Step 1: Implement ImportScreen**

```dart
// mobile/lib/features/import/import_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  Future<void> _pickAndImport(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    if (result == null || result.files.single.path == null) return;

    final repo = context.read<LearningRepository>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final merged = await repo.mergeFromFile(result.files.single.path!);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '단어 ${merged.newWords}개, 문장 ${merged.newSentences}개를 가져왔습니다',
          ),
        ),
      );
    } on InvalidBackupFileException catch (e) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('가져오기 실패'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가져오기')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.file_open),
          label: const Text('SQLite 파일 선택'),
          onPressed: () => _pickAndImport(context),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it analyzes cleanly**

```bash
cd mobile && flutter analyze lib/features/import/import_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/import
git commit -m "feat: add Import screen with file_picker and merge feedback"
```

---

### Task 8: Flashcard screen

**Files:**
- Create: `mobile/lib/features/flashcard/flashcard_item.dart`
- Create: `mobile/lib/features/flashcard/flashcard_screen.dart`
- Test: `mobile/test/features/flashcard/flashcard_screen_test.dart`

**Interfaces:**
- Consumes: `Word`, `Sentence` (Task 2), `LearningRepository` (Task 4, via `provider`), `EmptyState` (Task 5).
- Produces: `FlashcardItem` (`{id, front, back, contentTitle, isWord}` with `.fromWord`/`.fromSentence` factories) and `FlashcardScreen` widget (`StatelessWidget`, no constructor params) — mounted by `main.dart` in Task 10.

- [ ] **Step 1: Implement FlashcardItem (no test — a plain data-holding value type with two trivial factories, exercised indirectly by the screen test below)**

```dart
// mobile/lib/features/flashcard/flashcard_item.dart
import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

class FlashcardItem {
  final String id;
  final String front;
  final String back;
  final String contentTitle;
  final bool isWord;

  const FlashcardItem({
    required this.id,
    required this.front,
    required this.back,
    required this.contentTitle,
    required this.isWord,
  });

  factory FlashcardItem.fromWord(Word w) => FlashcardItem(
        id: w.id,
        front: w.word,
        back: [w.definition, w.sentence].where((s) => s.isNotEmpty).join('\n\n'),
        contentTitle: w.contentTitle,
        isWord: true,
      );

  factory FlashcardItem.fromSentence(Sentence s) => FlashcardItem(
        id: s.id,
        front: s.original,
        back: s.translation,
        contentTitle: s.contentTitle,
        isWord: false,
      );
}
```

- [ ] **Step 2: Write the failing test for FlashcardScreen**

```dart
// mobile/test/features/flashcard/flashcard_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/flashcard/flashcard_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('shows empty state when there is nothing to review', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('tapping the card flips it to show the back', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('lasting for a very short time'), findsNothing);

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('lasting for a very short time'), findsOneWidget);
  });

  testWidgets('알아요 removes the card and marks it reviewed', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'netflix',
      contentTitle: 'Title',
      contentId: 'c1',
      timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: FlashcardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral')); // flip
    await tester.pumpAndSettle();
    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
    final words = await repo.getWords();
    expect(words.single.reviewCount, 1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart
```
Expected: FAIL — `flashcard_screen.dart` doesn't exist yet.

- [ ] **Step 4: Implement FlashcardScreen**

```dart
// mobile/lib/features/flashcard/flashcard_screen.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../shared/widgets/empty_state.dart';
import 'flashcard_item.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<FlashcardItem>? _queue;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    final items = [
      ...words.map(FlashcardItem.fromWord),
      ...sentences.map(FlashcardItem.fromSentence),
    ]..shuffle(Random());
    if (!mounted) return;
    setState(() => _queue = items);
  }

  void _dontKnow() {
    setState(() {
      final current = _queue!.removeAt(0);
      _queue!.add(current);
      _flipped = false;
    });
  }

  Future<void> _know() async {
    final repo = context.read<LearningRepository>();
    final current = _queue!.first;
    if (current.isWord) {
      await repo.markWordReviewed(current.id);
    } else {
      await repo.markSentenceReviewed(current.id);
    }
    setState(() {
      _queue!.removeAt(0);
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return Scaffold(
      appBar: AppBar(title: const Text('플래시카드')),
      body: Builder(builder: (context) {
        if (queue == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (queue.isEmpty) {
          return const EmptyState(message: '오늘 복습 완료! 🎉');
        }
        final current = queue.first;
        return Column(
          children: [
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _flipped ? current.back : current.front,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _dontKnow,
                    child: const Text('몰라요'),
                  ),
                  ElevatedButton(
                    onPressed: _know,
                    child: const Text('알아요'),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/flashcard mobile/test/features/flashcard
git commit -m "feat: add Flashcard screen with review queue"
```

---

### Task 9: Settings screen

**Files:**
- Create: `mobile/lib/features/settings/settings_screen.dart`
- Test: `mobile/test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`; `LearningRepository.getDatabasePath()` (Task 4, via `provider`) — used instead of calling `path_provider` directly so this screen stays mockable in widget tests through the same `openDb` injection point every other screen test uses.
- Produces: `SettingsScreen` widget (`StatelessWidget`, no constructor params) — mounted by `main.dart` in Task 10. Persists the selected native language under the `shared_preferences` key `'native_lang'` (default `'ko'`), matching the Chrome extension's option set exactly (`popup/popup.html` `#native-lang`: ko/ja/zh/es/fr/de). Not consumed by any other Phase B screen yet — this is forward-compatible plumbing for Phase C, the same way `Word.nextReviewAt` is written but unused today.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/features/settings/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/settings/settings_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets('defaults to Korean and persists a new selection', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('native_lang'), 'ja');
  });

  testWidgets('shows the DB path from the repository', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text(inMemoryDatabasePath), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/settings/settings_screen_test.dart
```
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 3: Implement SettingsScreen**

```dart
// mobile/lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';

const Map<String, String> kNativeLanguages = {
  'ko': '한국어',
  'ja': '日本語',
  'zh': '中文',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _nativeLang = 'ko';
  String? _dbPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dbPath = await context.read<LearningRepository>().getDatabasePath();
    if (!mounted) return;
    setState(() {
      _nativeLang = prefs.getString('native_lang') ?? 'ko';
      _dbPath = dbPath;
    });
  }

  Future<void> _setNativeLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('native_lang', lang);
    if (!mounted) return;
    setState(() => _nativeLang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('모국어 (Native Language)'),
            trailing: DropdownButton<String>(
              value: _nativeLang,
              items: kNativeLanguages.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _setNativeLang(value);
              },
            ),
          ),
          ListTile(
            title: const Text('DB 파일 경로'),
            subtitle: Text(_dbPath ?? '불러오는 중...'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add `shared_preferences` test mock support and run**

```bash
cd mobile && flutter test test/features/settings/settings_screen_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/settings mobile/test/features/settings
git commit -m "feat: add Settings screen with persisted native-language selection"
```

---

### Task 10: main.dart — app shell wiring

**Files:**
- Modify: `mobile/lib/main.dart`
- Create: `mobile/test/main_test.dart`

**Interfaces:**
- Consumes: `LocalSQLiteRepository`, `LearningRepository` (Task 4); `HomeScreen` (Task 6); `ImportScreen` (Task 7); `FlashcardScreen` (Task 8); `SettingsScreen` (Task 9).
- Produces: the app entry point — no further tasks depend on this one.

- [ ] **Step 1: Write the failing smoke test**

```dart
// mobile/test/main_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bottom navigation switches between all 4 screens', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const EnglishHelperApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 단어/문장'), findsOneWidget);

    await tester.tap(find.text('플래시카드'));
    await tester.pumpAndSettle();
    expect(find.text('플래시카드'), findsWidgets);

    await tester.tap(find.text('가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('SQLite 파일 선택'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('모국어 (Native Language)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/main_test.dart
```
Expected: FAIL — `lib/app.dart` doesn't exist yet.

- [ ] **Step 3: Implement app.dart (the widget tree, separated from main() so tests can inject a repository)**

```dart
// mobile/lib/app.dart
import 'package:flutter/material.dart';

import 'features/flashcard/flashcard_screen.dart';
import 'features/home/home_screen.dart';
import 'features/import/import_screen.dart';
import 'features/settings/settings_screen.dart';

class EnglishHelperApp extends StatelessWidget {
  const EnglishHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Helper',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _RootShell(),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    FlashcardScreen(),
    ImportScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.style), label: '플래시카드'),
          NavigationDestination(icon: Icon(Icons.file_download), label: '가져오기'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Implement main.dart (production entry point)**

```dart
// mobile/lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';

void main() {
  runApp(
    ChangeNotifierProvider<LearningRepository>(
      create: (_) => LocalSQLiteRepository(),
      child: const EnglishHelperApp(),
    ),
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/main_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 6: Run the full test suite**

```bash
cd mobile && flutter test
```
Expected: all tests across every file pass, `0` failures.

- [ ] **Step 7: Run analyzer over the whole project**

```bash
cd mobile && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/main.dart mobile/lib/app.dart mobile/test/main_test.dart
git commit -m "feat: wire app shell with bottom navigation across all 4 screens"
```

---

### Task 11: Run on a real simulator/emulator

**Files:** none (verification-only task).

**Interfaces:** none — this task drives the already-built app, it doesn't produce anything later tasks depend on.

- [ ] **Step 1: Launch the iOS simulator (already created: "iPhone 17")**

```bash
open -a Simulator
xcrun simctl boot "iPhone 17" 2>&1 || true
```

- [ ] **Step 2: Run the app on the simulator**

```bash
cd mobile && flutter run -d "iPhone 17"
```
Expected: app builds, installs, and launches showing the Home tab with the empty state ("아직 저장된 항목이 없어요. Import 탭에서 불러오세요").

- [ ] **Step 3: Manually verify the 4-tab flow**

In the running simulator:
1. Tap through all 4 bottom-nav tabs — confirm each renders without error.
2. On Import, tap "SQLite 파일 선택" and cancel — confirm no crash.
3. Stop the run (`q` in the terminal running `flutter run`).

- [ ] **Step 4: No commit** — this task only verifies Task 1–10's output runs; it makes no code changes.
