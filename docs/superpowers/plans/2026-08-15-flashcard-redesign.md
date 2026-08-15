# 플래시카드 재설계(1d) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Flutter app's single flip-card flashcard screen with a spaced-repetition system: a real `review_level`/`last_reviewed_at`-driven due-date schedule, a typing-based recall card mode, a list mode, and an add/edit modal — matching Claude Design mockup §1d.

**Architecture:** A DB schema v2→v3 migration adds two columns to `words`/`sentences`. A new `review_schedule.dart` module is the single source of truth for level names, intervals, and due-date logic, consumed by both the repository (grading mutations) and the UI (queue filtering, badges, level picker). The screen itself stays one `StatefulWidget` (matching this codebase's existing per-screen-file convention) that grows across three tasks: card mode, list mode, add/edit modal.

**Tech Stack:** Flutter/Dart, `provider` for `LearningRepository`, `sqflite` migrations, `flutter_test` + `sqflite_common_ffi`/`sqflite_common_ffi_web` no-isolate factory for widget tests.

## Global Constraints

- `LearningRepository.getWords()`/`getSentences()` take no parameters and always return the full list — filtering (due-date, type, level) happens client-side in the widget, same pattern as the Home screen redesign.
- **`kWordsColumns`/`kSentencesColumns` in `mobile/lib/data/database.dart` must NOT be changed.** They validate Chrome-extension-exported backup files (`hasValidSchema`, called from `mergeFromFile`), not the app's own live schema. Adding the new columns there would reject every real backup file on import.
- Review levels are 0 (new) through 4 (완전히 외움), with fixed intervals 1/7/30/90 days (spec §3.2) — this is "Option B" from the §5.1 research note; FSRS (Option A) stays a future swap-in.
- "몰라요"/"다시" never mutates the repository — only "알아요" (또는 수정 모달의 레벨 선택) does.
- The card's back view never displays the user's typed answer — only the correct-answer detail (spec §5.2, explicit user request).
- Use `Color.withValues(alpha: ...)` (not deprecated `withOpacity`) for any color-with-opacity in new UI code — this Flutter version (3.44.8) flags `withOpacity` as deprecated.

---

### Task 1: Schema v3, model fields, and the review-schedule module

**Files:**
- Modify: `mobile/lib/data/database.dart`
- Modify: `mobile/lib/data/models/word.dart`
- Modify: `mobile/lib/data/models/sentence.dart`
- Create: `mobile/lib/data/review_schedule.dart`
- Test: `mobile/test/data/database_test.dart` (extend)
- Test: `mobile/test/data/review_schedule_test.dart` (new)
- Test: `mobile/test/data/models/word_test.dart` (extend)
- Test: `mobile/test/data/models/sentence_test.dart` (extend)

**Interfaces:**
- Produces: `Word.reviewLevel` (`int`, default 0), `Word.lastReviewedAt` (`String?`), same two fields on `Sentence`. `const kReviewLevelNames = ['새 항목', '학습 중', '복습 필요', '익숙해짐', '완전히 외움']`. `const kReviewIntervalDays = <int?>[null, 1, 7, 30, 90]`. `const kMaxReviewLevel = 4`. `String? nextReviewAtForLevel(int level, DateTime from)`. `bool isDueForReview(int reviewLevel, String? nextReviewAt)`. Task 2 (repository) and Tasks 3-5 (UI) all import from `review_schedule.dart`.

- [ ] **Step 1: Write the failing test for `review_schedule.dart`**

Create `mobile/test/data/review_schedule_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/review_schedule.dart';

void main() {
  group('nextReviewAtForLevel', () {
    test('level 0 has no schedule (returns null)', () {
      expect(nextReviewAtForLevel(0, DateTime(2026, 8, 15)), isNull);
    });

    test('level 1 is 1 day out', () {
      expect(
        nextReviewAtForLevel(1, DateTime(2026, 8, 15)),
        DateTime(2026, 8, 16).toIso8601String(),
      );
    });

    test('level 2 is 7 days out', () {
      expect(
        nextReviewAtForLevel(2, DateTime(2026, 8, 15)),
        DateTime(2026, 8, 22).toIso8601String(),
      );
    });

    test('level 3 is 30 days out', () {
      expect(
        nextReviewAtForLevel(3, DateTime(2026, 8, 15)),
        DateTime(2026, 9, 14).toIso8601String(),
      );
    });

    test('level 4 is 90 days out', () {
      expect(
        nextReviewAtForLevel(4, DateTime(2026, 8, 15)),
        DateTime(2026, 11, 13).toIso8601String(),
      );
    });
  });

  group('isDueForReview', () {
    test('level 0 is always due, regardless of nextReviewAt', () {
      expect(isDueForReview(0, null), isTrue);
      expect(isDueForReview(0, DateTime(2099, 1, 1).toIso8601String()), isTrue);
    });

    test('a level with no nextReviewAt is due (safety net)', () {
      expect(isDueForReview(2, null), isTrue);
    });

    test('a future nextReviewAt is not due', () {
      final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
      expect(isDueForReview(2, future), isFalse);
    });

    test('a past nextReviewAt is due', () {
      final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      expect(isDueForReview(2, past), isTrue);
    });
  });

  test('kReviewLevelNames has one name per level 0-4', () {
    expect(kReviewLevelNames, hasLength(5));
  });

  test('kReviewIntervalDays has one entry per level 0-4', () {
    expect(kReviewIntervalDays, hasLength(5));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/data/review_schedule_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/data/review_schedule.dart'`

- [ ] **Step 3: Write `review_schedule.dart`**

Create `mobile/lib/data/review_schedule.dart`:

```dart
/// Fixed-schedule spaced repetition (design.md §5.1 "Option B", compressed
/// to 5 levels). Index = review level (0-4). `review_level` is a plain int
/// column so a future FSRS ("Option A") swap-in only needs to replace this
/// module, not the schema or UI.
const List<String> kReviewLevelNames = ['새 항목', '학습 중', '복습 필요', '익숙해짐', '완전히 외움'];

/// Days until next review per level. Level 0 (new) has no schedule.
const List<int?> kReviewIntervalDays = [null, 1, 7, 30, 90];

const int kMaxReviewLevel = 4;

/// ISO8601 next-review timestamp for [level], counted from [from].
/// Returns null for level 0 (new items are never scheduled).
String? nextReviewAtForLevel(int level, DateTime from) {
  final days = kReviewIntervalDays[level];
  if (days == null) return null;
  return from.add(Duration(days: days)).toIso8601String();
}

/// Whether an item at [reviewLevel] with the given [nextReviewAt] (ISO8601
/// or null) belongs in today's review queue.
bool isDueForReview(int reviewLevel, String? nextReviewAt) {
  if (reviewLevel == 0) return true;
  if (nextReviewAt == null) return true;
  return DateTime.parse(nextReviewAt).isBefore(DateTime.now());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/data/review_schedule_test.dart`
Expected: PASS (10 tests)

- [ ] **Step 5: Add `reviewLevel`/`lastReviewedAt` to `Word`**

Replace the full contents of `mobile/lib/data/models/word.dart`:

```dart
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
  final int reviewLevel;
  final String? lastReviewedAt;

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
    this.reviewLevel = 0,
    this.lastReviewedAt,
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
        'review_level': reviewLevel,
        'last_reviewed_at': lastReviewedAt,
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
        reviewLevel: (map['review_level'] as int?) ?? 0,
        lastReviewedAt: map['last_reviewed_at'] as String?,
      );

  Word copyWith({
    int? reviewCount,
    String? nextReviewAt,
    int? reviewLevel,
    String? lastReviewedAt,
  }) =>
      Word(
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
        reviewLevel: reviewLevel ?? this.reviewLevel,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      );
}
```

- [ ] **Step 6: Add the same two fields to `Sentence`**

Replace the full contents of `mobile/lib/data/models/sentence.dart`:

```dart
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
  final int reviewLevel;
  final String? lastReviewedAt;

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
    this.reviewLevel = 0,
    this.lastReviewedAt,
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
        'review_level': reviewLevel,
        'last_reviewed_at': lastReviewedAt,
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
        reviewLevel: (map['review_level'] as int?) ?? 0,
        lastReviewedAt: map['last_reviewed_at'] as String?,
      );

  Sentence copyWith({
    int? reviewCount,
    String? nextReviewAt,
    int? reviewLevel,
    String? lastReviewedAt,
  }) =>
      Sentence(
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
        reviewLevel: reviewLevel ?? this.reviewLevel,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      );
}
```

- [ ] **Step 7: Add model tests for the two new fields**

Append to `mobile/test/data/models/word_test.dart` (inside the existing `group('Word', ...)`, before its closing `});`):

```dart
    test('toMap/fromMap round-trips reviewLevel and lastReviewedAt', () {
      final word = Word(
        id: 'w1', word: 'ephemeral', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        reviewLevel: 3,
        lastReviewedAt: '2026-08-10T00:00:00.000Z',
      );
      final restored = Word.fromMap(word.toMap());
      expect(restored.reviewLevel, 3);
      expect(restored.lastReviewedAt, '2026-08-10T00:00:00.000Z');
    });

    test('fromMap defaults reviewLevel to 0 and lastReviewedAt to null when missing', () {
      final restored = Word.fromMap({
        'id': 'w2', 'word': 'brief', 'platform': 'youtube',
        'timestamp': 10, 'saved_at': '2026-08-02T00:00:00.000Z',
      });
      expect(restored.reviewLevel, 0);
      expect(restored.lastReviewedAt, isNull);
    });

    test('copyWith updates reviewLevel and lastReviewedAt', () {
      final word = Word(
        id: 'w1', word: 'ephemeral', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = word.copyWith(reviewLevel: 2, lastReviewedAt: '2026-08-10T00:00:00.000Z');
      expect(updated.reviewLevel, 2);
      expect(updated.lastReviewedAt, '2026-08-10T00:00:00.000Z');
      expect(updated.word, 'ephemeral');
    });
```

Append the matching three tests to `mobile/test/data/models/sentence_test.dart` inside its `group('Sentence', ...)` — same shape, `Sentence(...)` instead of `Word(...)`, `original: 's-w1'` instead of `word:`, no `contentTitle`/`contentId` literal names differ only in the model's own required fields (copy the same pattern the existing file already uses for its own fixtures — read the file first to match its exact existing fixture style before appending).

- [ ] **Step 8: Run the model tests**

Run: `cd mobile && flutter test test/data/models/`
Expected: PASS (all existing + 6 new tests)

- [ ] **Step 9: Migrate the schema to v3**

In `mobile/lib/data/database.dart`, add the two columns to both `CREATE TABLE` statements in `onCreate`, bump `version` to `3`, and add an `onUpgrade` branch. Replace the full contents of the file:

```dart
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

Future<void> _addReviewLevelColumns(Database db) async {
  await db.execute('ALTER TABLE words ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0');
  await db.execute('ALTER TABLE words ADD COLUMN last_reviewed_at TEXT');
  await db.execute('ALTER TABLE sentences ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0');
  await db.execute('ALTER TABLE sentences ADD COLUMN last_reviewed_at TEXT');
}

Future<Database> openAppDatabase(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
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
            last_reviewed_at TEXT
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
            last_reviewed_at TEXT
          )
        ''');
        await _createTimerTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTimerTables(db);
        }
        if (oldVersion < 3) {
          await _addReviewLevelColumns(db);
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
```

Note `kWordsColumns`/`kSentencesColumns` are **unchanged** — see the "Global Constraints" section above for why.

- [ ] **Step 10: Fix the now-outdated `hasValidSchema` test**

The test `'returns true for a database created by openAppDatabase'` in `mobile/test/data/database_test.dart` will now FAIL: a fresh v3 `openAppDatabase` has `review_level`/`last_reviewed_at`, which are not in `kWordsColumns`/`kSentencesColumns`, so `hasValidSchema` correctly returns `false` for the app's own live database now. This is the intended new behavior (the live schema is no longer identical to a valid backup file's schema) — update the test to document it instead of asserting the old (now-wrong) expectation.

