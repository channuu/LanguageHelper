import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sentence.dart';
import '../models/study_session.dart';
import '../models/weekly_goal.dart';
import '../models/word.dart';
import '../repository.dart';
import '../study_timer_repository.dart';
import 'merge.dart';

/// Firestore 접근을 인터페이스 뒤에 둔다 — cloud_firestore는 위젯 테스트에서
/// 초기화할 수 없어 인메모리 대역으로 갈아끼워야 한다.
abstract class RemoteStore {
  Future<List<Map<String, Object?>>> list(String uid, String collection);
  Future<void> write(
      String uid, String collection, String docId, Map<String, Object?> data);
  Future<void> delete(String uid, String collection, String docId);
}

class FirestoreRemoteStore implements RemoteStore {
  final FirebaseFirestore _db;
  FirestoreRemoteStore({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid, String collection) =>
      _db.collection('users').doc(uid).collection(collection);

  /// 컬렉션 전체를 한 번에 받는다 — 페이지네이션 없음. 확장은 최근 500개로
  /// 자르지만(cloud/sync.js) 앱은 로컬이 원본이라 자를 수 없다. sync 한 번의
  /// 비용이 저장 항목 수에 비례해 늘어난다는 뜻이고, 수천 개 규모가 되면
  /// updated_at 기준 증분 pull(마지막 동기화 이후만)이 필요해진다.
  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async {
    final snap = await _col(uid, collection).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  @override
  Future<void> write(String uid, String collection, String docId,
          Map<String, Object?> data) =>
      _col(uid, collection).doc(docId).set(data);

  @override
  Future<void> delete(String uid, String collection, String docId) =>
      _col(uid, collection).doc(docId).delete();
}

class SyncResult {
  final bool ok;
  final int pending;
  const SyncResult({required this.ok, required this.pending});
}

class SyncService extends ChangeNotifier {
  static const _lastSyncKey = 'sync_last_at';
  static const _lastUidKey = 'sync_last_uid';

  final LearningRepository repository;
  final StudyTimerRepository timerRepository;
  final RemoteStore remote;

  String? _lastSyncAt;
  int _pending = 0;
  Future<SyncResult>? _inFlight;

  SyncService({
    required this.repository,
    required this.timerRepository,
    required this.remote,
  });

  String? get lastSyncAt => _lastSyncAt;
  int get pending => _pending;

  /// 서버에 올릴 형태 — synced_at은 기기별 사실이라 서버에 두지 않는다.
  /// 두 기기가 매번 서로의 값을 덮어쓰게 된다.
  Map<String, Object?> _forRemote(Map<String, Object?> map) {
    final copy = Map<String, Object?>.from(map);
    copy.remove('synced_at');
    return copy;
  }

  SyncRecord _recordOf(Map<String, Object?> map) => SyncRecord(
        id: map['id'] as String,
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ??
            '',
        syncedAt: map['synced_at'] as String?,
        data: map,
      );

  Future<int> _countPending() async {
    final words = await repository.getWords();
    final sentences = await repository.getSentences();
    final sessions = await timerRepository.getAllSessions();
    final goals = await timerRepository.getAllGoals();
    final queue = await repository.getSyncQueue();
    return words.where((w) => w.syncedAt == null).length +
        sentences.where((s) => s.syncedAt == null).length +
        sessions.where((s) => s.syncedAt == null).length +
        goals.where((g) => g.syncedAt == null).length +
        queue.length;
  }

  /// 로그인 직후 호출한다. 다른 계정이면 이전 계정의 로컬 캐시를 비운다
  /// — B 계정이 A 계정의 단어를 보는 사고를 막는다. 저장된 uid가 없는
  /// 최초 로그인은 지우지 않는다 — 그러면 기존 사용자의 첫 로그인에서
  /// 라이브러리를 날려버리게 된다.
  Future<void> onSignedIn(String uid) async {
    await _ensureOwner(uid);
    await syncNow(uid);
  }

  /// 로컬 데이터의 주인이 지금 로그인한 계정인지 확인하고, 아니면 비운다.
  ///
  /// sync 경로 안에서도 부른다. onSignedIn 한 곳에만 두면 그 호출이
  /// 유실될 때(로그인 직후 위젯이 사라지는 등) 이전 계정의 행이 로컬에
  /// 남고, 다음 syncNow가 그것을 새 계정의 서버로 올려버린다 — 확장에서
  /// 실제로 그렇게 샜다.
  ///
  /// 저장된 uid가 없으면 지우지 않는다. 기존 사용자의 첫 로그인이라
  /// 여기서 지우면 라이브러리를 통째로 날린다.
  Future<void> _ensureOwner(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString(_lastUidKey);
    if (lastUid != null && lastUid != uid) {
      await repository.clearAllLocalData();
      await timerRepository.clearAllLocalData();
      await prefs.remove(_lastSyncKey);
      _lastSyncAt = null;
    }
    await prefs.setString(_lastUidKey, uid);
  }

  /// 앱 진입에서 AuthGate와 루트 셸이 같은 프레임에 각각 부르고, 설정의
  /// "지금 동기화"가 그 위에 겹칠 수 있다. 두 벌이 같은 행을 오가면 서로가
  /// 상대의 '왕복 중 로컬 변경'이 되어 아래 재확인 로직을 무의미하게 만든다
  /// — 진행 중인 실행이 있으면 새로 돌리지 않고 그것을 함께 기다린다.
  Future<SyncResult> syncNow(String uid) {
    final running = _inFlight;
    if (running != null) return running;
    final started = _run(uid);
    _inFlight = started;
    return started.whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    });
  }

