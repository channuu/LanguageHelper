import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sentence.dart';
import '../models/word.dart';
import '../repository.dart';
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
  final RemoteStore remote;

  String? _lastSyncAt;
  int _pending = 0;

  SyncService({
    required this.repository,
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
    final queue = await repository.getSyncQueue();
    return words.where((w) => w.syncedAt == null).length +
        sentences.where((s) => s.syncedAt == null).length +
        queue.length;
  }

  /// 로그인 직후 호출한다. 다른 계정이면 이전 계정의 로컬 캐시를 비운다
  /// — B 계정이 A 계정의 단어를 보는 사고를 막는다. 저장된 uid가 없는
  /// 최초 로그인은 지우지 않는다 — 그러면 기존 사용자의 첫 로그인에서
  /// 라이브러리를 날려버리게 된다.
  Future<void> onSignedIn(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString(_lastUidKey);
    if (lastUid != null && lastUid != uid) {
      await repository.clearAllLocalData();
      await prefs.remove(_lastSyncKey);
      _lastSyncAt = null;
    }
    await prefs.setString(_lastUidKey, uid);
    await syncNow(uid);
  }

  Future<SyncResult> syncNow(String uid) async {
    var ok = true;
    try {
      await _pushDeletes(uid);
      await _syncWords(uid);
      await _syncSentences(uid);

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
      await remote.delete(uid, entry.entity, entry.docId);
      await repository.clearSyncQueueEntry(entry.entity, entry.docId);
    }
  }

  Future<void> _syncWords(String uid) async {
    final local = (await repository.getWords()).map((w) => w.toMap()).toList();
    final remoteDocs = await remote.list(uid, 'words');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'words', rec.id, _forRemote(rec.data));
      // per-row upsert by id — safe even if another word was saved
      // concurrently between the read above and this write.
      await repository.saveWord(
        Word.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final rec in plan.toWriteLocal) {
      await repository.saveWord(
        Word.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final id in plan.toDeleteLocal) {
      await repository.deleteWord(id);
      // 다른 기기의 삭제를 따라간 것이지 우리가 삭제한 게 아니다 — 되밀지 않는다.
      await repository.clearSyncQueueEntry('words', id);
    }
  }

  Future<void> _syncSentences(String uid) async {
    final local =
        (await repository.getSentences()).map((s) => s.toMap()).toList();
    final remoteDocs = await remote.list(uid, 'sentences');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'sentences', rec.id, _forRemote(rec.data));
      await repository.saveSentence(
        Sentence.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final rec in plan.toWriteLocal) {
      await repository.saveSentence(
        Sentence.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final id in plan.toDeleteLocal) {
      await repository.deleteSentence(id);
      await repository.clearSyncQueueEntry('sentences', id);
    }
  }

  /// 로그아웃 전에 밀린 것을 먼저 밀어낸다. 남으면 거부한다 — 로그아웃은
  /// 로컬 캐시를 비우므로 미동기 항목이 유실된다.
  Future<SyncResult> signOut(String uid, {bool force = false}) async {
    final result = await syncNow(uid);
    if (result.pending > 0 && !force) {
      return SyncResult(ok: false, pending: result.pending);
    }
    await repository.clearAllLocalData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_lastUidKey);
    _lastSyncAt = null;
    _pending = 0;
    notifyListeners();
    return const SyncResult(ok: true, pending: 0);
  }
}
