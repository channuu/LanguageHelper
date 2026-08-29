import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planMerge } from '../cloud/merge.js';

const T1 = '2026-08-01T00:00:00.000Z';
const T2 = '2026-08-02T00:00:00.000Z';

const local = (id, updated, synced) => ({ id, updated_at: updated, synced_at: synced });
const remote = (id, updated) => ({ id, updated_at: updated });

test('rule 1: an unsynced local item is pushed and never touched by the pull', () => {
  const r = planMerge([local('a', T1, null)], []);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toDeleteLocal, []);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 1 holds even when the server has an older copy', () => {
  // The local edit has not been uploaded yet, so it must win regardless.
  const r = planMerge([local('a', T2, null)], [remote('a', T1)]);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 1 takes precedence over rule 2: unsynced local older than remote must still push', () => {
  // Rule 1 says unsynced items must be pushed and never overwritten.
  // Rule 2 says newer timestamp wins. When they conflict, rule 1 wins.
  const r = planMerge([local('a', T1, null)], [remote('a', T2)]);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toWriteLocal, []);
  assert.deepEqual(r.toDeleteLocal, []);
});

test('rule 2: the newer updated_at wins — local newer means push', () => {
  const r = planMerge([local('a', T2, T1)], [remote('a', T1)]);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 2: remote newer means overwrite local', () => {
  const r = planMerge([local('a', T1, T1)], [remote('a', T2)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['a']);
  assert.deepEqual(r.toPush, []);
});

test('rule 2: a tie goes to the server', () => {
  // Clock skew between devices must not make them overwrite each other forever.
  const r = planMerge([local('a', T1, T1)], [remote('a', T1)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['a']);
  assert.deepEqual(r.toPush, []);
});

test('rule 3: a remote-only item is inserted locally', () => {
  const r = planMerge([], [remote('b', T1)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['b']);
  assert.deepEqual(r.toDeleteLocal, []);
});

test('rule 4: a synced local item missing from the server was deleted elsewhere', () => {
  const r = planMerge([local('c', T1, T1)], []);
  assert.deepEqual(r.toDeleteLocal, ['c']);
  assert.deepEqual(r.toPush, []);
});

test('handles all four rules together', () => {
  const r = planMerge(
    [local('unsynced', T2, null), local('older', T1, T1), local('gone', T1, T1)],
    [remote('older', T2), remote('new', T1)]
  );
  assert.deepEqual(r.toPush.map(i => i.id), ['unsynced']);
  assert.deepEqual(r.toWriteLocal.map(i => i.id).sort(), ['new', 'older']);
  assert.deepEqual(r.toDeleteLocal, ['gone']);
});

test('empty on both sides is a no-op', () => {
  assert.deepEqual(planMerge([], []), {
    toWriteLocal: [], toDeleteLocal: [], toPush: []
  });
});

test('carries the full remote record into toWriteLocal', () => {
  const doc = { id: 'a', updated_at: T2, word: 'hi', review_count: 3 };
  const r = planMerge([], [doc]);
  assert.deepEqual(r.toWriteLocal[0], doc);
});
