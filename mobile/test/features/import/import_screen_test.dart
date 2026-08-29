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
    // Real file-system/native-FFI I/O (temp dir creation, sqlite file
    // open/insert/close) doesn't resolve reliably inside testWidgets'
    // fake-async zone — tester.runAsync escapes to a real event loop for
    // it, the same technique already used elsewhere in this codebase for
    // real async work inside widget tests.
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('eh_import_screen_test');
      final importPath = '${tempDir.path}/import.sqlite';
      // openAppDatabase() creates the app's own *current* schema (a
      // superset with review_level/last_reviewed_at columns), which
      // hasValidSchema() rejects as "extra columns" — a valid backup file
      // needs the narrower Chrome-extension export shape instead, built
      // here the same way mobile/test/data/repository_test.dart does.
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
        updatedAt: '2026-08-11T21:24:00.000Z',
      ).toMap()
        ..remove('review_level')
        ..remove('last_reviewed_at')
        ..remove('updated_at')
        ..remove('synced_at');
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
