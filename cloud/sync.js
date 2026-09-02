// cloud/sync.js
// 로컬(chrome.storage.local)이 진실이고 Firestore는 미러다.
// 푸시 실패는 조용히 삼킨다 — 로컬 저장은 이미 성공했고, 매번 토스트를
// 띄우면 지하철에서 단어를 저장할 때마다 경고가 뜬다. 대신 미동기 개수로
// 드러낸다 (설계 §10.2).
import { getAuth, getValidToken } from './auth.js';
import {
  listDocuments, writeDocument, deleteDocument, FirestoreError
} from './firestore-rest.js';
import { migrateWord, migrateSentence, SCHEMA_VERSION } from './migrate.js';
import { planMerge } from './merge.js';

const KEYS = { words: 'eh-words', sentences: 'eh-sentences' };
const QUEUE_KEY = 'eh-sync-queue';
const LAST_UID_KEY = 'eh-last-uid';
const LAST_SYNC_KEY = 'eh-last-sync';
const VERSION_KEY = 'eh-schema-version';
const MAX_ITEMS = 500;

/**
 * 500개 상한을 지키되 아직 서버에 올라가지 않은 항목은 남긴다.
 * synced_at이 null인 항목은 여기서 버리면 서버에도 없어 되돌릴 수 없다.
 * 오래된 쪽(배열 끝)부터, 이미 올라간 항목만 골라 떨어뜨린다.
 */
export function capItems(items, max = MAX_ITEMS) {
  if (items.length <= max) return items;
  let toDrop = items.length - max;
  const out = [];
  for (let i = items.length - 1; i >= 0; i--) {
    if (toDrop > 0 && items[i].synced_at != null) { toDrop--; continue; }
    out.unshift(items[i]);
  }
  return out;
}

async function read(key, fallback) {
  const res = await chrome.storage.local.get(key);
  return res[key] === undefined ? fallback : res[key];
}

async function write(key, value) {
  await chrome.storage.local.set({ [key]: value });
}

export async function ensureMigrated() {
  const version = await read(VERSION_KEY, 0);
  if (version >= SCHEMA_VERSION) return;

  await write(KEYS.words, (await read(KEYS.words, [])).map(migrateWord));
  await write(KEYS.sentences, (await read(KEYS.sentences, [])).map(migrateSentence));
  await write(VERSION_KEY, SCHEMA_VERSION);
}

export async function queueDelete(entity, docId) {
  const queue = await read(QUEUE_KEY, []);
  if (!queue.some(q => q.entity === entity && q.docId === docId)) {
    queue.push({ entity, docId });
    await write(QUEUE_KEY, queue);
  }
}

async function countPending() {
  const words = await read(KEYS.words, []);
  const sentences = await read(KEYS.sentences, []);
  const queue = await read(QUEUE_KEY, []);
  return words.filter(w => w.synced_at == null).length
    + sentences.filter(s => s.synced_at == null).length
    + queue.length;
}

export async function getSyncStatus() {
  return {
    lastSyncAt: await read(LAST_SYNC_KEY, null),
    pending: await countPending()
  };
}

export async function clearLocalData() {
  await chrome.storage.local.remove([
    KEYS.words, KEYS.sentences, QUEUE_KEY, LAST_SYNC_KEY
  ]);
}

/** Firestore에 올릴 형태 — synced_at은 기기별 사실이라 서버에 두지 않는다. */
function forRemote(item) {
  const { synced_at, ...rest } = item;
  return rest;
}

async function pushEntity(uid, entity, token) {
  const items = await read(KEYS[entity], []);
  const now = new Date().toISOString();
  const pushedIds = [];

  for (const item of items) {
    if (item.synced_at != null) continue;
    await writeDocument(uid, entity, item.id, forRemote(item), token);
    pushedIds.push(item.id);
  }
  if (pushedIds.length === 0) return;

  // Re-read right before writing: SAVE_WORD (or a concurrent sync run) can
  // have changed this key while we were awaiting the network above. Stamp
  // synced_at onto the CURRENT array by id instead of writing back the stale
  // `items` snapshot — that would silently erase anything saved meanwhile.
  const current = await read(KEYS[entity], []);
  const pushedSet = new Set(pushedIds);
  const stamped = current.map(i => (
    pushedSet.has(i.id) ? { ...i, synced_at: now } : i
  ));
  await write(KEYS[entity], stamped);
}

async function pushDeletes(uid, token) {
  const queue = await read(QUEUE_KEY, []);
  if (queue.length === 0) return;

  const remaining = [];
  for (const entry of queue) {
    try {
      await deleteDocument(uid, entry.entity, entry.docId, token);
    } catch (err) {
      // A genuine bug (not a Firestore/network failure) must surface instead
      // of being retried forever in silence — same principle as syncNow.
      if (!(err instanceof FirestoreError)) throw err;
      remaining.push(entry);
    }
  }
  await write(QUEUE_KEY, remaining);
}

