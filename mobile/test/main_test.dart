// mobile/test/main_test.dart
//
// IMPORTANT: app.dart's IndexedStack builds all 5 screens up front,
// including TimerScreen — so its Timer.periodic is running from the very
// first pumpWidget() call in this test, before any tab is even tapped.
// `pumpAndSettle()` pumps until no frame is scheduled, and a periodic
// timer that fires forever can make that loop until it hits its internal
// cap and throws "pumpAndSettle timed out". This file uses a bounded
// settleOnce() helper everywhere instead — never pumpAndSettle().
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/data/sync/auth_service.dart';
import 'package:english_helper_app/data/sync/sync_service.dart';
import 'package:english_helper_app/app.dart';

// AuthGate가 인증 스트림을 보므로, EnglishHelperApp을 직접 띄우는 테스트는
// 이미 로그인된 상태를 흉내 낸 가짜 AuthService가 필요하다.
class _FakeAuthService implements AuthService {
  @override
  final AuthUser? currentUser = const AuthUser(uid: 'test-uid', email: 'test@example.com');

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signUp(String email, String password) async {}

  @override
  Future<void> signOut() async {}
}

// 같은 사용자가 스트림에서 두 번 흘러도(재빌드) 계정 전환 검사는 한 번만
// 돌아야 한다 — onSignedIn은 syncNow까지 부르는 무거운 경로다.
class _StreamAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  @override
  AuthUser? currentUser = const AuthUser(uid: 'test-uid', email: 'test@example.com');

  void emit(AuthUser? user) {
    currentUser = user;
    _controller.add(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> signOut() async {}
}

// SettingsScreen이 SyncService를 watch하므로 프로바이더가 필요하다.
// 이 테스트는 동기화를 검증하지 않으니 아무것도 하지 않는 원격 저장소를 쓴다.
class _NullRemoteStore implements RemoteStore {
  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async => [];
  @override
  Future<void> write(String uid, String c, String id, Map<String, Object?> d) async {}
  @override
  Future<void> delete(String uid, String c, String id) async {}
}

// 셸이 동기화를 부르는지만 보면 되므로, 네트워크를 타는 본체 대신
// 호출만 세는 대역을 쓴다.
class _RecordingSyncService extends SyncService {
  final List<String> syncNowUids = [];
  final List<String> signedInUids = [];

  _RecordingSyncService({
    required super.repository,
    required super.timerRepository,
  }) : super(remote: _NullRemoteStore());

  @override
  Future<SyncResult> syncNow(String uid) async {
    syncNowUids.add(uid);
    return const SyncResult(ok: true, pending: 0);
  }

  @override
  Future<void> onSignedIn(String uid) async {
    signedInUids.add(uid);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> settleOnce(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<_RecordingSyncService> pumpApp(WidgetTester tester) async {
    final learningRepo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final timerRepo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final sync = _RecordingSyncService(
      repository: learningRepo,
      timerRepository: timerRepo,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
          ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
          Provider<AuthService>.value(value: _FakeAuthService()),
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        child: const EnglishHelperApp(),
      ),
    );
    await settleOnce(tester);
    return sync;
  }

  testWidgets('bottom navigation switches between all 5 screens', (tester) async {
    final learningRepo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final timerRepo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
          ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
          Provider<AuthService>.value(value: _FakeAuthService()),
          ChangeNotifierProvider<SyncService>.value(
            value: SyncService(
              repository: learningRepo,
              timerRepository: timerRepo,
              remote: _NullRemoteStore(),
            ),
          ),
        ],
        child: const EnglishHelperApp(),
      ),
    );
    await settleOnce(tester);

    expect(find.text('저장한 표현'), findsOneWidget);

    await tester.tap(find.text('플래시카드'));
    await settleOnce(tester);
    expect(find.text('플래시카드'), findsWidgets);

    await tester.tap(find.text('가져오기'));
    await settleOnce(tester);
    expect(find.text('파일 선택'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await settleOnce(tester);
    expect(find.text('모국어'), findsOneWidget);

    await tester.tap(find.text('타이머'));
    await settleOnce(tester);
    expect(find.text('시작'), findsOneWidget);
  });

  testWidgets('앱을 열면 로그인한 계정으로 동기화한다', (tester) async {
    final sync = await pumpApp(tester);
    expect(sync.syncNowUids, ['test-uid']);
  });

  testWidgets('포그라운드로 돌아오면 다시 동기화한다', (tester) async {
    final sync = await pumpApp(tester);
    sync.syncNowUids.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleOnce(tester);

    expect(sync.syncNowUids, ['test-uid']);
  });

  testWidgets('로그인 상태로 들어오면 계정 전환 검사를 태운다', (tester) async {
    final sync = await pumpApp(tester);
    expect(sync.signedInUids, ['test-uid']);
  });

  testWidgets('같은 계정이 다시 흘러도 계정 전환 검사는 한 번만 돈다', (tester) async {
    final learningRepo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final timerRepo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    final sync = _RecordingSyncService(
      repository: learningRepo,
      timerRepository: timerRepo,
    );
    final auth = _StreamAuthService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
          ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        child: const EnglishHelperApp(),
      ),
    );
    auth.emit(auth.currentUser);
    await settleOnce(tester);
    auth.emit(auth.currentUser);
    await settleOnce(tester);

    expect(sync.signedInUids, ['test-uid']);
  });
}
