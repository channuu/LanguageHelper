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
    // Use the no-isolate FFI factory: the isolate-based `databaseFactoryFfi`
    // hangs inside testWidgets' FakeAsync zone.
    databaseFactory = databaseFactoryFfiNoIsolate;
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
