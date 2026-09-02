// lexicon/lookup.js
// 설계 문서 §7의 조회 계층. service worker에서만 로드한다 —
// content script는 IIFE 전역 방식이라 이 모듈을 import할 수 없다.

import { DICT_BASE } from './config.js';
import { scanMwe } from './mwe-match.js';
import { staleBuckets } from './cache-plan.js';
// 버킷 배정 규칙은 빌드와 조회가 반드시 같아야 한다 — 한 곳에서 가져온다.
import { bucketFor } from './build-transform.js';

const DB_NAME = 'eh-dict';
const DB_VERSION = 1;

let dbPromise = null;
let indexPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('buckets')) db.createObjectStore('buckets');
      if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function idb(store, mode, fn) {
  return openDB().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(store, mode);
    const req = fn(tx.objectStore(store));
    tx.oncomplete = () => resolve(req ? req.result : undefined);
    tx.onerror = () => reject(tx.error);
  }));
}

const idbGet = (store, key) => idb(store, 'readonly', s => s.get(key));
const idbPut = (store, key, value) =>
  // 캐시 쓰기 실패는 조회 실패가 아니다 (설계 §11).
  idb(store, 'readwrite', s => s.put(value, key)).catch(err => {
    console.warn('[EH dict] 캐시 쓰기 실패', err);
  });
const idbDel = (store, key) => idb(store, 'readwrite', s => s.delete(key)).catch(() => {});

async function fetchJson(pathname) {
  const res = await fetch(`${DICT_BASE}/${pathname}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`dict fetch ${pathname}: ${res.status}`);
  return res.json();
}

/** 해시가 달라진 버킷을 버린다. 실패하면 조용히 넘어간다 — 캐시는 그대로 쓴다. */
async function refreshVersion() {
  let remote = null;
  try { remote = await fetchJson('version.json'); } catch (e) {
    console.warn('[EH dict] version.json 조회 실패', e);
    return;
  }
  const cached = (await idbGet('meta', 'hashes')) || {};
  const stale = staleBuckets(cached, remote);
  for (const b of stale) {
    await idbDel('buckets', b);
    delete cached[b];
  }
  if (stale.length) await idbPut('meta', 'hashes', cached);
  await idbPut('meta', 'version', remote);
}

/** mwe-index.json과 inflections.json. 최초 1회만 받는다. */
function getIndex() {
  if (indexPromise) return indexPromise;
  indexPromise = (async () => {
    const cached = await idbGet('meta', 'index');
    if (cached) return cached;
    const [mwe, inflections] = await Promise.all([
      fetchJson('mwe-index.json'), fetchJson('inflections.json')
    ]);
    const index = { mwe, inflections };
    await idbPut('meta', 'index', index);
    return index;
  })().catch(err => {
    indexPromise = null;               // 다음 호출에서 다시 시도한다
    throw err;
  });
  return indexPromise;
}

async function getBucket(name) {
  const cached = await idbGet('buckets', name);
  if (cached) return cached;
  const entries = await fetchJson(`b/${name}.json`);
  await idbPut('buckets', name, entries);
  const version = await idbGet('meta', 'version');
  if (version && version.buckets && version.buckets[name]) {
    const hashes = (await idbGet('meta', 'hashes')) || {};
    hashes[name] = version.buckets[name];
    await idbPut('meta', 'hashes', hashes);
  }
  return entries;
}

export async function scanText(text) {
  const index = await getIndex();
  return scanMwe(String(text).split(' '), index);
}

export async function lookup(term) {
  await refreshVersion();
  const key = String(term).toLowerCase().trim();
  if (!key) return null;

  let entries = await getBucket(bucketFor(key));
  if (entries[key]) return entries[key];

  // 단일 단어라면 굴절형일 수 있다 — 원형으로 한 번 더 본다.
  if (!key.includes(' ')) {
    const { inflections } = await getIndex();
    const lemma = inflections[key];
    if (lemma && lemma !== key) {
      const b = bucketFor(lemma);
      entries = b === bucketFor(key) ? entries : await getBucket(b);
      if (entries[lemma]) return entries[lemma];
    }
  }
  return null;
}
