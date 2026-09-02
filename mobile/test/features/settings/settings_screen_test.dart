import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/sync/auth_service.dart';
import 'package:english_helper_app/data/sync/sync_service.dart';
import 'package:english_helper_app/features/settings/settings_screen.dart';

class _FakeAuthService implements AuthService {
  @override
  AuthUser? currentUser;
  _FakeAuthService(String email)
      : currentUser = AuthUser(uid: 'u1', email: email);

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

/// SyncService는 ChangeNotifier라 상속해서 동작만 갈아끼우는 편이 짧다.
class _FakeSyncService extends SyncService {
  int syncNowCalls = 0;
  final String? _lastSync;
  final int _pending;
  final bool _fails;

  _FakeSyncService({String? lastSyncAt, int pending = 0, bool fails = false})
      : _lastSync = lastSyncAt,
        _pending = pending,
        _fails = fails,
        super(
          repository: LocalSQLiteRepository(
              openDb: () => openAppDatabase(inMemoryDatabasePath)),
          timerRepository: LocalStudyTimerRepository(
              openDb: () => openAppDatabase(inMemoryDatabasePath)),
          remote: _NullRemoteStore(),
        );

  @override
  String? get lastSyncAt => _lastSync;
  @override
  int get pending => _pending;

  @override
  Future<SyncResult> syncNow(String uid) async {
    syncNowCalls++;
    return SyncResult(ok: !_fails, pending: _pending);
  }
}

class _NullRemoteStore implements RemoteStore {
  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async => [];
  @override
  Future<void> write(String uid, String c, String id, Map<String, Object?> d) async {}
  @override
  Future<void> delete(String uid, String c, String id) async {}
}

Future<_FakeSyncService> pumpSettings(
  WidgetTester tester, {
  required String email,
  String? lastSyncAt,
  int pending = 0,
  bool syncFails = false,
}) async {
  final sync = _FakeSyncService(
      lastSyncAt: lastSyncAt, pending: pending, fails: syncFails);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(
              openDb: () => openAppDatabase(inMemoryDatabasePath)),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(
              openDb: () => openAppDatabase(inMemoryDatabasePath)),
        ),
        Provider<AuthService>.value(value: _FakeAuthService(email)),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return sync;
}

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
        Provider<AuthService>.value(value: _FakeAuthService('a@b.c')),
        ChangeNotifierProvider<SyncService>.value(value: _FakeSyncService()),
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

    await tester.scrollUntilVisible(find.text(inMemoryDatabasePath), 200);
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
      updatedAt: '2026-08-01T00:00:00.000Z',
    ));
    await repo.saveSentence(const Sentence(
      id: 's1', original: 'x', platform: 'youtube', contentTitle: 't', contentId: 'c', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildScreen(repo, timerRepo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('2'), 200);
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

  testWidgets('계정 섹션에 로그인한 이메일을 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c');
    expect(find.text('a@b.c'), findsOneWidget);
  });

  testWidgets('마지막 동기화 시각이 없으면 안내를 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c', lastSyncAt: null);
    expect(find.text('아직 동기화 안 됨'), findsOneWidget);
  });

  testWidgets('미동기 항목 개수를 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c', pending: 3);
    expect(find.text('3개 대기 중'), findsOneWidget);
  });

  testWidgets('지금 동기화가 실패하면 알린다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c', syncFails: true);

    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();

    // 자동 동기화는 조용히 넘어가지만(설계 §10.2), 사용자가 직접 누른
    // 것은 결과를 알려줘야 한다.
    expect(find.text('동기화하지 못했어요. 잠시 뒤 다시 시도해 주세요.'),
        findsOneWidget);
  });

  testWidgets('지금 동기화를 누르면 syncNow를 호출한다', (tester) async {
    final sync = await pumpSettings(tester, email: 'a@b.c');
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    expect(sync.syncNowCalls, 1);
  });
}