In `mobile/test/data/database_test.dart`, inside `group('hasValidSchema', ...)`, replace:

```dart
    test('returns true for a database created by openAppDatabase', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);
      expect(await hasValidSchema(db), isTrue);
      await db.close();
    });
```

with:

```dart
    test('a fresh v3 app database has extra columns beyond a valid backup schema', () async {
      // hasValidSchema pins the backup-file contract to kWordsColumns/
      // kSentencesColumns (the Chrome extension's export shape), which is
      // intentionally narrower than the app's own live schema now that the
      // app has review_level/last_reviewed_at that the extension never
      // produces. This is the correct, expected mismatch — not a bug.
      final db = await openAppDatabase(inMemoryDatabasePath);
      expect(await hasValidSchema(db), isFalse);
      await db.close();
    });
```

- [ ] **Step 11: Add the v2→v3 migration test**

In `mobile/test/data/database_test.dart`, inside `group('schema migration', ...)`, add a second test after the existing `'adds study_sessions/weekly_goals to a pre-existing v1 (Phase B) database'` test:

```dart
    test('adds review_level/last_reviewed_at to a pre-existing v2 database', () async {
      final tempDir = await Directory.systemTemp.createTemp('db_migration_v3_test');
      final dbPath = p.join(tempDir.path, 'v2.sqlite');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // Simulate a pre-existing v2 install (Home-screen-redesign era):
      // words/sentences + study_sessions/weekly_goals, no review_level yet.
      final v2Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS words (
                id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT, sentence TEXT,
                translation TEXT, platform TEXT, content_title TEXT, content_id TEXT,
                timestamp REAL, saved_at TEXT, review_count INTEGER DEFAULT 0, next_review_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sentences (
                id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT, platform TEXT,
                content_title TEXT, content_id TEXT, timestamp REAL, saved_at TEXT,
                review_count INTEGER DEFAULT 0, next_review_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS study_sessions (
                id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL, saved_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS weekly_goals (
                id TEXT PRIMARY KEY, target_minutes INTEGER NOT NULL,
                effective_from TEXT NOT NULL, created_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      await v2Db.insert('words', {
        'id': 'w1', 'word': 'ephemeral', 'platform': 'netflix',
        'content_title': 'x', 'content_id': 'y', 'timestamp': 1,
        'saved_at': '2026-08-02T00:00:00.000Z', 'review_count': 2,
      });
      await v2Db.close();

      final upgradedDb = await openAppDatabase(dbPath);

      final wordsCols = (await upgradedDb.rawQuery('PRAGMA table_info(words)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(wordsCols, contains('review_level'));
      expect(wordsCols, contains('last_reviewed_at'));

      final sentencesCols = (await upgradedDb.rawQuery('PRAGMA table_info(sentences)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(sentencesCols, contains('review_level'));
      expect(sentencesCols, contains('last_reviewed_at'));

      // Pre-existing row must survive the migration with the new columns
      // defaulted correctly.
      final rows = await upgradedDb.query('words', where: 'id = ?', whereArgs: ['w1']);
      expect(rows.single['review_level'], 0);
      expect(rows.single['last_reviewed_at'], isNull);
      expect(rows.single['review_count'], 2); // untouched

      await upgradedDb.close();
    });
```