  Future<SyncResult> _run(String uid) async {
    var ok = true;
    try {
      await _ensureOwner(uid);
      await _pushDeletes(uid);
      await _syncWords(uid);
      await _syncSentences(uid);
      await _syncSessions(uid);
      await _syncGoals(uid);

      final prefs = await SharedPreferences.getInstance();
      _lastSyncAt = DateTime.now().toIso8601String();
      await prefs.setString(_lastSyncKey, _lastSyncAt!);
    } catch (err) {
      // 푸시 실패는 사용자에게 알리지 않는다 — 로컬 저장은 이미 성공했다.
      // 미동기 개수로만 드러내고 다음 syncNow에서 재시도한다.
      debugPrint('[Sync] failed: $err');
      ok = false;
    }
    _pending = await _countPending();
    notifyListeners();
    return SyncResult(ok: ok, pending: _pending);
  }

  Future<void> _pushDeletes(String uid) async {
    // 삭제는 먼저 반영한다 — 나중에 pull하면 로컬에서 지운 항목이 서버에
    // 아직 있는 걸 보고 되살려버린다.
    for (final entry in await repository.getSyncQueue()) {
      try {
        await remote.delete(uid, entry.entity, entry.docId);
      } on FirebaseException catch (err) {
        // 한 항목이 영영 안 지워지더라도(규칙 변경, 깨진 docId) 네 컬렉션의
        // push/pull 전체를 영구히 막으면 안 된다. 큐에 남겨 다음에 재시도한다.
        // FirebaseException이 아닌 예외는 진짜 버그이므로 그대로 올린다.
        debugPrint('[Sync] delete failed ${entry.entity}/${entry.docId}: $err');
        continue;
      }
      await repository.clearSyncQueueEntry(entry.entity, entry.docId);
    }
  }

