import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/study_session.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/data/sync/sync_service.dart';

class InMemoryRemoteStore implements RemoteStore {
  final Map<String, Map<String, Map<String, Object?>>> docs = {};
  int writeCount = 0;
  int listCount = 0;
  Object? throwOnWrite;
  Object? throwOnDelete;

  /// 네트워크 왕복 '중에' 로컬에서 벌어지는 일을 재현하는 훅.
  Future<void> Function()? onList;
  Future<void> Function()? onWrite;

  String _key(String uid, String collection) => '$uid/$collection';

  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async {
    listCount++;
    if (onList != null) await onList!();
    return (docs[_key(uid, collection)] ?? {}).values.toList();
  }

  @override
  Future<void> write(String uid, String collection, String docId,
      Map<String, Object?> data) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    writeCount++;
    docs.putIfAbsent(_key(uid, collection), () => {})[docId] = data;
    if (onWrite != null) await onWrite!();
  }

  @override
  Future<void> delete(String uid, String collection, String docId) async {
    if (throwOnDelete != null) throw throwOnDelete!;
    docs[_key(uid, collection)]?.remove(docId);
  }
}

Word makeWord(String id, {required String updatedAt, String? syncedAt}) => Word(
      id: id, word: 'w-$id', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: updatedAt,
      updatedAt: updatedAt, syncedAt: syncedAt,
    );

