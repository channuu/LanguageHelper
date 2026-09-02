import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { syncNow, capItems } from '../cloud/sync.js';
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
  let onWordGet = null;

  globalThis.fetch = async (url, opts = {}) => {
    const method = opts.method || 'GET';
    const entity = url.includes('/sentences') ? 'sentences' : 'words';
    const idMatch = url.match(/\/(words|sentences)\/([^/?]+)/);

    if (method === 'GET') {
      if (entity === 'words' && onWordGet) await onWordGet();
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

  return {
    collections,
    setOnWordPatch: (fn) => { onWordPatch = fn; },
    setOnWordGet: (fn) => { onWordGet = fn; }
  };
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

test('an item saved during the pull half of a sync survives (pull-side of defect 2)', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [];
  store['eh-sentences'] = [];

  const fs = installFakeFirestore();
  fs.collections.words.set('w9', {
    id: 'w9', word: 'remote', updated_at: '2026-01-01T00:00:00.000Z'
  });

  // The race pullEntity has to survive is a save landing AFTER it read its
  // local snapshot and BEFORE it writes the merged array back. Hooking the
  // network GET is too early (the snapshot is read after it), so inject on
  // the first eh-words read that follows the GET: the caller still receives
  // the pre-injection snapshot, exactly as it would if SAVE_WORD had run a
  // microsecond later.
  let seenGet = false;
  let injected = false;
  fs.setOnWordGet(async () => { seenGet = true; });
  const realGet = chrome.storage.local.get.bind(chrome.storage.local);
  chrome.storage.local.get = async (keys) => {
    const out = await realGet(keys);
    if (seenGet && !injected && String(keys).includes('eh-words')) {
      injected = true;
      store['eh-words'] = [
        ...(store['eh-words'] || []),
        { id: 'w2', word: 'beta', updated_at: '2026-01-02T00:00:00.000Z', synced_at: null }
      ];
    }
    return out;
  };

  const result = await syncNow();

  assert.equal(result.ok, true);
  assert.ok(injected, '테스트가 실제로 경합을 만들지 못했다');
  const ids = store['eh-words'].map(w => w.id).sort();
  assert.deepEqual(ids, ['w2', 'w9'], '왕복 중 저장한 항목이 사라졌다');
});

test('an item deleted during a sync is not resurrected by the pull', async () => {
  setValidAuth(store);
  store['eh-schema-version'] = SCHEMA_VERSION;
  store['eh-words'] = [
    {
      id: 'w1', word: 'alpha',
      updated_at: '2026-01-01T00:00:00.000Z',
      synced_at: '2026-01-01T00:00:00.000Z'
    }
  ];
  store['eh-sentences'] = [];

  const fs = installFakeFirestore();
  fs.collections.words.set('w1', {
    id: 'w1', word: 'alpha', updated_at: '2026-01-01T00:00:00.000Z'
  });
  // The user deletes w1 while the GET is in flight: it leaves storage and
  // joins the delete queue, which this sync already pushed past.
  fs.setOnWordGet(async () => {
    store['eh-words'] = [];
    store['eh-sync-queue'] = [{ entity: 'words', docId: 'w1' }];
  });

  await syncNow();

  assert.deepEqual(store['eh-words'].map(w => w.id), [],
    '지운 항목이 같은 sync의 pull에서 되살아났다');
});

test('capItems never drops an item that has not been uploaded yet', () => {
  const items = [
    { id: 'new', synced_at: null },
    { id: 'a', synced_at: 'x' },
    { id: 'old-unsynced', synced_at: null }
  ];
  assert.deepEqual(
    capItems(items, 2).map(i => i.id),
    ['new', 'old-unsynced'],
    '서버에 없는 항목을 버리면 되돌릴 방법이 없다'
  );
});

test('capItems drops the oldest synced items first and keeps order', () => {
  const items = [
    { id: 'a', synced_at: 'x' },
    { id: 'b', synced_at: 'x' },
    { id: 'c', synced_at: 'x' }
  ];
  assert.deepEqual(capItems(items, 2).map(i => i.id), ['a', 'b']);
});

test('capItems leaves a list under the cap untouched', () => {
  const items = [{ id: 'a', synced_at: null }];
  assert.equal(capItems(items, 2), items);
});
