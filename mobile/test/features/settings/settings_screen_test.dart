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
    databaseFactory = databaseFactoryFfiNoIsolate;
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