- [ ] **Step 12: Run the full database test file**

Run: `cd mobile && flutter test test/data/database_test.dart`
Expected: PASS (all tests, including the fixed one and the new migration test)

- [ ] **Step 13: Commit**

```bash
cd mobile
git add lib/data/database.dart lib/data/models/word.dart lib/data/models/sentence.dart \
  lib/data/review_schedule.dart test/data/database_test.dart test/data/review_schedule_test.dart \
  test/data/models/word_test.dart test/data/models/sentence_test.dart
git commit -m "feat: add review_level/last_reviewed_at schema (v2->v3) and review-schedule module"
```

---

### Task 2: Repository — grading mutations and level-setting

**Files:**
- Modify: `mobile/lib/data/repository.dart`
- Test: `mobile/test/data/repository_test.dart` (extend)

**Interfaces:**
- Consumes: `nextReviewAtForLevel(int, DateTime) -> String?` and `kMaxReviewLevel` from `mobile/lib/data/review_schedule.dart` (Task 1). `Word.reviewLevel`/`lastReviewedAt`, `Sentence.reviewLevel`/`lastReviewedAt` (Task 1).
- Produces: `LearningRepository.setWordReviewLevel(String id, int level)` and `.setSentenceReviewLevel(String id, int level)` (new abstract methods + `LocalSQLiteRepository` implementations). `markWordReviewed`/`markSentenceReviewed` keep their existing signatures but change behavior (level-based, not fixed +1 day). Task 5 (add/edit modal) calls `setWordReviewLevel`/`setSentenceReviewLevel` directly.

- [ ] **Step 1: Write the failing tests**

In `mobile/test/data/repository_test.dart`, replace the two existing `markWordReviewed`/`markSentenceReviewed` tests:

```dart
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
```

with:

```dart
  test('markWordReviewed increments reviewCount, bumps reviewLevel, and schedules nextReviewAt', () async {
    await repo.saveWord(_word('w1', reviewCount: 2));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewCount, 3);
    expect(word.reviewLevel, 1);
    expect(word.lastReviewedAt, isNotNull);
    expect(word.nextReviewAt, isNotNull);
  });

  test('markWordReviewed caps reviewLevel at kMaxReviewLevel', () async {
    await repo.saveWord(_word('w1').copyWith(reviewLevel: kMaxReviewLevel));
    await repo.markWordReviewed('w1');
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, kMaxReviewLevel);
  });

  test('markSentenceReviewed increments reviewCount, bumps reviewLevel, and schedules nextReviewAt', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.markSentenceReviewed('s1');
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewCount, 1);
    expect(sentence.reviewLevel, 1);
    expect(sentence.lastReviewedAt, isNotNull);
    expect(sentence.nextReviewAt, isNotNull);
  });

  test('setWordReviewLevel sets an arbitrary level directly', () async {
    await repo.saveWord(_word('w1'));
    await repo.setWordReviewLevel('w1', 3);
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 3);
    expect(word.lastReviewedAt, isNotNull);
    expect(word.nextReviewAt, isNotNull);
  });

  test('setSentenceReviewLevel sets an arbitrary level directly', () async {
    await repo.saveSentence(_sentence('s1'));
    await repo.setSentenceReviewLevel('s1', 0);
    final sentence = (await repo.getSentences()).single;
    expect(sentence.reviewLevel, 0);
    expect(sentence.nextReviewAt, isNull); // level 0 has no schedule
  });
```

Add the import at the top of the file:

```dart
import 'package:english_helper_app/data/review_schedule.dart';
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd mobile && flutter test test/data/repository_test.dart`
Expected: the reviewCount/nextReviewAt assertions still PASS (unchanged behavior); `reviewLevel`/`lastReviewedAt` assertions FAIL (still 0/null — the old fixed "+1 day" logic doesn't touch them); `setWordReviewLevel`/`setSentenceReviewLevel` calls FAIL to compile (`Error: The method 'setWordReviewLevel' isn't defined`).

- [ ] **Step 3: Implement the repository changes**

In `mobile/lib/data/repository.dart`, add the import:

```dart
import 'review_schedule.dart';
```

Add two new methods to the `LearningRepository` abstract class (after `markSentenceReviewed`):

```dart
  Future<void> setWordReviewLevel(String id, int level);
  Future<void> setSentenceReviewLevel(String id, int level);
```

Replace `markWordReviewed`:

```dart
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
    );
    await db.insert('words', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }
```

Replace `markSentenceReviewed`:

```dart
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
    );
    await db.insert('sentences', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }
```

Add the two new methods (after `markSentenceReviewed`'s implementation):

```dart
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
    );
    await db.insert('sentences', updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }
