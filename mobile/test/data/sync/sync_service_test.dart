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
  Object? throwOnWrite;

  String _key(String uid, String collection) => '$uid/$collection';

  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async =>
      (docs[_key(uid, collection)] ?? {}).values.toList();

  @override
  Future<void> write(String uid, String collection, String docId,
      Map<String, Object?> data) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    writeCount++;
    docs.putIfAbsent(_key(uid, collection), () => {})[docId] = data;
  }

  @override
  Future<void> delete(String uid, String collection, String docId) async {
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
}
