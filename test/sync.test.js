import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { syncNow } from '../cloud/sync.js';
import { SCHEMA_VERSION } from '../cloud/migrate.js';
import { toFirestoreFields, fromFirestoreFields } from '../cloud/firestore-rest.js';

// chrome.storage.local의 최소 대역 — test/auth.test.js와 같은 패턴.
function installFakeChrome() {
  const store = {};
  globalThis.chrome = {
    storage: {
      local: {
        async get(keys) {
          const ks = Array.isArray(keys) ? keys : [keys];
          const out = {};
          for (const k of ks) if (k in store) out[k] = store[k];
          return out;
        },
        async set(obj) { Object.assign(store, obj); },
        async remove(keys) {
          for (const k of (Array.isArray(keys) ? keys : [keys])) delete store[k];
        }
      }
    }
  };
  return store;
}

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body)
  };
}

function setValidAuth(store, overrides = {}) {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'ID',
    refreshToken: 'R', expiresAt: Date.now() + 600000,
    ...overrides
  };
}

/**
 * A minimal fake Firestore that actually remembers what's been PATCHed, so
 * the pull half of a sync sees the same documents the push half just wrote
 * (instead of an always-empty collection, which would make planMerge think
 * every synced item was deleted server-side).
 */
function installFakeFirestore() {
  const collections = { words: new Map(), sentences: new Map() };
  let onWordPatch = null;

  globalThis.fetch = async (url, opts = {}) => {
    const method = opts.method || 'GET';
    const entity = url.includes('/sentences') ? 'sentences' : 'words';
    const idMatch = url.match(/\/(words|sentences)\/([^/?]+)/);

    if (method === 'GET') {
      const docs = [...collections[entity].values()]
        .map(fields => ({ fields: toFirestoreFields(fields) }));
      return jsonResponse({ documents: docs });
    }
    if (method === 'PATCH') {
      if (entity === 'words' && onWordPatch) await onWordPatch();
      const body = JSON.parse(opts.body);
      collections[entity].set(idMatch[2], fromFirestoreFields(body.fields));
      return jsonResponse({});
    }
    if (method === 'DELETE') {
      collections[entity].delete(idMatch[2]);
      return jsonResponse({});
    }
    throw new Error('unexpected method ' + method);
  };

  return { collections, setOnWordPatch: (fn) => { onWordPatch = fn; } };
}

let store;
beforeEach(() => {
  store = installFakeChrome();
  globalThis.fetch = async () => { throw new Error('no fetch handler installed for this test'); };
});

test('syncNow returns ok:false instead of throwing when fetch rejects (offline)', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [];
  store['eh-sentences'] = [];
  globalThis.fetch = async () => { throw new TypeError('Failed to fetch'); };

  const result = await syncNow();
  assert.equal(result.ok, false);
});

test('an item saved during an in-flight sync still exists in storage afterward (defect 2)', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [
    { id: 'w1', word: 'alpha', updated_at: '2026-01-01T00:00:00.000Z', synced_at: null }
  ];
  store['eh-sentences'] = [];

  const fs = installFakeFirestore();
  // Simulate the SAVE_WORD handler writing directly to chrome.storage.local
  // while pushEntity is mid-await on the network — the exact race defect 2
  // describes.
  fs.setOnWordPatch(async () => {
    store['eh-words'] = [
      ...store['eh-words'],
      { id: 'w2', word: 'beta', updated_at: '2026-01-02T00:00:00.000Z', synced_at: null }
    ];
  });

  const result = await syncNow();

  assert.equal(result.ok, true);
  const ids = store['eh-words'].map(w => w.id).sort();
  assert.deepEqual(ids, ['w1', 'w2']);
});

test('a successful push marks the item synced_at and excludes it from pending', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [
    { id: 'w1', word: 'alpha', updated_at: '2026-01-01T00:00:00.000Z', synced_at: null }
  ];
  store['eh-sentences'] = [];
  installFakeFirestore();

  const result = await syncNow();

  assert.equal(result.ok, true);
  assert.ok(store['eh-words'][0].synced_at);
  assert.equal(result.pending, 0);
});

test('a failed push leaves the item unsynced and counted as pending', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [
    { id: 'w1', word: 'alpha', updated_at: '2026-01-01T00:00:00.000Z', synced_at: null }
  ];
  store['eh-sentences'] = [];

  globalThis.fetch = async (url, opts = {}) => {
    if ((opts.method || 'GET') === 'PATCH') {
      return jsonResponse({ error: { message: 'boom' } }, 500);
    }
    return jsonResponse({ documents: [] });
  };

  const result = await syncNow();

  assert.equal(result.ok, false);
  assert.equal(store['eh-words'][0].synced_at, null);
  assert.equal(result.pending, 1);
});

test('synced_at is never present in any object handed to writeDocument', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [
    { id: 'w1', word: 'alpha', updated_at: '2026-01-01T00:00:00.000Z', synced_at: null }
  ];
  store['eh-sentences'] = [
    { id: 's1', original: 'hi', updated_at: '2026-01-01T00:00:00.000Z', synced_at: null }
  ];

  const patchBodies = [];
  globalThis.fetch = async (url, opts = {}) => {
    if ((opts.method || 'GET') === 'PATCH') {
      patchBodies.push(JSON.parse(opts.body));
      return jsonResponse({});
    }
    return jsonResponse({ documents: [] });
  };

  const result = await syncNow();

  assert.equal(result.ok, true);
  assert.ok(patchBodies.length > 0);
  for (const body of patchBodies) {
    assert.ok(!('synced_at' in body.fields));
  }
});
