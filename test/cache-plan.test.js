import { test } from 'node:test';
import assert from 'node:assert/strict';
import { staleBuckets } from '../lexicon/cache-plan.js';

test('해시가 같으면 버릴 게 없다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', gi: 'b2' },
    { version: '2026-09-02', buckets: { aw: 'a1', gi: 'b2' } }), []);
});

test('해시가 달라진 버킷만 버린다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', gi: 'b2' },
    { version: '2026-10-01', buckets: { aw: 'a1', gi: 'ZZ' } }), ['gi']);
});

test('원격에서 사라진 버킷도 버린다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', xx: 'c3' },
    { version: '2026-10-01', buckets: { aw: 'a1' } }), ['xx']);
});

test('캐시가 비어 있으면 버릴 게 없다', () => {
  assert.deepEqual(staleBuckets({}, { version: '2026-10-01', buckets: { aw: 'a1' } }), []);
});

test('원격 버전을 못 읽으면 아무것도 버리지 않는다', () => {
  // 갱신 확인 실패가 조회 실패가 되어선 안 된다 (설계 §11)
  assert.deepEqual(staleBuckets({ aw: 'a1' }, null), []);
  assert.deepEqual(staleBuckets({ aw: 'a1' }, {}), []);
});