```

Note: `copyWith`'s `reviewLevel: level` line above must actually pass `level` even when `level == 0` — check `Word.copyWith`/`Sentence.copyWith` from Task 1 use `reviewLevel ?? this.reviewLevel` (nullable-int pattern), which breaks for `level = 0` only if `0` were passed as `null`, which it never is (`int` here, not `int?`) — `0 ?? this.reviewLevel` correctly evaluates to `0`. No bug; confirmed safe.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/data/repository_test.dart`
Expected: PASS (all existing tests + 6 new ones)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: `flutter analyze` no issues (note: `flutter analyze` will flag `FlashcardScreen`/`FlashcardItem` as NOT implementing the two new abstract methods only if something implements `LearningRepository` directly elsewhere — confirm via the analyzer output that `LocalSQLiteRepository` is the only implementer). `flutter test` passes fully.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/data/repository.dart test/data/repository_test.dart
git commit -m "feat: level-based grading in markXReviewed, add setXReviewLevel"
```

---

### Task 3: Card mode — typing-based recall

**Files:**
- Modify: `mobile/lib/features/flashcard/flashcard_item.dart` (full rewrite)
- Modify: `mobile/lib/features/flashcard/flashcard_screen.dart` (full rewrite of card-mode path; list mode and modal come in Tasks 4-5)
- Test: `mobile/test/features/flashcard/flashcard_screen_test.dart` (full rewrite)
- Test: `mobile/test/features/flashcard/flashcard_item_test.dart` (new)

**Interfaces:**
- Consumes: `isDueForReview(int, String?) -> bool`, `kReviewLevelNames`, `kReviewIntervalDays` from `mobile/lib/data/review_schedule.dart` (Task 1). `LearningRepository.markWordReviewed`/`markSentenceReviewed` (Task 2, behavior already changed). `AppColors`/`AppFonts` from `mobile/lib/theme/app_theme.dart`.
- Produces: `FlashcardItem` gains `promptLabel`, `prompt`, `correctAnswer`, `backHeadline`, `backSubtext`, `backDetail`, `backExample`, `reviewLevel`, `lastReviewedAt` fields (replacing the old `front`/`back` pair). Tasks 4-5 reuse `FlashcardItem.fromWord`/`.fromSentence` and the screen's mode-toggle state shape (`_mode` field, documented in Task 4's brief).

- [ ] **Step 1: Rewrite `flashcard_item.dart`**

Replace the full contents of `mobile/lib/features/flashcard/flashcard_item.dart`:

```dart
import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

/// One flashcard's testable content. Word items test 뜻→단어 (see the
/// translation, type the English word); sentence items test 번역→원문.
class FlashcardItem {
  final String id;
  final bool isWord;
  final String promptLabel;
  final String prompt;
  final String correctAnswer;
  final String backHeadline;
  final String backSubtext;
  final String backDetail;
  final String backExample;
  final String contentTitle;
  final String platform;
  final int reviewLevel;
  final String? lastReviewedAt;

  const FlashcardItem({
    required this.id,
    required this.isWord,
    required this.promptLabel,
    required this.prompt,
    required this.correctAnswer,
    required this.backHeadline,
    required this.backSubtext,
    required this.backDetail,
    required this.backExample,
    required this.contentTitle,
    required this.platform,
    required this.reviewLevel,
    required this.lastReviewedAt,
  });

  factory FlashcardItem.fromWord(Word w) => FlashcardItem(
        id: w.id,
        isWord: true,
        promptLabel: '영어로 어떻게 말할까요?',
        prompt: w.translation.isNotEmpty ? w.translation : w.definition,
        correctAnswer: w.word,
        backHeadline: w.word,
        backSubtext: w.translation,
        backDetail: w.definition,
        backExample: w.sentence,
        contentTitle: w.contentTitle,
        platform: w.platform,
        reviewLevel: w.reviewLevel,
        lastReviewedAt: w.lastReviewedAt,
      );

  factory FlashcardItem.fromSentence(Sentence s) => FlashcardItem(
        id: s.id,
        isWord: false,
        promptLabel: '원문을 입력해보세요',
        prompt: s.translation,
        correctAnswer: s.original,
        backHeadline: s.original,
        backSubtext: s.translation,
        backDetail: '',
        backExample: '',
        contentTitle: s.contentTitle,
        platform: s.platform,
        reviewLevel: s.reviewLevel,
        lastReviewedAt: s.lastReviewedAt,
      );
}
```

- [ ] **Step 2: Write the failing `FlashcardItem` test**

Create `mobile/test/features/flashcard/flashcard_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/flashcard/flashcard_item.dart';

Word _word() => Word(
      id: 'w1', word: 'ephemeral', definition: 'lasting for a very short time',
      sentence: 'Nothing in life is ephemeral.', translation: '덧없는',
      platform: 'netflix', contentTitle: 'Title', contentId: 'c1',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: 2, lastReviewedAt: '2026-08-10T00:00:00.000Z',
    );

Sentence _sentence() => Sentence(
      id: 's1', original: 'Nothing in life is ephemeral.', translation: '인생에서 덧없지 않은 것은 없다.',
      platform: 'youtube', contentTitle: 'Video', contentId: 'c2',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
    );

