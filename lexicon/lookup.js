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
let refreshPromise = null; // service worker 생애주기당 한 번만 실행한다

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
  }).catch(err => {
    dbPromise = null; // 다음 호출에서 다시 열기를 시도한다 — 실패를 영구 기억하지 않는다
    throw err;
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

const idbGet = (store, key) =>
  // 캐시 읽기 실패는 조회 실패가 아니다 (설계 §11) — 캐시가 없는 것처럼 취급한다.
  idb(store, 'readonly', s => s.get(key)).catch(err => {
    console.warn('[EH dict] 캐시 읽기 실패', err);
    return undefined;
  });
const idbPut = (store, key, value) =>
  // 캐시 쓰기 실패는 조회 실패가 아니다 (설계 §11).
  idb(store, 'readwrite', s => s.put(value, key)).catch(err => {
    console.warn('[EH dict] 캐시 쓰기 실패', err);
  });
const idbDel = (store, key) => idb(store, 'readwrite', s => s.delete(key)).catch(() => {});

/**
 * 같은 키에 대한 읽기-수정-쓰기를 단일 트랜잭션 안에서 원자적으로 수행한다.
 * getBucket과 refreshVersion이 meta.hashes를 동시에 갱신할 때의
 * lost-update 경쟁을 막기 위함이다 — 두 개의 별도 트랜잭션으로 하면 안 된다.
 */
function idbUpdate(store, key, fn) {
  return openDB().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(store, 'readwrite');
    const os = tx.objectStore(store);
    const getReq = os.get(key);
    getReq.onsuccess = () => {
      os.put(fn(getReq.result), key);
    };
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  })).catch(err => {
    console.warn('[EH dict] 캐시 갱신 실패', err);
  });
}

async function fetchJson(pathname) {
  const res = await fetch(`${DICT_BASE}/${pathname}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`dict fetch ${pathname}: ${res.status}`);
  return res.json();
}

/**
 * 해시가 달라진 버킷과, 버전이 바뀌었다면 mwe/inflections 인덱스를 버린다.
 * 실패하면 조용히 넘어간다 — 캐시는 그대로 쓴다 (설계 §11).
 */
async function refreshVersion() {
  let remote = null;
  try { remote = await fetchJson('version.json'); } catch (e) {
    console.warn('[EH dict] version.json 조회 실패', e);
    return;
  }

  const cachedHashes = (await idbGet('meta', 'hashes')) || {};
  const stale = staleBuckets(cachedHashes, remote);
  for (const b of stale) {
    await idbDel('buckets', b);
  }
  if (stale.length) {
    await idbUpdate('meta', 'hashes', hashes => {
      const next = { ...(hashes || {}) };
      for (const b of stale) delete next[b];
      return next;
    });
  }
  await idbPut('meta', 'version', remote);

  const cachedIndex = await idbGet('meta', 'index');
  if (cachedIndex && cachedIndex.version !== remote.version) {
    await idbDel('meta', 'index');
    indexPromise = null; // 다음 getIndex() 호출에서 새로 받는다
  }
}

/** 서비스워커 생애주기당 한 번만 version.json을 확인한다. */
function ensureFresh() {
  if (!refreshPromise) {
    refreshPromise = refreshVersion().catch(err => {
      // refreshVersion은 이미 내부에서 실패를 삼키지만, 예상 못 한 오류에 대비한다.
      console.warn('[EH dict] 버전 확인 실패', err);
      refreshPromise = null; // 다음 호출에서 다시 시도한다 — 캐시는 그대로 쓴다
    });
  }
  return refreshPromise;
}

/** mwe-index.json과 inflections.json. 캐시된 버전 문자열이 최신과 같으면 재사용한다. */
function getIndex() {
  if (indexPromise) return indexPromise;
  indexPromise = (async () => {
    const cached = await idbGet('meta', 'index');
    if (cached) return cached;
    const [mwe, inflections] = await Promise.all([
      fetchJson('mwe-index.json'), fetchJson('inflections.json')
    ]);
    const version = await idbGet('meta', 'version');
    const index = { version: version && version.version, mwe, inflections };
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
    await idbUpdate('meta', 'hashes', hashes => ({
      ...(hashes || {}),
      [name]: version.buckets[name],
    }));
  }
  return entries;
}

export async function scanText(text) {
  await ensureFresh();
  const index = await getIndex();
  return scanMwe(String(text).split(' '), index);
}

export async function lookup(term) {
  await ensureFresh();
  const key = String(term).toLowerCase().trim();
  if (!key) return null;

  const startBucket = bucketFor(key);
  let entries = await getBucket(startBucket);
  if (entries[key]) return entries[key];

  // 단일 단어라면 굴절형일 수 있다 — 원형으로 한 번 더 본다.
  if (!key.includes(' ')) {
    const { inflections } = await getIndex();
    const lemma = inflections[key];
    if (lemma && lemma !== key) {
      const b = bucketFor(lemma);
      entries = b === startBucket ? entries : await getBucket(b);
      if (entries[lemma]) return entries[lemma];
    }
  }
  return null;
}
