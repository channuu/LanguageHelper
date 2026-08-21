# 가져오기 · 설정 화면 (1f) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the 가져오기(Import)와 설정(Settings) screens from their bare Phase B state to match the Claude Design mockup `English Helper UI.dc.html` §1f exactly, including a new "마지막 가져오기" persisted summary and a reusable weekly-goal editor shared with the Timer screen.

**Architecture:** Extend `LearningRepository`/`LocalSQLiteRepository` with duplicate-skip counting and a `SharedPreferences`-backed last-import summary (mirroring `StudyTimerRepository`'s existing active-session persistence pattern). Rebuild both screens as StatelessWidget/StatefulWidget following the established no-AppBar, big-title pattern (Home/Timer). Expose the Timer screen's existing `_GoalSheet` publicly so Settings can reuse it verbatim for its "주간 학습 목표" row.

**Tech Stack:** Flutter, Provider, sqflite, shared_preferences (already a dependency via `study_timer_repository.dart`), file_picker (existing).

## Global Constraints

- No AppBar on either screen — big title pattern (`Theme.of(context).textTheme.headlineLarge`) matching Home/Timer, wrapped in `SafeArea`.
- New settings ("하루 복습 목표", "앞면에 표시", "출처 문장 함께 보기") are persisted to `SharedPreferences` but **not** wired into Flashcard screen behavior — out of scope (matches the existing "모국어" precedent, which is also stored-but-unconsumed).
- The mockup's dashed drop-zone border and diagonal-stripe background are simplified to a solid light border / plain background — a dashed border requires a custom painter or new package dependency for a purely decorative element, disproportionate to what was asked.
- Every widget test that opens a repository against `inMemoryDatabasePath` MUST call `addTearDown(repo.close)` — `sqflite_common_ffi_no_isolate` caches connections by that one shared path, and every prior omission on this branch has caused cross-test DB-state leakage. The existing `settings_screen_test.dart` is missing this on both its current tests — fix it while touching that file.
- Design tokens: `AppColors`/`AppFonts` from `mobile/lib/theme/app_theme.dart` — no new hex literals for colors that already have a token.

---

### Task 1: Data layer — duplicate-skip counting + last-import persistence

**Files:**
- Create: `mobile/lib/data/models/last_import_summary.dart`
- Modify: `mobile/lib/data/repository.dart`
- Test: `mobile/test/data/repository_test.dart`

**Interfaces:**
- Produces: `LastImportSummary` (fields: `importedAt` (DateTime), `newWords`, `newSentences`, `skippedWords`, `skippedSentences` (all int); `toJson()`/`fromJson()`). `MergeResult` gains `skippedWords`/`skippedSentences` (both required int). `LearningRepository.getLastImportSummary() -> Future<LastImportSummary?>`. `LocalSQLiteRepository`'s constructor gains an optional `Future<SharedPreferences> Function()? getPrefs` parameter (defaults to `SharedPreferences.getInstance`), matching `LocalStudyTimerRepository`'s existing `_getPrefs` pattern in `study_timer_repository.dart`.
- Consumes: nothing from other tasks (this is the foundation task).

- [ ] **Step 1: Write the failing tests**

Create `mobile/lib/data/models/last_import_summary.dart` is not written yet — write tests first against the planned API. Extend the existing `mergeFromFile` test in `mobile/test/data/repository_test.dart` (the one titled `'merges new rows and ignores duplicate ids, counts correctly'`) to also assert the new skip counts, and add a new test group for `getLastImportSummary`.

First, add the `shared_preferences` import and a `setUp` mock at the top of `mobile/test/data/repository_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/review_schedule.dart';
```

In `main()`, add a `setUp` alongside the existing `setUpAll` (there is currently no top-level `setUp` in this file — add one):

```dart
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
```

Then find this existing assertion block inside the `'merges new rows and ignores duplicate ids, counts correctly'` test:

```dart
      final result = await repo.mergeFromFile(importPath);

      expect(result.newWords, 1);
      expect(result.newSentences, 1);
```

Replace it with:

```dart
      final result = await repo.mergeFromFile(importPath);

      expect(result.newWords, 1);
      expect(result.newSentences, 1);
      expect(result.skippedWords, 1); // w1 was a duplicate
      expect(result.skippedSentences, 0);
```

Add a new test group at the end of `main()`, just before the final closing `}` of `main()` (after the `mergeFromFile` group's closing `});`):

```dart
  group('getLastImportSummary', () {
    test('returns null before any import has happened', () async {
      final summary = await repo.getLastImportSummary();
      expect(summary, isNull);
    });

    test('returns the most recent import summary after a successful merge', () async {
      final tempDir = await Directory.systemTemp.createTemp('eh_last_import_test');
      addTearDown(() => tempDir.delete(recursive: true));

      // NOTE (corrected after implementation): openAppDatabase() creates
      // the app's own *current* schema (a superset with review_level/
      // last_reviewed_at columns), which hasValidSchema() rejects as
      // "extra columns" — a valid backup file needs the narrower
      // Chrome-extension export shape instead, built the same way the
      // existing "merges new rows..." test above this group does (raw
      // CREATE TABLE via databaseFactory.openDatabase, then strip
      // review_level/last_reviewed_at from the row maps before insert).
      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await databaseFactory.openDatabase(
        importPath,
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
      final w1Map = _word('w1').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      final s1Map = _sentence('s1').toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      await importDb.insert('words', w1Map);
      await importDb.insert('sentences', s1Map);
      await importDb.close();

      await repo.mergeFromFile(importPath);
      final summary = await repo.getLastImportSummary();

      expect(summary, isNotNull);
      expect(summary!.newWords, 1);
      expect(summary.newSentences, 1);
      expect(summary.skippedWords, 0);
      expect(summary.skippedSentences, 0);
      expect(summary.importedAt.difference(DateTime.now()).abs() < const Duration(seconds: 5), isTrue);
    });

    test('a failed import (invalid backup file) does not update the summary', () async {
      final tempDir = await Directory.systemTemp.createTemp('eh_last_import_fail_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final badPath = '${tempDir.path}/bad.sqlite';
      final badDb = await databaseFactory.openDatabase(badPath);
      await badDb.execute('CREATE TABLE not_words (id TEXT)');
      await badDb.close();

      await expectLater(
        () => repo.mergeFromFile(badPath),
        throwsA(isA<InvalidBackupFileException>()),
      );

      final summary = await repo.getLastImportSummary();
      expect(summary, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/data/repository_test.dart`
Expected: FAIL — `skippedWords`/`skippedSentences` don't exist on `MergeResult`, `getLastImportSummary` doesn't exist on `LearningRepository`.

- [ ] **Step 3: Create the `LastImportSummary` model**

Create `mobile/lib/data/models/last_import_summary.dart`:

```dart
class LastImportSummary {
  final DateTime importedAt;
  final int newWords;
  final int newSentences;
  final int skippedWords;
  final int skippedSentences;

  const LastImportSummary({
    required this.importedAt,
    required this.newWords,
    required this.newSentences,
    required this.skippedWords,
    required this.skippedSentences,
  });

  Map<String, Object?> toJson() => {
        'importedAt': importedAt.toIso8601String(),
        'newWords': newWords,
        'newSentences': newSentences,
        'skippedWords': skippedWords,
        'skippedSentences': skippedSentences,
      };

  factory LastImportSummary.fromJson(Map<String, Object?> json) => LastImportSummary(
        importedAt: DateTime.parse(json['importedAt'] as String),
        newWords: json['newWords'] as int,
        newSentences: json['newSentences'] as int,
        skippedWords: json['skippedWords'] as int,
        skippedSentences: json['skippedSentences'] as int,
      );
}
```

- [ ] **Step 4: Extend `MergeResult`, `LearningRepository`, and `LocalSQLiteRepository`**

In `mobile/lib/data/repository.dart`, update the imports at the top of the file:

```dart
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
```

Replace the `MergeResult` class:

```dart
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
```

Add one line to the `LearningRepository` abstract class, right after `Future<String> getDatabasePath();`:

```dart
  Future<String> getDatabasePath();
  Future<LastImportSummary?> getLastImportSummary();
  Future<void> close();
```

Update `LocalSQLiteRepository`'s fields and constructor:

```dart
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
```

Replace the `mergeFromFile` method body (keep the signature and the schema-validation block at the top unchanged):

```dart
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd mobile && flutter test test/data/repository_test.dart`
Expected: PASS (all tests, including the 3 new ones and the extended assertion).

- [ ] **Step 6: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes (some pre-existing tests that construct `LocalSQLiteRepository()` directly are unaffected since `getPrefs` is optional).

- [ ] **Step 7: Commit**

```bash
cd mobile
git add lib/data/models/last_import_summary.dart lib/data/repository.dart test/data/repository_test.dart
git commit -m "feat: track skipped-duplicate counts and persist last-import summary"
```

---

### Task 2: Import screen rebuild

**Files:**
- Modify: `mobile/lib/features/import/import_screen.dart`
- Test: `mobile/test/features/import/import_screen_test.dart` (new)

**Interfaces:**
- Consumes: `LearningRepository.mergeFromFile`, `.getLastImportSummary()` (Task 1). `LastImportSummary` fields (Task 1). `AppColors`/`AppFonts` from `mobile/lib/theme/app_theme.dart`.
- Produces: nothing consumed by later tasks — Import and Settings are independent screens.

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/import/import_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/import/import_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: ImportScreen()),
    );
  }

  testWidgets('shows the title, subtitle, and 파일 선택 button', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text('가져오기'), findsOneWidget);
    expect(find.text('파일 선택'), findsOneWidget);
  });

  testWidgets('hides the LAST IMPORT card when nothing has ever been imported', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text('LAST IMPORT'), findsNothing);
  });

  testWidgets('shows the LAST IMPORT card with correct counts after a real import', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    late Directory tempDir;
    // NOTE (corrected after implementation): real file-system/native-FFI
    // I/O (temp dir creation, sqlite file open/insert/close) doesn't
    // resolve reliably inside testWidgets' fake-async zone and hangs
    // indefinitely — wrap it in tester.runAsync(), the standard escape
    // hatch for real async work inside widget tests. Also, openAppDatabase()
    // creates the app's own *current* schema (a superset with
    // review_level/last_reviewed_at columns), which hasValidSchema()
    // rejects as "extra columns" — build the narrower backup-schema
    // fixture instead, the same pattern used in repository_test.dart.
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('eh_import_screen_test');
      final importPath = '${tempDir.path}/import.sqlite';
      final importDb = await databaseFactory.openDatabase(
        importPath,
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
      final w1Map = const Word(
        id: 'w1',
        word: 'ephemeral',
        platform: 'youtube',
        contentTitle: 't',
        contentId: 'c',
        timestamp: 0,
        savedAt: '2026-08-11T21:24:00.000Z',
      ).toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at');
      await importDb.insert('words', w1Map);
      await importDb.close();

      // Drive the same code path the screen's "파일 선택" button would after
      // FilePicker returns a path — FilePicker itself can't be driven from a
      // widget test, so this exercises mergeFromFile + the screen's reload
      // directly through the repository, then re-pumps to see the result.
      await repo.mergeFromFile(importPath);
    });
    addTearDown(() => tempDir.delete(recursive: true));

    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text('LAST IMPORT'), findsOneWidget);
    expect(find.text('+1개'), findsOneWidget);
    expect(find.textContaining('단어 1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/import/import_screen_test.dart`
Expected: FAIL — current `ImportScreen` has no title text matching, no LAST IMPORT card.

- [ ] **Step 3: Rewrite the Import screen**

Replace the full contents of `mobile/lib/features/import/import_screen.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/last_import_summary.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  LastImportSummary? _lastImport;

  @override
  void initState() {
    super.initState();
    _loadLastImport();
  }

  Future<void> _loadLastImport() async {
    final repo = context.read<LearningRepository>();
    final summary = await repo.getLastImportSummary();
    if (!mounted) return;
    setState(() => _lastImport = summary);
  }

  Future<void> _pickAndImport(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    if (result == null || result.files.single.path == null) return;

    if (!context.mounted) return;
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
      await _loadLastImport();
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

  static String _dateTimeLabel(DateTime dt) {
    final period = dt.hour < 12 ? '오전' : '오후';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${dt.month}월 ${dt.day}일 $period $hour12:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lastImport = _lastImport;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('가져오기', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              const Text(
                '확장 프로그램 팝업에서 내보낸 .sqlite 파일을 선택하면 기존 데이터와 합칩니다. 같은 항목은 건너뜁니다.',
                style: TextStyle(fontSize: 13, height: 1.65, color: AppColors.inkTertiary),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _pickAndImport(context),
                child: Container(
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD4DAE5)),
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.surface,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD4DAE5)),
                          color: AppColors.surface,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.file_upload_outlined, size: 20, color: AppColors.inkSecondary),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'english_helper.sqlite',
                        style: TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _pickAndImport(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '파일 선택',
                    style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
              if (lastImport != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LAST IMPORT',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: AppColors.inkQuaternary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_dateTimeLabel(lastImport.importedAt), style: const TextStyle(fontSize: 13.5)),
                          Text(
                            '+${lastImport.newWords + lastImport.newSentences}개',
                            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12, color: AppColors.accentInk),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '단어 ${lastImport.newWords} · 문장 ${lastImport.newSentences} 추가, '
                        '중복 ${lastImport.skippedWords + lastImport.skippedSentences}건 건너뜀',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/import/import_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/import/import_screen.dart test/features/import/import_screen_test.dart
git commit -m "feat: redesign Import screen per mockup §1f (drop zone, LAST IMPORT card)"
```

---

### Task 3: Expose the weekly-goal sheet for reuse in Settings

**Files:**
- Modify: `mobile/lib/features/timer/weekly_goal_card.dart`
- Test: `mobile/test/features/timer/weekly_goal_card_test.dart` (no behavior change — verify existing tests still pass)

**Interfaces:**
- Produces: `GoalSheet` (renamed from `_GoalSheet`, now public) — `const GoalSheet({required int initialHours, required int currentTotalSeconds})`, returns `int?` (hours) via `Navigator.pop` exactly as before. Task 4 imports this from `mobile/lib/features/timer/weekly_goal_card.dart`.
- Consumes: nothing new — this is a pure rename, no behavior change.

This task is a mechanical rename only: `_GoalSheet` → `GoalSheet` everywhere it's referenced in this one file. No new functionality.

- [ ] **Step 1: Rename the class**

In `mobile/lib/features/timer/weekly_goal_card.dart`, find and replace exactly these occurrences (there are 3: the class declaration, its `createState` return type reference, and the one construction site in `_openGoalSheet`):

```dart
class _GoalSheet extends StatefulWidget {
```
→
```dart
class GoalSheet extends StatefulWidget {
```

```dart
class _GoalSheet extends StatefulWidget {
  final int initialHours;
  final int currentTotalSeconds;
  const _GoalSheet({required this.initialHours, required this.currentTotalSeconds});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}
```
→
```dart
class GoalSheet extends StatefulWidget {
  final int initialHours;
  final int currentTotalSeconds;
  const GoalSheet({super.key, required this.initialHours, required this.currentTotalSeconds});

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}
```

```dart
class _GoalSheetState extends State<_GoalSheet> {
```
→
```dart
class _GoalSheetState extends State<GoalSheet> {
```

And the one construction site inside `_openGoalSheet`:

```dart
      builder: (_) => _GoalSheet(
        initialHours: currentGoalHours,
        currentTotalSeconds: currentTotalSeconds,
      ),
```
→
```dart
      builder: (_) => GoalSheet(
        initialHours: currentGoalHours,
        currentTotalSeconds: currentTotalSeconds,
      ),
```

- [ ] **Step 2: Run tests to verify nothing broke**

Run: `cd mobile && flutter test test/features/timer/weekly_goal_card_test.dart`
Expected: PASS (all 8 existing tests — this was a pure rename, behavior is identical).

- [ ] **Step 3: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 4: Commit**

```bash
cd mobile
git add lib/features/timer/weekly_goal_card.dart
git commit -m "refactor: make GoalSheet public for reuse in the Settings screen"
```

---

### Task 4: Settings screen rebuild

**Files:**
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Test: `mobile/test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `GoalSheet` (Task 3, from `mobile/lib/features/timer/weekly_goal_card.dart`). `StudyTimerRepository.getWeeklyGoalMinutes`/`.setWeeklyGoal` (existing, from `mobile/lib/data/study_timer_repository.dart`). `LearningRepository.getWords`/`.getSentences`/`.getDatabasePath` (existing). `AppColors`/`AppFonts` (existing).
- Produces: nothing consumed by other tasks — this is the last task.

- [ ] **Step 1: Write the failing tests**

Replace the full contents of `mobile/test/features/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/settings/settings_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen(LearningRepository repo, StudyTimerRepository timerRepo) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>.value(value: repo),
        ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets('defaults to Korean and persists a new selection via the choice sheet', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);

    await tester.tap(find.text('모국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('native_lang'), 'ja');
    expect(find.text('日本語'), findsOneWidget);
  });

  testWidgets('shows the DB path from the repository', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text(inMemoryDatabasePath), findsOneWidget);
  });

  testWidgets('shows the saved item count from the repository', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalSQLiteRepository(openDb: () async => db);
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    await repo.saveWord(const Word(
      id: 'w1', word: 'x', platform: 'youtube', contentTitle: 't', contentId: 'c', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
    ));
    await repo.saveSentence(const Sentence(
      id: 's1', original: 'x', platform: 'youtube', contentTitle: 't', contentId: 'c', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('editing 하루 복습 목표 via the stepper persists the new value', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('20개'), findsOneWidget); // default

    await tester.tap(find.text('하루 복습 목표'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('21개'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('daily_review_goal'), 21);
  });

  testWidgets('앞면에 표시 opens a choice sheet and persists the selection', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('영어'), findsOneWidget); // default

    await tester.tap(find.text('앞면에 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한글'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('flashcard_front'), 'ko');
  });

  testWidgets('출처 문장 함께 보기 toggles and persists immediately', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_source_sentence'), false); // default true, toggled off
  });

  testWidgets('주간 학습 목표 row opens the shared GoalSheet and saving updates StudyTimerRepository', (tester) async {
    final repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);
    await timerRepo.setWeeklyGoal(300); // 5 hours

    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('5시간'), findsOneWidget);

    await tester.tap(find.text('주간 학습 목표'));
    await tester.pumpAndSettle();
    expect(find.text('주간 학습 목표'), findsWidgets); // sheet title + row label both present

    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await timerRepo.getWeeklyGoalMinutes(mondayOf(DateTime.now())), 360);
    expect(find.text('6시간'), findsOneWidget);
  });
}
```

This test file needs `Word`/`Sentence` model imports too — add these to the top import block:

```dart
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — current `SettingsScreen` has none of this structure.

