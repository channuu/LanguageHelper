import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toFirestoreFields, fromFirestoreFields } from '../cloud/firestore-rest.js';

test('encodes each scalar type', () => {
  assert.deepEqual(toFirestoreFields({ a: 'hi' }), { a: { stringValue: 'hi' } });
  assert.deepEqual(toFirestoreFields({ a: null }), { a: { nullValue: null } });
  assert.deepEqual(toFirestoreFields({ a: true }), { a: { booleanValue: true } });
  assert.deepEqual(toFirestoreFields({ a: 3 }), { a: { integerValue: '3' } });
  assert.deepEqual(toFirestoreFields({ a: 1.5 }), { a: { doubleValue: 1.5 } });
});

test('undefined values are omitted, not encoded as null', () => {
  assert.deepEqual(toFirestoreFields({ a: 'x', b: undefined }), { a: { stringValue: 'x' } });
});

test('decodes each scalar type', () => {
  assert.deepEqual(fromFirestoreFields({ a: { stringValue: 'hi' } }), { a: 'hi' });
  assert.deepEqual(fromFirestoreFields({ a: { nullValue: null } }), { a: null });
  assert.deepEqual(fromFirestoreFields({ a: { booleanValue: false } }), { a: false });
  // Firestore returns integers as JSON strings — they must come back as numbers.
  assert.deepEqual(fromFirestoreFields({ a: { integerValue: '42' } }), { a: 42 });
  assert.deepEqual(fromFirestoreFields({ a: { doubleValue: 1.5 } }), { a: 1.5 });
});

test('decodes missing fields object as empty', () => {
  assert.deepEqual(fromFirestoreFields(undefined), {});
});

test('round-trips a word record', () => {
  const word = {
    id: 'abc', word: 'ephemeral', definition: 'lasting a short time',
    sentence: 'an ephemeral moment', translation: '순간적인',
    platform: 'youtube', content_title: 'Test', content_id: 'v1',
    timestamp: 125.5, saved_at: '2026-08-29T00:00:00.000Z',
    review_count: 0, next_review_at: null,
    review_level: 0, last_reviewed_at: null,
    updated_at: '2026-08-29T00:00:00.000Z'
  };
  assert.deepEqual(fromFirestoreFields(toFirestoreFields(word)), word);
});

test('a whole-number double survives the round trip as a number', () => {
  // timestamp is conceptually a double but is often whole (0, 125). It goes out
  // as integerValue and must come back as a plain number, not a string.
  const out = fromFirestoreFields(toFirestoreFields({ timestamp: 125 }));
  assert.equal(out.timestamp, 125);
  assert.equal(typeof out.timestamp, 'number');
});