async function pullEntity(uid, entity, token) {
  const remote = await listDocuments(uid, entity, token, { pageSize: MAX_ITEMS });
  const local = await read(KEYS[entity], []);
  const { toWriteLocal, toDeleteLocal } = planMerge(local, remote);

  // Re-read right before writing and apply the merge decision (computed from
  // the `local` snapshot above) onto the CURRENT array by id. Items added to
  // storage after `local` was read (e.g. SAVE_WORD) have synced_at == null
  // and were never part of the merge input — basing the map on `current`
  // means they're simply untouched entries in it, so they survive. Deletes
  // still apply by id against `current`, so nothing the merge decided to
  // remove gets resurrected.
  const current = await read(KEYS[entity], []);
  const byId = new Map(current.map(i => [i.id, i]));
  for (const id of toDeleteLocal) byId.delete(id);

  // 삭제 대기 중인 항목은 서버 문서로 되살리지 않는다. 이번 sync의
  // pushDeletes가 지나간 뒤에 지운 항목이 여기 남는데, 서버에는 아직 그
  // 문서가 있어 rule 3이 "서버에만 있음"으로 읽고 다시 넣어버린다 —
  // 방금 지운 게 눈앞에서 되살아난다. 다음 sync가 서버에서 지울 것이다.
  const queuedDeletes = new Set(
    (await read(QUEUE_KEY, []))
      .filter(q => q.entity === entity)
      .map(q => q.docId)
  );

  const now = new Date().toISOString();
  for (const doc of toWriteLocal) {
    if (queuedDeletes.has(doc.id)) continue;
    // 서버에서 온 문서는 정의상 동기화된 상태다.
    byId.set(doc.id, { ...doc, synced_at: now });
  }

  const merged = capItems(
    [...byId.values()]
      .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))
  );

  await write(KEYS[entity], merged);
}

// syncNow can genuinely run concurrently — a save triggers one while the
// 15-minute alarm fires another. Chain every call through this so a second
// caller awaits the in-flight run instead of racing it. `.catch(() => {})`
// keeps a rejected run from poisoning the chain and blocking future syncs.
let syncChain = Promise.resolve();

export function syncNow() {
  const run = syncChain.then(() => runSyncNow());
  syncChain = run.catch(() => {});
  return run;
}

/**
 * 로컬 데이터의 주인이 지금 로그인한 계정인지 확인하고, 아니면 비운다 (설계 §4.4).
 *
 * 이 검사는 sync 경로 안에 있어야 한다. 예전에는 로그인 창이 보내는
 * EH_AUTH_CHANGED 한 번에만 걸려 있었는데, login.js는 그 메시지의 실패를
 * 조용히 삼킨다(창이 먼저 닫히면 그렇게 된다). 그러면 이전 계정의 단어가
 * 로컬에 남고, 다음 sync가 그것을 새 계정의 Firestore로 올려버린다 —
 * 실제로 새 계정으로 가입하자마자 남의 단어가 보이는 사고가 났다.
 *
 * 저장된 uid가 없으면 지우지 않는다. 기존 사용자가 처음 로그인하는 경우라
 * 여기서 지우면 라이브러리를 통째로 날린다.
 */
export async function ensureOwner(uid) {
  const lastUid = await read(LAST_UID_KEY, null);
  if (lastUid && lastUid !== uid) await clearLocalData();
  await write(LAST_UID_KEY, uid);
}

/**
 * 밀린 것을 먼저 올리고, 그다음 내려받는다.
 * 401은 getValidToken이 이미 갱신을 시도한 뒤이므로 재시도하지 않는다.
 */
async function runSyncNow() {
  await ensureMigrated();

  const auth = await getAuth();
  if (!auth) return { ok: false, pending: 0 };

  await ensureOwner(auth.uid);

  const token = await getValidToken();
  if (!token) return { ok: false, pending: await countPending() };

  try {
    await pushDeletes(auth.uid, token);
    for (const entity of ['words', 'sentences']) {
      await pushEntity(auth.uid, entity, token);
      await pullEntity(auth.uid, entity, token);
    }
    await write(LAST_SYNC_KEY, new Date().toISOString());
    return { ok: true, pending: await countPending() };
  } catch (err) {
    if (!(err instanceof FirestoreError)) throw err;
    console.warn('[EH Sync] failed', err.status, err.message);
    return { ok: false, pending: await countPending() };
  }
}
