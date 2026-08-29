import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/sync/merge.dart';

const t1 = '2026-08-01T00:00:00.000Z';
const t2 = '2026-08-02T00:00:00.000Z';

SyncRecord local(String id, String updated, String? synced) =>
    SyncRecord(id: id, updatedAt: updated, syncedAt: synced, data: {'id': id});

SyncRecord remote(String id, String updated) =>
    SyncRecord(id: id, updatedAt: updated, syncedAt: null, data: {'id': id});

void main() {
  test('규칙 1: 미동기 항목은 푸시하고 풀이 건드리지 않는다', () {
    final r = planMerge(local: [local('a', t1, null)], remote: []);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toDeleteLocal, isEmpty);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 1: 서버에 더 오래된 사본이 있어도 미동기가 이긴다', () {
    final r = planMerge(local: [local('a', t2, null)], remote: [remote('a', t1)]);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 2: 로컬이 더 최신이면 푸시', () {
    final r = planMerge(local: [local('a', t2, t1)], remote: [remote('a', t1)]);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 2: 서버가 더 최신이면 로컬을 덮어쓴다', () {
    final r = planMerge(local: [local('a', t1, t1)], remote: [remote('a', t2)]);
    expect(r.toWriteLocal.map((e) => e.id), ['a']);
    expect(r.toPush, isEmpty);
  });

  test('규칙 2: 동률이면 서버가 이긴다', () {
    // 기기 시계 오차로 서로를 무한히 덮어쓰는 것을 막는다.
    final r = planMerge(local: [local('a', t1, t1)], remote: [remote('a', t1)]);
    expect(r.toWriteLocal.map((e) => e.id), ['a']);
    expect(r.toPush, isEmpty);
  });

  test('규칙 3: 서버에만 있으면 로컬에 넣는다', () {
    final r = planMerge(local: [], remote: [remote('b', t1)]);
    expect(r.toWriteLocal.map((e) => e.id), ['b']);
    expect(r.toDeleteLocal, isEmpty);
  });

  test('규칙 4: 올린 적 있는데 서버에 없으면 다른 기기에서 삭제된 것이다', () {
    final r = planMerge(local: [local('c', t1, t1)], remote: []);
    expect(r.toDeleteLocal, ['c']);
    expect(r.toPush, isEmpty);
  });

  test('네 규칙이 함께 동작한다', () {
    final r = planMerge(
      local: [local('unsynced', t2, null), local('older', t1, t1), local('gone', t1, t1)],
      remote: [remote('older', t2), remote('new', t1)],
    );
    expect(r.toPush.map((e) => e.id), ['unsynced']);
    expect(r.toWriteLocal.map((e) => e.id).toList()..sort(), ['new', 'older']);
    expect(r.toDeleteLocal, ['gone']);
  });

  test('양쪽이 비어 있으면 아무것도 하지 않는다', () {
    final r = planMerge(local: [], remote: []);
    expect(r.toWriteLocal, isEmpty);
    expect(r.toDeleteLocal, isEmpty);
    expect(r.toPush, isEmpty);
  });

  test('원격 레코드를 통째로 toWriteLocal에 싣는다', () {
    final doc = SyncRecord(
      id: 'a', updatedAt: t2, syncedAt: null,
      data: {'id': 'a', 'word': 'hi', 'review_count': 3},
    );
    final r = planMerge(local: [], remote: [doc]);
    expect(r.toWriteLocal.single.data, doc.data);
  });
}