  /// 컬렉션 한 벌을 동기화한다. 네 컬렉션의 차이는 어디서 읽고 어떻게
  /// 쓰느냐뿐이라 한곳에 모은다 — 왕복 중 로컬 변경을 다루는 규칙이 네
  /// 군데로 흩어지면 한 군데만 고쳐진 채 남기 쉽다.
  Future<void> _syncCollection({
    required String uid,
    required String collection,
    required Future<List<Map<String, Object?>>> Function() readLocal,
    required Future<void> Function(Map<String, Object?> row) writeLocal,
    Future<void> Function(String id)? deleteLocal,
  }) async {
    final before = await readLocal();
    final remoteDocs = await remote.list(uid, collection);
    final plan = planMerge(
      local: before.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final pushedIds = <String>[];
    for (final rec in plan.toPush) {
      await remote.write(uid, collection, rec.id, _forRemote(rec.data));
      pushedIds.add(rec.id);
    }

    // 네트워크가 오가는 사이 사용자가 같은 행을 고쳤을 수 있다. 왕복 전
    // 스냅샷을 그대로 되쓰면 그 편집이 사라지고, synced_at까지 찍혀 다시
    // 올라가지도 않는다. 쓰기 직전에 현재 행을 다시 읽어, updated_at이
    // 그대로인 행에만 결정을 적용한다 — 바뀐 행은 다음 sync가 가져간다.
    final snapshot = {for (final row in before) row['id'] as String: row};
    final current = {
      for (final row in await readLocal()) row['id'] as String: row
    };
    // 삭제 대기 중인 항목은 서버 문서로 되살리지 않는다. 이번 sync의
    // _pushDeletes가 지나간 뒤에 지운 항목이 여기 남는데, 서버에는 아직
    // 그 문서가 있어 규칙 3이 "서버에만 있음"으로 읽고 다시 넣어버린다.
    // 다음 sync가 서버에서 지울 것이다.
    final queuedDeletes = {
      for (final entry in await repository.getSyncQueue())
        if (entry.entity == collection) entry.docId
    };
    final now = DateTime.now().toIso8601String();

    bool unchanged(String id) {
      final cur = current[id];
      return cur != null && cur['updated_at'] == snapshot[id]?['updated_at'];
    }

    for (final id in pushedIds) {
      if (!unchanged(id)) continue;
      await writeLocal({...current[id]!, 'synced_at': now});
    }
    for (final rec in plan.toWriteLocal) {
      if (queuedDeletes.contains(rec.id)) continue;
      if (current.containsKey(rec.id) && !unchanged(rec.id)) continue;
      // 서버에서 온 문서는 정의상 동기화된 상태다.
      await writeLocal({...rec.data, 'synced_at': now});
    }
    for (final id in plan.toDeleteLocal) {
      if (deleteLocal != null) {
        await deleteLocal(id);
        // 다른 기기의 삭제를 따라간 것이지 우리가 삭제한 게 아니다 — 되밀지 않는다.
        await repository.clearSyncQueueEntry(collection, id);
        continue;
      }
      // append-only 컬렉션(세션·목표)에는 삭제 경로가 없다. 따라서 "올린 적
      // 있는데 서버에 없다"는 것은 다른 기기의 삭제가 아니라 유실이다 —
      // 지우지 말고 다시 올린다. 그냥 두면 synced_at이 찍힌 채 로컬에만
      // 남아 다시 올라가지도 않고, 다음 계정 전환에서 조용히 사라진다.
      final row = current[id];
      if (row == null) continue;
      await remote.write(uid, collection, id, _forRemote(row));
      await writeLocal({...row, 'synced_at': now});
    }
  }

  Future<void> _syncWords(String uid) => _syncCollection(
        uid: uid,
        collection: 'words',
        readLocal: () async =>
            (await repository.getWords()).map((w) => w.toMap()).toList(),
        writeLocal: (row) => repository.saveWord(Word.fromMap(row)),
        deleteLocal: repository.deleteWord,
      );

  Future<void> _syncSentences(String uid) => _syncCollection(
        uid: uid,
        collection: 'sentences',
        readLocal: () async =>
            (await repository.getSentences()).map((s) => s.toMap()).toList(),
        writeLocal: (row) => repository.saveSentence(Sentence.fromMap(row)),
        deleteLocal: repository.deleteSentence,
      );

  // 세션과 목표는 append-only다 — 앱에 삭제 경로가 없어 toDeleteLocal을
  // 다룰 필요가 없다.
  Future<void> _syncSessions(String uid) => _syncCollection(
        uid: uid,
        collection: 'study_sessions',
        readLocal: () async =>
            (await timerRepository.getAllSessions()).map((s) => s.toMap()).toList(),
        writeLocal: (row) =>
            timerRepository.upsertSession(StudySession.fromMap(row)),
      );

  Future<void> _syncGoals(String uid) => _syncCollection(
        uid: uid,
        collection: 'weekly_goals',
        readLocal: () async =>
            (await timerRepository.getAllGoals()).map((g) => g.toMap()).toList(),
        writeLocal: (row) => timerRepository.upsertGoal(WeeklyGoal.fromMap(row)),
      );

  /// 로그아웃 전에 밀린 것을 먼저 밀어낸다. 남으면 거부한다 — 로그아웃은
  /// 로컬 캐시를 비우므로 미동기 항목이 유실된다.
  Future<SyncResult> signOut(String uid, {bool force = false}) async {
    final result = await syncNow(uid);
    if (result.pending > 0 && !force) {
      return SyncResult(ok: false, pending: result.pending);
    }
    await repository.clearAllLocalData();
    await timerRepository.clearAllLocalData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_lastUidKey);
    _lastSyncAt = null;
    _pending = 0;
    notifyListeners();
    return const SyncResult(ok: true, pending: 0);
  }
}