void main() {
  group('FlashcardItem.fromWord', () {
    test('tests 뜻→단어: prompt is translation, answer is the English word', () {
      final item = FlashcardItem.fromWord(_word());
      expect(item.isWord, isTrue);
      expect(item.prompt, '덧없는');
      expect(item.correctAnswer, 'ephemeral');
      expect(item.backHeadline, 'ephemeral');
      expect(item.backSubtext, '덧없는');
      expect(item.backDetail, 'lasting for a very short time');
      expect(item.backExample, 'Nothing in life is ephemeral.');
      expect(item.reviewLevel, 2);
      expect(item.lastReviewedAt, '2026-08-10T00:00:00.000Z');
    });

    test('falls back to definition as prompt when translation is empty', () {
      final word = _word().copyWith();
      final noTranslation = Word(
        id: word.id, word: word.word, definition: word.definition,
        sentence: word.sentence, translation: '', platform: word.platform,
        contentTitle: word.contentTitle, contentId: word.contentId,
        timestamp: word.timestamp, savedAt: word.savedAt,
      );
      final item = FlashcardItem.fromWord(noTranslation);
      expect(item.prompt, 'lasting for a very short time');
    });
  });

  group('FlashcardItem.fromSentence', () {
    test('tests 번역→원문: prompt is translation, answer is the original', () {
      final item = FlashcardItem.fromSentence(_sentence());
      expect(item.isWord, isFalse);
      expect(item.prompt, '인생에서 덧없지 않은 것은 없다.');
      expect(item.correctAnswer, 'Nothing in life is ephemeral.');
      expect(item.backHeadline, 'Nothing in life is ephemeral.');
      expect(item.backSubtext, '인생에서 덧없지 않은 것은 없다.');
      expect(item.backDetail, '');
      expect(item.backExample, '');
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails, then passes**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_item_test.dart`
Expected: FAIL first (old `FlashcardItem` has `front`/`back`, not these fields — compile error), then re-run after Step 1's rewrite (already done above) to confirm PASS. (Steps are ordered TDD-style per task convention; since `flashcard_item.dart` was rewritten in Step 1, this test should already pass — run it now to confirm.)
Expected after Step 1 lands: PASS (4 tests)

- [ ] **Step 4: Write the failing card-mode screen tests**

Replace the full contents of `mobile/test/features/flashcard/flashcard_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/flashcard/flashcard_screen.dart';

Word _dueWord({String id = 'w1', int reviewLevel = 0, String? lastReviewedAt}) => Word(
      id: id, word: 'ephemeral', definition: 'lasting for a very short time',
      translation: '덧없는', platform: 'netflix', contentTitle: 'Title',
      contentId: 'c1', timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: reviewLevel, lastReviewedAt: lastReviewedAt,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildApp(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: FlashcardScreen()),
    );
  }

  testWidgets('shows empty state when there is nothing saved', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('shows the prompt (not the raw word) on the front of a due card', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('덧없는'), findsOneWidget); // prompt = translation
    expect(find.text('ephemeral'), findsNothing); // answer not shown yet
  });

  testWidgets('typing the correct answer and submitting shows correct feedback', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ephemeral'); // case-insensitive match
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('정답'), findsWidgets);
  });

  testWidgets('typing a wrong answer shows the correct answer inline', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrongword');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('오답'), findsWidgets);
    expect(find.textContaining('ephemeral'), findsWidgets); // correct answer revealed
  });

  testWidgets('submitting an empty answer does not grade', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('정답'), findsNothing);
    expect(find.textContaining('오답'), findsNothing);
  });

  testWidgets('알아요 is only visible after flipping to the back', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('알아요'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('flashcard-body')));
    await tester.pumpAndSettle();

    expect(find.text('알아요'), findsOneWidget);
  });

  testWidgets('알아요 marks the word reviewed and does not show the typed answer on the back', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'my typed guess');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flashcard-body')));
    await tester.pumpAndSettle();

    // Back view shows the correct detail, never the user's raw input string.
    expect(find.text('my typed guess'), findsNothing);
    expect(find.text('lasting for a very short time'), findsOneWidget);

    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 1);
  });

  testWidgets('다시 requeues without touching the database', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('다시'));
    await tester.pumpAndSettle();

    final word = (await repo.getWords()).single;
    expect(word.reviewLevel, 0);
    expect(word.lastReviewedAt, isNull);
    // Single-item queue: 다시 requeues it, so it's still showing.
    expect(find.text('덧없는'), findsOneWidget);
  });

  testWidgets('an item not yet due is excluded from the queue', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
    await repo.saveWord(Word(
      id: 'w1', word: 'ephemeral', translation: '덧없는', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: 2, nextReviewAt: future,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 복습 완료'), findsOneWidget);
  });

  testWidgets('reloads the queue automatically after an import while empty', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);

    await repo.saveWord(_dueWord());
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsNothing);
    expect(find.text('덧없는'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run to verify tests fail**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart`
Expected: FAIL — old `flashcard_screen.dart` still uses `front`/`back`/plain flip, no `TextField`, no `Icons.arrow_forward`, no due-date filtering.

- [ ] **Step 6: Rewrite `flashcard_screen.dart`**

Replace the full contents of `mobile/lib/features/flashcard/flashcard_screen.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../data/review_schedule.dart';
import '../../shared/widgets/empty_state.dart';
import '../../theme/app_theme.dart';
import 'flashcard_item.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<FlashcardItem>? _queue;
  int _initialQueueLength = 0;
  bool _flipped = false;
  bool _graded = false;
  bool _wasCorrect = false;
  final _answerController = TextEditingController();

  bool _hadItemsInitially = false;

  LearningRepository? _repo;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<LearningRepository>();
    if (!identical(repo, _repo)) {
      _repo?.removeListener(_onRepositoryChanged);
      _repo = repo;
      repo.addListener(_onRepositoryChanged);
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_onRepositoryChanged);
    _answerController.dispose();
    super.dispose();
  }

  void _onRepositoryChanged() {
    if (_queue == null || _queue!.isEmpty) {
      _loadQueue();
    }
  }

  Future<void> _loadQueue() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    final items = [
      ...words
          .where((w) => isDueForReview(w.reviewLevel, w.nextReviewAt))
          .map(FlashcardItem.fromWord),
      ...sentences
          .where((s) => isDueForReview(s.reviewLevel, s.nextReviewAt))
          .map(FlashcardItem.fromSentence),
    ]..shuffle(Random());
    if (!mounted) return;
    setState(() {
      _queue = items;
      _initialQueueLength = items.length;
      _hadItemsInitially = words.isNotEmpty || sentences.isNotEmpty;
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  void _again() {
    setState(() {
      final current = _queue!.removeAt(0);
      _queue!.add(current);
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
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
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  void _submitAnswer() {
    final input = _answerController.text.trim();
    if (input.isEmpty) return;
    final current = _queue!.first;
    setState(() {
      _graded = true;
      _wasCorrect = input.toLowerCase() == current.correctAnswer.trim().toLowerCase();
    });
  }

  void _toggleFlip() {
    setState(() => _flipped = !_flipped);
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
          return EmptyState(
            message: _hadItemsInitially
                ? '오늘 복습 완료! 🎉'
                : '아직 저장된 항목이 없어요.\n크롬 확장 프로그램에서 단어나 문장을 저장해보세요!',
          );
        }
        final current = queue.first;
        final progress = _initialQueueLength == 0
            ? 0.0
            : 1 - (queue.length / _initialQueueLength);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              _CardHeader(item: current),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFE5E8F0),
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('flashcard-body'),
                  onTap: _toggleFlip,
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppColors.border),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _flipped
                          ? _CardBack(item: current)
                          : _CardFront(item: current, promptSize: 24),
                    ),
                  ),
                ),
              ),
              if (!_flipped) ...[
                const SizedBox(height: 14),
                _AnswerInput(
                  controller: _answerController,
                  onSubmit: _submitAnswer,
                  graded: _graded,
                  wasCorrect: _wasCorrect,
                  correctAnswer: current.correctAnswer,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _again,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: AppColors.borderStrong),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('다시'),
                    ),
                  ),
                  if (_flipped) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _know,
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: const Text('알아요'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final FlashcardItem item;
  const _CardHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = kReviewLevelNames[item.reviewLevel];
    final days = kReviewIntervalDays[item.reviewLevel];
    final gap = days == null ? '' : '${days}일';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accentInk,
            ),
          ),
        ),
        if (gap.isNotEmpty) ...[
          const SizedBox(width: 7),
          Text(gap, style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary)),
        ],
        const Spacer(),
        Text(
          '마지막 복습 ${item.lastReviewedAt == null ? '없음' : _shortDate(item.lastReviewedAt!)}',
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
        ),
      ],
    );
  }

  static String _shortDate(String iso) {
    final d = DateTime.parse(iso);
    return '${d.month}/${d.day}';
  }
}

class _CardFront extends StatelessWidget {
  final FlashcardItem item;
  final double promptSize;
  const _CardFront({required this.item, required this.promptSize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.promptLabel,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.12,
              color: AppColors.inkTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.prompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: promptSize,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final FlashcardItem item;
  const _CardBack({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.backHeadline, style: const TextStyle(
          fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 26, color: AppColors.ink)),
        if (item.backSubtext.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(item.backSubtext, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
        if (item.backDetail.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.backDetail, style: const TextStyle(fontSize: 13.5, color: AppColors.inkTertiary, height: 1.6)),
        ],
        if (item.backExample.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 18),
          Text(item.backExample, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 15, color: AppColors.inkSecondary, height: 1.55)),
        ],
      ],
    );
  }
}

