import { test } from 'node:test';
import assert from 'node:assert/strict';
import { migrateWord, migrateSentence, SCHEMA_VERSION } from '../cloud/migrate.js';

const legacyWord = {
  id: 'w1', word: 'ephemeral', definition: 'short-lived',
  sentence: 'an ephemeral moment', translation: '순간적인',
  platform: 'youtube', contentTitle: 'Test Video', contentId: 'v1',
  timestamp: 125, savedAt: '2026-08-01T00:00:00.000Z',
  reviewCount: 0, nextReviewAt: null
};

test('renames camelCase keys to snake_case', () => {
  const out = migrateWord(legacyWord);
  assert.equal(out.content_title, 'Test Video');
  assert.equal(out.content_id, 'v1');
  assert.equal(out.saved_at, '2026-08-01T00:00:00.000Z');
  assert.equal(out.review_count, 0);
  assert.equal(out.next_review_at, null);
  assert.equal('contentTitle' in out, false);
  assert.equal('savedAt' in out, false);
});

test('seeds updated_at from saved_at and leaves synced_at null', () => {
  const out = migrateWord(legacyWord);
  assert.equal(out.updated_at, '2026-08-01T00:00:00.000Z');
  assert.equal(out.synced_at, null);
});

test('adds the review fields the app expects', () => {
  const out = migrateWord(legacyWord);
  assert.equal(out.review_level, 0);
  assert.equal(out.last_reviewed_at, null);
});

test('is idempotent — a migrated item passes through unchanged', () => {
  const once = migrateWord(legacyWord);
  assert.deepEqual(migrateWord(once), once);
});

test('preserves an already-set synced_at when re-run', () => {
  const synced = { ...migrateWord(legacyWord), synced_at: '2026-08-02T00:00:00.000Z' };
  assert.equal(migrateWord(synced).synced_at, '2026-08-02T00:00:00.000Z');
});

test('migrates a sentence with its own field set', () => {
  const out = migrateSentence({
    id: 's1', original: 'Hello there', translation: '안녕하세요',
    platform: 'netflix', contentTitle: 'Show', contentId: 'c1',
    timestamp: 10, savedAt: '2026-08-01T00:00:00.000Z',
    reviewCount: 1, nextReviewAt: '2026-08-02T00:00:00.000Z'
  });
  assert.equal(out.original, 'Hello there');
  assert.equal(out.content_title, 'Show');
  assert.equal(out.review_count, 1);
  assert.equal(out.next_review_at, '2026-08-02T00:00:00.000Z');
  assert.equal(out.updated_at, '2026-08-01T00:00:00.000Z');
  assert.equal('word' in out, false);
});

test('tolerates an item missing savedAt entirely', () => {
  const out = migrateWord({ id: 'w2', word: 'x' });
  assert.equal(typeof out.updated_at, 'string');
  assert.ok(out.updated_at.length > 0);
  assert.equal(out.saved_at, out.updated_at);
});

test('exposes a schema version', () => {
  assert.equal(SCHEMA_VERSION, 1);
});