void main() {
  const t1 = '2026-08-01T00:00:00.000Z';
  const t2 = '2026-08-02T00:00:00.000Z';

  late LocalSQLiteRepository repo;
  late LocalStudyTimerRepository timerRepo;
  late InMemoryRemoteStore remote;
  late SyncService sync;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    remote = InMemoryRemoteStore();
    sync = SyncService(repository: repo, timerRepository: timerRepo, remote: remote);
  });

  tearDown(() async {
    await repo.close();
    await timerRepo.close();
  });

  test('미동기 항목을 업로드하고 syncedAt을 채운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));

    final result = await sync.syncNow('u1');

    expect(result.ok, isTrue);
    expect(remote.docs['u1/words']!.containsKey('w1'), isTrue);
    expect((await repo.getWords()).single.syncedAt, isNotNull);
  });

  test('업로드하는 문서에 synced_at을 넣지 않는다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');

    expect(remote.docs['u1/words']!['w1']!.containsKey('synced_at'), isFalse,
        reason: 'synced_at은 기기별 사실이라 서버에 두면 서로 덮어쓴다');
    expect(remote.docs['u1/words']!['w1']!['updated_at'], t1);
  });

  test('서버에만 있는 항목을 내려받는다', () async {
    remote.docs['u1/words'] = {
      'w9': {'id': 'w9', 'word': 'remote', 'platform': 'netflix',
             'content_title': 'T', 'content_id': 'c', 'timestamp': 0.0,
             'saved_at': t1, 'review_count': 0, 'review_level': 0,
             'updated_at': t1},
    };

    await sync.syncNow('u1');

    final words = await repo.getWords();
    expect(words.map((w) => w.id), ['w9']);
    expect(words.single.syncedAt, isNotNull);
  });

  test('서버에서 사라진 동기화 항목은 로컬에서도 지운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');
    remote.docs['u1/words']!.remove('w1');

    await sync.syncNow('u1');

    expect(await repo.getWords(), isEmpty);
  });

  test('미동기 항목은 풀에서 삭제되지 않는다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t2));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.syncNow('u1');

    expect(result.ok, isFalse);
    expect((await repo.getWords()).map((w) => w.id), ['w1']);
    expect(result.pending, 1);
  });

  test('삭제 큐를 서버에 반영하고 큐를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');
    await repo.deleteWord('w1');

    await sync.syncNow('u1');

    expect(remote.docs['u1/words']!.containsKey('w1'), isFalse);
    expect(await repo.getSyncQueue(), isEmpty);
  });

  test('다른 계정으로 로그인하면 로컬 캐시를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u2');

    expect(await repo.getWords(), isEmpty,
        reason: 'B 계정이 A 계정의 단어를 보면 안 된다');
  });

  test('같은 계정으로 다시 로그인하면 캐시를 유지한다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u1');

    expect((await repo.getWords()).length, 1);
  });

  test('미동기 항목이 남으면 로그아웃을 거부한다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.signOut('u1');

    expect(result.ok, isFalse);
    expect(result.pending, 1);
    expect((await repo.getWords()).length, 1, reason: '데이터가 남아 있어야 한다');
  });

  test('force면 미동기 항목이 있어도 로그아웃하고 캐시를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.signOut('u1', force: true);

    expect(result.ok, isTrue);
    expect(await repo.getWords(), isEmpty);
  });

  test('타이머 세션을 업로드하고 syncedAt을 채운다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));

    await sync.syncNow('u1');

    expect(remote.docs['u1/study_sessions']!.containsKey('ss1'), isTrue);
    expect((await timerRepo.getAllSessions()).single.syncedAt, isNotNull);
  });

  test('서버에만 있는 주간 목표를 내려받는다', () async {
    remote.docs['u1/weekly_goals'] = {
      'g1': {'id': 'g1', 'target_minutes': 300,
             'effective_from': t1, 'created_at': t1, 'updated_at': t1},
    };

    await sync.syncNow('u1');

    expect((await timerRepo.getAllGoals()).map((g) => g.id), ['g1']);
  });

  test('타이머 문서에도 synced_at을 올리지 않는다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));

    await sync.syncNow('u1');

    expect(remote.docs['u1/study_sessions']!['ss1']!.containsKey('synced_at'),
        isFalse);
  });

  test('계정 전환 시 타이머 데이터도 비운다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u2');

    expect(await timerRepo.getAllSessions(), isEmpty);
  });

  group('왕복 중 들어온 로컬 변경', () {
    test('업로드 중 매긴 복습 점수를 스냅샷으로 되돌리지 않는다', () async {
      await repo.saveWord(makeWord('w1', updatedAt: t1));
      // 업로드가 오가는 사이 사용자가 같은 카드를 채점한다.
      remote.onWrite = () => repo.setWordReviewLevel('w1', 3);

      await sync.syncNow('u1');

      final w = (await repo.getWords()).single;
      expect(w.reviewLevel, 3, reason: '왕복 전 스냅샷이 편집을 덮어썼다');
      expect(w.syncedAt, isNull,
          reason: '서버에 없는 편집이므로 미동기로 남아 다음 sync가 올려야 한다');
    });

    test('내려받기 중 매긴 복습 점수를 서버 문서로 덮지 않는다', () async {
      await repo.saveWord(makeWord('w1', updatedAt: t1, syncedAt: t1));
      remote.docs['u1/words'] = {
        'w1': {...makeWord('w1', updatedAt: t2).toMap()..remove('synced_at')},
      };
      // words 목록을 받아오는 첫 왕복에서만 끼어든다 — 훅은 컬렉션마다
      // 불리므로 그대로 두면 마지막 컬렉션 뒤에 편집이 일어나 검증이 무의미해진다.
      var edited = false;
      remote.onList = () async {
        if (edited) return;
        edited = true;
        await repo.setWordReviewLevel('w1', 4);
      };

      await sync.syncNow('u1');

      final w = (await repo.getWords()).single;
      expect(w.reviewLevel, 4, reason: '서버 문서가 방금 매긴 점수를 덮었다');
    });
  });

  test('동시에 부른 syncNow는 한 번만 돈다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));

    final first = sync.syncNow('u1');
    final second = sync.syncNow('u1');
    await Future.wait([first, second]);

    expect(remote.listCount, 4,
        reason: '컬렉션 4개 × 1회 — 두 번 돌면 8이 된다');
  });

  test('삭제 하나가 실패해도 나머지 동기화를 계속한다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await repo.queueDelete('words', 'gone');
    remote.throwOnDelete =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

    await sync.syncNow('u1');

    expect(remote.docs['u1/words']?.containsKey('w1'), isTrue,
        reason: '삭제 하나가 4개 컬렉션 전체를 막으면 안 된다');
    expect((await repo.getSyncQueue()).single.docId, 'gone',
        reason: '실패한 항목은 큐에 남아 다음에 재시도한다');
  });

  test('삭제 대기 중인 항목은 서버 문서로 되살아나지 않는다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1, syncedAt: t1));
    remote.docs['u1/words'] = {
      'w1': {...makeWord('w1', updatedAt: t1).toMap()..remove('synced_at')},
    };
    // 삭제 큐를 밀고 지나간 뒤 사용자가 w1을 지운다. 서버에는 아직 남아
    // 있으므로 규칙 3이 "서버에만 있음"으로 읽는다.
    var deleted = false;
    remote.onList = () async {
      if (deleted) return;
      deleted = true;
      await repo.deleteWord('w1');
      await repo.queueDelete('words', 'w1');
    };

    await sync.syncNow('u1');

    expect(await repo.getWords(), isEmpty,
        reason: '방금 지운 항목이 같은 sync에서 되살아났다');
  });

  test('주간 목표를 올릴 때도 synced_at을 서버에 넣지 않는다', () async {
    await timerRepo.setWeeklyGoal(300);

    await sync.syncNow('u1');

    final goal = remote.docs['u1/weekly_goals']!.values.single;
    expect(goal.containsKey('synced_at'), isFalse,
        reason: 'synced_at은 기기별 사실이라 서버에 두면 서로 덮어쓴다');
  });

  test('로그아웃은 타이머 데이터도 지운다', () async {
    await timerRepo.startSession();
    await timerRepo.endSession();
    await timerRepo.setWeeklyGoal(300);

    final result = await sync.signOut('u1');

    expect(result.ok, isTrue);
    expect(await timerRepo.getAllSessions(), isEmpty);
    expect(await timerRepo.getAllGoals(), isEmpty);
  });

  test('아직 못 올린 학습 세션이 있으면 로그아웃을 거부한다', () async {
    await timerRepo.startSession();
    await timerRepo.endSession();
    remote.throwOnWrite =
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

    final result = await sync.signOut('u1');

    expect(result.ok, isFalse);
    expect(result.pending, greaterThan(0));
    expect(await timerRepo.getAllSessions(), hasLength(1),
        reason: '거부했으면 로컬 데이터는 그대로여야 한다');
  });

  test('다른 계정으로 sync하면 이전 계정의 로컬 데이터를 먼저 비운다', () async {
    // 계정 전환 검사가 onSignedIn 한 곳에만 있으면, 그 호출이 유실될 때
    // 앱 진입 sync가 이전 계정의 단어를 새 계정으로 올려버린다.
    SharedPreferences.setMockInitialValues({'sync_last_uid': 'someone-else'});
    await repo.saveWord(makeWord('w1', updatedAt: t1));

    await sync.syncNow('u1');

    expect(await repo.getWords(), isEmpty,
        reason: '이전 계정의 단어가 새 계정 아래 남았다');
    expect(remote.docs['u1/words'] ?? {}, isEmpty,
        reason: '이전 계정의 단어를 새 계정 서버로 올렸다');
  });

  test('처음 로그인하는 계정은 기존 로컬 데이터를 지우지 않는다', () async {
    // 기존 사용자의 첫 로그인이다 — 여기서 지우면 라이브러리가 날아간다.
    await repo.saveWord(makeWord('w1', updatedAt: t1));

    await sync.syncNow('u1');

    expect((await repo.getWords()).single.id, 'w1');
    expect(remote.docs['u1/words']!.containsKey('w1'), isTrue);
  });

  test('서버에서 사라진 학습 세션은 지우지 않고 다시 올린다', () async {
    // 세션·목표는 append-only다 — 앱에 삭제 경로가 없으므로 "서버에 없다"는
    // 것은 삭제가 아니라 유실이다. 규칙 4가 걸릴 때 그대로 두면 로컬에만
    // 남은 채 다시 올라가지 않고, 다음 계정 전환에서 조용히 사라진다.
    await timerRepo.startSession();
    await timerRepo.endSession();
    await sync.syncNow('u1');
    expect(remote.docs['u1/study_sessions'], hasLength(1));

    remote.docs['u1/study_sessions']!.clear();
    await sync.syncNow('u1');

    expect(await timerRepo.getAllSessions(), hasLength(1),
        reason: '로컬 기록을 지우면 안 된다');
    expect(remote.docs['u1/study_sessions'], hasLength(1),
        reason: '서버에 없으니 다시 올려야 한다');
  });
}