- [ ] **Step 3: Rewrite the Settings screen**

Replace the full contents of `mobile/lib/features/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';
import '../../data/study_timer_repository.dart';
import '../../theme/app_theme.dart';
import '../timer/weekly_goal_card.dart';

const Map<String, String> kNativeLanguages = {
  'ko': '한국어',
  'ja': '日本語',
  'zh': '中文',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
};

const Map<String, String> kFlashcardFrontOptions = {
  'en': '영어',
  'ko': '한글',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _nativeLang = 'ko';
  int _dailyReviewGoal = 20;
  String _flashcardFront = 'en';
  bool _showSourceSentence = true;
  String? _dbPath;
  int? _savedItemCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<LearningRepository>();
    final prefs = await SharedPreferences.getInstance();
    final dbPath = await repo.getDatabasePath();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    if (!mounted) return;
    setState(() {
      _nativeLang = prefs.getString('native_lang') ?? 'ko';
      _dailyReviewGoal = prefs.getInt('daily_review_goal') ?? 20;
      _flashcardFront = prefs.getString('flashcard_front') ?? 'en';
      _showSourceSentence = prefs.getBool('show_source_sentence') ?? true;
      _dbPath = dbPath;
      _savedItemCount = words.length + sentences.length;
    });
  }

  Future<void> _setNativeLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('native_lang', lang);
    if (!mounted) return;
    setState(() => _nativeLang = lang);
  }

  Future<void> _setFlashcardFront(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flashcard_front', value);
    if (!mounted) return;
    setState(() => _flashcardFront = value);
  }

  Future<void> _setShowSourceSentence(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_source_sentence', value);
    if (!mounted) return;
    setState(() => _showSourceSentence = value);
  }

  Future<void> _editDailyReviewGoal(BuildContext context) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyGoalSheet(initialValue: _dailyReviewGoal),
    );
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_review_goal', result);
    if (!mounted) return;
    setState(() => _dailyReviewGoal = result);
  }

  Future<void> _editNativeLang(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: '모국어',
        options: kNativeLanguages,
        selected: _nativeLang,
      ),
    );
    if (result != null) await _setNativeLang(result);
  }

  Future<void> _editFlashcardFront(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: '앞면에 표시',
        options: kFlashcardFrontOptions,
        selected: _flashcardFront,
      ),
    );
    if (result != null) await _setFlashcardFront(result);
  }

  Future<void> _editWeeklyGoal(BuildContext context, StudyTimerRepository timerRepo) async {
    final weekStart = mondayOf(DateTime.now());
    final goalMinutes = await timerRepo.getWeeklyGoalMinutes(weekStart);
    final sessions = await timerRepo.getSessionsBetween(weekStart, weekStart.add(const Duration(days: 7)));
    final totalSeconds = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    if (!context.mounted) return;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalSheet(
        initialHours: (goalMinutes ?? 300) ~/ 60,
        currentTotalSeconds: totalSeconds,
      ),
    );
    if (result != null) {
      await timerRepo.setWeeklyGoal(result * 60);
      if (mounted) setState(() {}); // refresh the displayed "{H}시간" row
    }
  }

  @override
  Widget build(BuildContext context) {
    final timerRepo = context.watch<StudyTimerRepository>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('설정', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 20),
            _SectionLabel('학습'),
            _SettingsCard(
              children: [
                _ChevronRow(
                  label: '모국어',
                  value: kNativeLanguages[_nativeLang] ?? _nativeLang,
                  onTap: () => _editNativeLang(context),
                ),
                _ChevronRow(
                  label: '하루 복습 목표',
                  value: '$_dailyReviewGoal개',
                  onTap: () => _editDailyReviewGoal(context),
                ),
                _ChevronRow(
                  label: '주간 학습 목표',
                  value: FutureBuilder<int?>(
                    future: timerRepo.getWeeklyGoalMinutes(mondayOf(DateTime.now())),
                    builder: (context, snapshot) {
                      final minutes = snapshot.data ?? 300;
                      return Text('${minutes ~/ 60}시간', style: const TextStyle(fontSize: 14, color: AppColors.inkTertiary));
                    },
                  ),
                  onTap: () => _editWeeklyGoal(context, timerRepo),
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('플래시카드'),
            _SettingsCard(
              children: [
                _ChevronRow(
                  label: '앞면에 표시',
                  value: kFlashcardFrontOptions[_flashcardFront] ?? _flashcardFront,
                  onTap: () => _editFlashcardFront(context),
                ),
                _SwitchRow(
                  label: '출처 문장 함께 보기',
                  value: _showSourceSentence,
                  onChanged: _setShowSourceSentence,
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('데이터'),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DB 파일 경로', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 5),
                      Text(
                        _dbPath ?? '불러오는 중...',
                        style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: const Color(0xFFF1F3F8)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      const Expanded(child: Text('저장된 항목', style: TextStyle(fontSize: 14))),
                      Text(
                        '${_savedItemCount ?? 0}',
                        style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13, color: AppColors.inkTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'English Helper 0.4.0 · Phase B',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: AppColors.inkQuaternary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ChevronRow extends StatelessWidget {
  final String label;
  final Object value; // String or a Widget (e.g. FutureBuilder)
  final VoidCallback onTap;
  final bool isLast;
  const _ChevronRow({required this.label, required this.value, required this.onTap, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final valueWidget = value is Widget
        ? value as Widget
        : Text('$value', style: const TextStyle(fontSize: 14, color: AppColors.inkTertiary));
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: isLast
            ? null
            : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            valueWidget,
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;
  const _SwitchRow({required this.label, required this.value, required this.onChanged, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: isLast
          ? null
          : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.accent),
        ],
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  final String title;
  final Map<String, String> options;
  final String selected;
  const _ChoiceSheet({required this.title, required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFDCE1EA), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 20)),
          const SizedBox(height: 14),
          for (final entry in options.entries)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 15))),
                    if (entry.key == selected) const Icon(Icons.check, size: 18, color: AppColors.accentInk),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyGoalSheet extends StatefulWidget {
  final int initialValue;
  const _DailyGoalSheet({required this.initialValue});

  @override
  State<_DailyGoalSheet> createState() => _DailyGoalSheetState();
}

class _DailyGoalSheetState extends State<_DailyGoalSheet> {
  late int _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  void _adjust(int delta) => setState(() => _draft = (_draft + delta).clamp(1, 999));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFDCE1EA), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('하루 복습 목표', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 20)),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _adjust(-1),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE1EA)), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('−', style: TextStyle(fontSize: 22, color: AppColors.inkSecondary)),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text('$_draft개', textAlign: TextAlign.center, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () => _adjust(1),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE1EA)), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('+', style: TextStyle(fontSize: 22, color: AppColors.inkSecondary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.ink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('저장', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
git commit -m "feat: redesign Settings screen per mockup §1f (3 sections, shared GoalSheet)"
```