class _AnswerInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool graded;
  final bool wasCorrect;
  final String correctAnswer;

  const _AnswerInput({
    required this.controller,
    required this.onSubmit,
    required this.graded,
    required this.wasCorrect,
    required this.correctAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.only(left: 16, right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderStrong, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: '답을 입력하세요'),
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: onSubmit,
                icon: const Icon(Icons.arrow_forward),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        if (graded) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Text(
                  wasCorrect ? '정답!' : '오답',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: wasCorrect ? AppColors.accentInk : AppColors.danger,
                  ),
                ),
                if (!wasCorrect) ...[
                  const SizedBox(width: 8),
                  Text('정답: $correctAnswer', style: const TextStyle(fontSize: 12.5, color: AppColors.inkTertiary)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/flashcard/`
Expected: PASS (all `flashcard_item_test.dart` and `flashcard_screen_test.dart` tests)

- [ ] **Step 8: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 9: Commit**

```bash
cd mobile
git add lib/features/flashcard/flashcard_item.dart lib/features/flashcard/flashcard_screen.dart \
  test/features/flashcard/flashcard_screen_test.dart test/features/flashcard/flashcard_item_test.dart
git commit -m "feat: typing-recall card mode with due-date queue filtering"
```

---

### Task 4: List mode and type filter

**Files:**
- Modify: `mobile/lib/features/flashcard/flashcard_screen.dart`
- Test: `mobile/test/features/flashcard/flashcard_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `kReviewLevelNames` from `mobile/lib/data/review_schedule.dart` (Task 1). `FlashcardItem` (Task 3, unchanged shape). `AppColors`/`AppFonts`.
- Produces: `_FlashcardScreenState` gains `_mode` (`_FlashcardMode` enum: `card`, `list`) and `_typeFilter` (`_TypeFilter` enum: `all`, `wordOnly`, `sentenceOnly`) fields, both driving what Task 3's card-mode queue AND this task's list view show. Task 5 (add/edit modal) is triggered from this task's list items and FAB.

- [ ] **Step 1: Write the failing tests**

Append to `mobile/test/features/flashcard/flashcard_screen_test.dart` (before the file's closing `}`):

```dart
  testWidgets('list mode shows all saved items regardless of due date', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
    await repo.saveWord(_dueWord(id: 'w1'));
    await repo.saveWord(Word(
      id: 'w2', word: 'brief', translation: '짧은', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z', reviewLevel: 2, nextReviewAt: future,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget); // not-yet-due item still shows in list mode
  });

  testWidgets('level filter chip narrows the list', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(id: 'w1', reviewLevel: 0));
    await repo.saveWord(Word(
      id: 'w2', word: 'brief', translation: '짧은', platform: 'netflix',
      contentTitle: 'Title', contentId: 'c1', timestamp: 1,
      savedAt: '2026-08-02T00:00:00.000Z', reviewLevel: 2,
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget);

    await tester.tap(find.text(kReviewLevelNames[2]));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(find.text('brief'), findsOneWidget);
  });

  testWidgets('type filter narrows both card and list mode', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(id: 'w1'));
    await repo.saveSentence(Sentence(
      id: 's1', original: 'Nothing in life is ephemeral.', translation: '인생에서 덧없지 않은 것은 없다.',
      platform: 'youtube', contentTitle: 'Video', contentId: 'c2',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('Nothing in life is ephemeral.'), findsOneWidget);

    await tester.tap(find.text('단어'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('Nothing in life is ephemeral.'), findsNothing);
  });
```

Add the import at the top of the test file:

```dart
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/review_schedule.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart`
Expected: FAIL — no "목록" tab, no level/type filter chips exist yet.

- [ ] **Step 3: Add list mode to `flashcard_screen.dart`**

In `mobile/lib/features/flashcard/flashcard_screen.dart`, add two enums above the `FlashcardScreen` class:

```dart
enum _FlashcardMode { card, list }
enum _TypeFilter { all, wordOnly, sentenceOnly }
```

In `_FlashcardScreenState`, add three fields (with the other state fields):

```dart
  _FlashcardMode _mode = _FlashcardMode.card;
  _TypeFilter _typeFilter = _TypeFilter.all;
  int? _listLevelFilter; // null = 전체
```

Add two new imports at the top:

```dart
import '../../data/models/sentence.dart';
import '../../data/models/word.dart';
```

Change `_loadQueue` to also keep the full (not just due) lists around for list mode, and to apply `_typeFilter` to the card queue. Replace `_loadQueue`:

```dart
  List<Word> _allWords = [];
  List<Sentence> _allSentences = [];

  Future<void> _loadQueue() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    _allWords = words;
    _allSentences = sentences;
    final dueItems = [
      if (_typeFilter != _TypeFilter.sentenceOnly)
        ...words
            .where((w) => isDueForReview(w.reviewLevel, w.nextReviewAt))
            .map(FlashcardItem.fromWord),
      if (_typeFilter != _TypeFilter.wordOnly)
        ...sentences
            .where((s) => isDueForReview(s.reviewLevel, s.nextReviewAt))
            .map(FlashcardItem.fromSentence),
    ]..shuffle(Random());
    if (!mounted) return;
    setState(() {
      _queue = dueItems;
      _initialQueueLength = dueItems.length;
      _hadItemsInitially = words.isNotEmpty || sentences.isNotEmpty;
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  void _setTypeFilter(_TypeFilter filter) {
    setState(() => _typeFilter = filter);
    _loadQueue();
  }

  List<FlashcardItem> get _listItems {
    final items = [
      if (_typeFilter != _TypeFilter.sentenceOnly) ..._allWords.map(FlashcardItem.fromWord),
      if (_typeFilter != _TypeFilter.wordOnly) ..._allSentences.map(FlashcardItem.fromSentence),
    ];
    if (_listLevelFilter == null) return items;
    return items.where((it) => it.reviewLevel == _listLevelFilter).toList();
  }
```

`(note: `Word`/`Sentence` model field `reviewLevel` and `nextReviewAt` already exist from Task 1 — this step only reads them.)`

Change `build()` to add the mode/type toggle above the existing card-mode `Builder`, and branch to a list view when `_mode == _FlashcardMode.list`. Replace the whole `build` method:

```dart
  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return Scaffold(
      appBar: AppBar(title: const Text('플래시카드')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                _ModeToggle(
                  mode: _mode,
                  listCount: _allWords.length + _allSentences.length,
                  onCard: () => setState(() => _mode = _FlashcardMode.card),
                  onList: () => setState(() => _mode = _FlashcardMode.list),
                ),
                const SizedBox(height: 10),
                _TypeFilterRow(current: _typeFilter, onPick: _setTypeFilter),
              ],
            ),
          ),
          Expanded(
            child: queue == null
                ? const Center(child: CircularProgressIndicator())
                : _mode == _FlashcardMode.card
                    ? _buildCardMode(queue)
                    : _buildListMode(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMode(List<FlashcardItem> queue) {
    if (queue.isEmpty) {
      return EmptyState(
        message: _hadItemsInitially
            ? '오늘 복습 완료! 🎉'
            : '아직 저장된 항목이 없어요.\n크롬 확장 프로그램에서 단어나 문장을 저장해보세요!',
      );
    }
    final current = queue.first;
    final progress = _initialQueueLength == 0 ? 0.0 : 1 - (queue.length / _initialQueueLength);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _CardHeader(item: current),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE5E8F0),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              key: const ValueKey('flashcard-body'),
              onTap: _toggleFlip,
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _flipped ? _CardBack(item: current) : _CardFront(item: current, promptSize: 24),
                ),
              ),
            ),
          ),
          if (!_flipped) ...[
            const SizedBox(height: 14),
            _AnswerInput(
              controller: _answerController,
              onSubmit: _submitAnswer,
              graded: _graded,
              wasCorrect: _wasCorrect,
              correctAnswer: current.correctAnswer,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _again,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.borderStrong),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('다시'),
                ),
              ),
              if (_flipped) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _know,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: const Text('알아요'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListMode() {
    final items = _listItems;
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _levelChip(label: '전체', level: null),
                    ),
                    for (var lvl = 0; lvl <= kMaxReviewLevel; lvl++)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: _levelChip(label: kReviewLevelNames[lvl], level: lvl),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(message: '해당 레벨의 항목이 없어요')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: items.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _ListItemCard(
                          item: items[index],
                          onTap: () => _openEditSheet(items[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: () => _openEditSheet(null),
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.ink,
            icon: const Icon(Icons.add),
            label: const Text('추가'),
          ),
        ),
      ],
    );
  }

  Widget _levelChip({required String label, required int? level}) {
    final selected = _listLevelFilter == level;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      shape: const StadiumBorder(),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      side: BorderSide(color: selected ? AppColors.ink : AppColors.border),
      labelStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: selected ? Colors.white : AppColors.inkSecondary,
      ),
      onSelected: (_) => setState(() => _listLevelFilter = level),
    );
  }

  void _openEditSheet(FlashcardItem? item) {
    // Wired up in Task 5.
  }
```

Add three small stateless widgets after `_AnswerInput` (still in the same file):

```dart
class _ModeToggle extends StatelessWidget {
  final _FlashcardMode mode;
  final int listCount;
  final VoidCallback onCard;
  final VoidCallback onList;

  const _ModeToggle({required this.mode, required this.listCount, required this.onCard, required this.onList});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE9ECF3), borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          Expanded(child: _segment('카드', mode == _FlashcardMode.card, onCard)),
          Expanded(child: _segment('목록 $listCount', mode == _FlashcardMode.list, onList)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? AppColors.ink : AppColors.inkTertiary,
          ),
        ),
      ),
    );
  }
}

class _TypeFilterRow extends StatelessWidget {
  final _TypeFilter current;
  final void Function(_TypeFilter) onPick;
  const _TypeFilterRow({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _TypeFilter value) {
      final selected = current == value;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          shape: const StadiumBorder(),
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.ink,
          side: BorderSide(color: selected ? AppColors.ink : AppColors.border),
          labelStyle: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: selected ? Colors.white : AppColors.inkSecondary,
          ),
          onSelected: (_) => onPick(value),
        ),
      );
    }

    return Row(
      children: [
        chip('전체', _TypeFilter.all),
        chip('단어', _TypeFilter.wordOnly),
        chip('문장', _TypeFilter.sentenceOnly),
      ],
    );
  }
}

class _ListItemCard extends StatelessWidget {
  final FlashcardItem item;
  final VoidCallback onTap;
  const _ListItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.backHeadline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: AppColors.ink)),
                      if (item.backSubtext.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.backSubtext, style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    kReviewLevelNames[item.reviewLevel],
                    style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accentInk),
                  ),
                ),
              ],
            ),
            if (item.backExample.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.only(left: 9),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border, width: 2))),
                child: Text(item.backExample, style: const TextStyle(fontSize: 12.5, color: AppColors.inkTertiary)),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 9),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F2F7)))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '마지막 복습 ${item.lastReviewedAt == null ? '없음' : _CardHeader._shortDate(item.lastReviewedAt!)}',
                      style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart`
Expected: PASS (all tests, including Task 3's and this task's new ones)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/flashcard/flashcard_screen.dart test/features/flashcard/flashcard_screen_test.dart
git commit -m "feat: flashcard list mode with type/level filters"
```

---

### Task 5: Add/edit modal

**Files:**
- Modify: `mobile/lib/features/flashcard/flashcard_screen.dart`
- Test: `mobile/test/features/flashcard/flashcard_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `LearningRepository.saveWord`/`saveSentence`/`deleteWord`/`deleteSentence`/`setWordReviewLevel`/`setSentenceReviewLevel` (Task 2). `kReviewLevelNames`, `kReviewIntervalDays`, `kMaxReviewLevel` from `review_schedule.dart` (Task 1). `_openEditSheet(FlashcardItem?)` stub from Task 4 (this task fills it in).
- Produces: nothing further consumed by other tasks — this is the final task of the plan.

- [ ] **Step 1: Write the failing tests**

Append to `mobile/test/features/flashcard/flashcard_screen_test.dart` (before the file's closing `}`):

```dart
  testWidgets('tapping + opens the add sheet, saving creates a new word', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(find.text('새 항목'), findsWidgets); // sheet title or level-0 row

    await tester.enterText(find.byKey(const ValueKey('edit-en-field')), 'ephemeral');
    await tester.enterText(find.byKey(const ValueKey('edit-ko-field')), '덧없는');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words, hasLength(1));
    expect(words.single.word, 'ephemeral');
    expect(words.single.translation, '덧없는');
  });

  testWidgets('tapping a list item opens the edit sheet pre-filled, saving updates it', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('항목 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ephemeral'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('edit-ko-field')), '수정된 뜻');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words.single.translation, '수정된 뜻');
    expect(words.single.id, 'w1'); // same id, upserted not duplicated
  });

  testWidgets('delete button only shows when editing, and deletes the item', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord());

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(find.text('삭제'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();
    expect(find.text('삭제'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    final words = await repo.getWords();
    expect(words, isEmpty);
  });

  testWidgets('tapping a review level in the sheet applies it immediately', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await repo.saveWord(_dueWord(reviewLevel: 0));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(kReviewLevelNames[3]));
    await tester.pumpAndSettle();

    // Applied immediately, independent of 저장/취소.
    final words = await repo.getWords();
    expect(words.single.reviewLevel, 3);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart`
Expected: FAIL — `_openEditSheet` is currently a no-op stub, no sheet appears.

- [ ] **Step 3: Implement the edit sheet**

`mobile/lib/features/flashcard/flashcard_screen.dart` already has `import 'dart:math';` at the top from Task 3 (for `Random` in `_loadQueue`'s shuffle) — no new import needed for the id generator below, which reuses the same `Random` class.

Add a small id generator near the top of the file, after the imports:

```dart
// Dart's `_`-prefixed privacy is per-file, so this can't import
// study_timer_repository.dart's identical private _generateId() — a small
// duplicate is simpler than exporting a cross-feature utility for 3 lines.
String _generateId() {
  final rand = Random();
  return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
}
```

Replace the `_openEditSheet` stub in `_FlashcardScreenState`:

```dart
  void _openEditSheet(FlashcardItem? item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemSheet(
        item: item,
        onSaved: _loadQueue,
      ),
    );
  }
```

Add the `_EditItemSheet` widget at the end of the file (after `_ListItemCard`):

```dart
class _EditItemSheet extends StatefulWidget {
  final FlashcardItem? item; // null = creating a new item
  final VoidCallback onSaved;

  const _EditItemSheet({required this.item, required this.onSaved});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late bool _isWord;
  late final TextEditingController _enController;
  late final TextEditingController _koController;
  late final TextEditingController _exController;
  late int _level;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _isWord = item?.isWord ?? true;
    _enController = TextEditingController(text: item?.backHeadline ?? '');
    _koController = TextEditingController(text: item?.backSubtext ?? '');
    _exController = TextEditingController(text: item?.backExample ?? '');
    _level = item?.reviewLevel ?? 0;
  }

  @override
  void dispose() {
    _enController.dispose();
    _koController.dispose();
    _exController.dispose();
    super.dispose();
  }

  Future<void> _pickLevel(int level) async {
    setState(() => _level = level);
    final item = widget.item;
    if (item == null) return; // new item: level is only saved when 저장 is tapped
    final repo = context.read<LearningRepository>();
    if (item.isWord) {
      await repo.setWordReviewLevel(item.id, level);
    } else {
      await repo.setSentenceReviewLevel(item.id, level);
    }
  }

  Future<void> _save() async {
    final repo = context.read<LearningRepository>();
    final en = _enController.text.trim();
    final ko = _koController.text.trim();
    if (en.isEmpty) return;

    if (_isWord) {
      final existing = widget.item;
      await repo.saveWord(Word(
        id: existing?.id ?? _generateId(),
        word: en,
        translation: ko,
        sentence: _exController.text.trim(),
        definition: '', // the edit sheet has no definition field (spec §5.4)
        platform: existing == null ? '' : existing.platform,
        contentTitle: existing?.contentTitle ?? '',
        contentId: '',
        timestamp: 0,
        savedAt: DateTime.now().toIso8601String(),
        reviewLevel: _level,
      ));
    } else {
      final existing = widget.item;
      await repo.saveSentence(Sentence(
        id: existing?.id ?? _generateId(),
        original: en,
        translation: ko,
        platform: existing?.platform ?? '',
        contentTitle: existing?.contentTitle ?? '',
        contentId: '',
        timestamp: 0,
        savedAt: DateTime.now().toIso8601String(),
        reviewLevel: _level,
      ));
    }
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    final repo = context.read<LearningRepository>();
    if (item.isWord) {
      await repo.deleteWord(item.id);
    } else {
      await repo.deleteSentence(item.id);
    }
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 18,
        bottom: 26 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
                Expanded(
                  child: Text(
                    _isNew ? '항목 추가' : '항목 수정',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                TextButton(onPressed: _save, child: const Text('저장')),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: const Color(0xFFE9ECF3), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Expanded(child: _typeSegment('단어', _isWord, () => setState(() => _isWord = true))),
                  Expanded(child: _typeSegment('문장', !_isWord, () => setState(() => _isWord = false))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(_isWord ? '영어 단어' : '영어 원문', style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('edit-en-field'),
              controller: _enController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('한글 뜻', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('edit-ko-field'),
              controller: _koController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_isWord) ...[
              const SizedBox(height: 16),
              const Text('응용 예문', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
              const SizedBox(height: 7),
              TextField(
                key: const ValueKey('edit-ex-field'),
                controller: _exController,
                maxLines: 3,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 18),
            const Text('복습 상태', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 8),
            for (var lvl = 0; lvl <= kMaxReviewLevel; lvl++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _levelRow(lvl),
              ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.borderStrong),
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('삭제'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeSegment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 12.5, color: selected ? AppColors.ink : AppColors.inkTertiary)),
      ),
    );
  }

  Widget _levelRow(int level) {
    final selected = _level == level;
    final days = kReviewIntervalDays[level];
    return GestureDetector(
      onTap: () => _pickLevel(level),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTint : Colors.white,
          border: Border.all(color: selected ? AppColors.accent : AppColors.borderStrong),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Text(kReviewLevelNames[level], style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 14, color: selected ? AppColors.accentInk : AppColors.ink)),
            const Spacer(),
            Text(days == null ? '-' : '${days}일', style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5, color: AppColors.inkQuaternary)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/flashcard/flashcard_screen_test.dart`
Expected: PASS (all tests across Tasks 3-5)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/flashcard/flashcard_screen.dart test/features/flashcard/flashcard_screen_test.dart
git commit -m "feat: add/edit/delete modal for flashcard items"
```

---

## Self-Review Notes

- **Spec coverage:** §3.1 schema → Task 1. §3.2 level schedule → Task 1 (`review_schedule.dart`). §3.3 grading/level-set logic → Task 2. §4 queue filtering → Task 3. §5.1 mode/type toggle → Task 4. §5.2 card mode → Task 3. §5.3 list mode → Task 4. §5.4 add/edit modal → Task 5. §6 error handling (empty states, empty-answer no-op) → Task 3 (`_submitAnswer` early-return) and Task 4 (list empty state). §7 tests → one test per spec bullet, distributed across Tasks 1-5. §8 out-of-scope items (FSRS, auto-demotion, showing the typed answer on the back) → none implemented, confirmed by the explicit test in Task 3 ("does not show the typed answer").
- **Placeholder scan:** none found — every step has literal code and exact commands.
- **Type consistency:** `isDueForReview(int, String?) -> bool` signature matches everywhere it's called (Task 3's `_loadQueue`, Task 4's updated `_loadQueue`). `FlashcardItem`'s field names (`promptLabel`, `prompt`, `correctAnswer`, `backHeadline`, `backSubtext`, `backDetail`, `backExample`, `reviewLevel`, `lastReviewedAt`) are identical across Task 3's definition, its own test, and every consumer in Tasks 3-5. `setWordReviewLevel(String, int)`/`setSentenceReviewLevel(String, int)` signatures match between Task 2's definition and Task 5's `_EditItemSheet._pickLevel` call sites. `kMaxReviewLevel`/`kReviewLevelNames`/`kReviewIntervalDays` are consumed with matching types (`int`, `List<String>`, `List<int?>`) in Tasks 2-5.
- **Cross-task file ownership:** `flashcard_screen.dart` is modified by Tasks 3, 4, and 5 in sequence — each task's steps show the full replacement or targeted addition assuming the previous task's version is already in place (Task 4's `build()` replacement supersedes Task 3's; Task 5 only adds to what Task 4 left). Dispatch these three tasks in strict order.
