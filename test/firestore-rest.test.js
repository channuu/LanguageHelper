import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toFirestoreFields, fromFirestoreFields } from '../cloud/firestore-rest.js';
import {
  listDocuments, writeDocument, deleteDocument, FirestoreError
} from '../cloud/firestore-rest.js';

function fakeFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, opts = {}) => {
    calls.push({ url, opts });
    return handler(url, opts);
  };
  return calls;
}

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body)
  };
}

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

test('listDocuments requests ordered documents and decodes them', async () => {
  const calls = fakeFetch(() => jsonResponse({
    documents: [{
      name: 'projects/p/databases/(default)/documents/users/u1/words/w1',
      fields: { id: { stringValue: 'w1' }, word: { stringValue: 'hi' } }
    }]
  }));

  const docs = await listDocuments('u1', 'words', 'TOKEN', { pageSize: 500 });

  assert.deepEqual(docs, [{ id: 'w1', word: 'hi' }]);
  assert.match(calls[0].url, /\/users\/u1\/words\?/);
  assert.match(calls[0].url, /pageSize=500/);
  assert.match(calls[0].url, /orderBy=updated_at\+desc/);
  assert.equal(calls[0].opts.headers.Authorization, 'Bearer TOKEN');
});

test('listDocuments returns empty array when the collection has no documents', async () => {
  fakeFetch(() => jsonResponse({}));
  assert.deepEqual(await listDocuments('u1', 'words', 'TOKEN', {}), []);
});

test('writeDocument PATCHes encoded fields', async () => {
  const calls = fakeFetch(() => jsonResponse({}));
  await writeDocument('u1', 'words', 'w1', { id: 'w1', review_count: 2 }, 'TOKEN');

  assert.equal(calls[0].opts.method, 'PATCH');
  assert.match(calls[0].url, /\/users\/u1\/words\/w1$/);
  assert.deepEqual(JSON.parse(calls[0].opts.body), {
    fields: { id: { stringValue: 'w1' }, review_count: { integerValue: '2' } }
  });
});

test('deleteDocument issues DELETE', async () => {
  const calls = fakeFetch(() => jsonResponse({}));
  await deleteDocument('u1', 'words', 'w1', 'TOKEN');
  assert.equal(calls[0].opts.method, 'DELETE');
  assert.match(calls[0].url, /\/users\/u1\/words\/w1$/);
});

test('deleteDocument treats 404 as success', async () => {
  // Already gone on the server is the outcome we wanted.
  fakeFetch(() => jsonResponse({ error: { message: 'NOT_FOUND' } }, 404));
  await deleteDocument('u1', 'words', 'w1', 'TOKEN');
});

test('a failing request throws FirestoreError carrying the status', async () => {
  fakeFetch(() => jsonResponse({ error: { message: 'UNAUTHENTICATED' } }, 401));
  await assert.rejects(
    () => listDocuments('u1', 'words', 'BAD', {}),
    (err) => err instanceof FirestoreError && err.status === 401
  );
});