---

## Self-Review Notes

- **Spec coverage:** §3 (Import layout/behavior) → Task 2. §4 (MergeResult/LastImportSummary data layer) → Task 1. §5.1 학습 (모국어/하루 복습 목표/주간 학습 목표 incl. GoalSheet reuse) → Tasks 3+4. §5.2 플래시카드 (앞면에 표시/출처 문장) → Task 4. §5.3 데이터 (DB 경로/저장된 항목/버전 footer) → Task 4. §6 에러 처리 (LAST IMPORT hidden when null, stepper clamped, safe defaults before load) → Tasks 2/4. §7 테스트 → covered per-task. §8 범위 밖 → confirmed no task wires new settings into Flashcard screen behavior.
- **Placeholder scan:** none found — every step has literal code.
- **Type consistency:** `LastImportSummary` fields (`importedAt`, `newWords`, `newSentences`, `skippedWords`, `skippedSentences`) match between Task 1's definition and Task 2's usage. `MergeResult`'s 4 fields match between Task 1 and Task 2's snackbar text (`merged.newWords`/`merged.newSentences`, unchanged from before). `GoalSheet(initialHours:, currentTotalSeconds:)` constructor matches between Task 3's rename and Task 4's `_editWeeklyGoal` call site exactly.
- **Cross-task file ownership:** Task 1 touches `repository.dart` + a new model file — no overlap with Tasks 2-4. Task 2 owns `import_screen.dart` only. Task 3 touches `weekly_goal_card.dart` (rename only) — must run before Task 4, which imports `GoalSheet` from it. Task 4 owns `settings_screen.dart` only. Dispatch order: 1 → 2 → 3 → 4 (2 depends on 1; 4 depends on 3; 2 and 3 could in principle run in either order relative to each other, but this plan dispatches them in file-listed order for a simpler ledger).
- **DB-isolation discipline:** every test in Tasks 1, 2, and 4 that opens `inMemoryDatabasePath` calls `addTearDown(repo.close)` (and `addTearDown(timerRepo.close)` where a `StudyTimerRepository` is also constructed) — including fixing the two pre-existing `settings_screen_test.dart` tests that were missing it.
