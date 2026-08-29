// cloud/firestore-rest.js
// Firestore REST v1의 값 표현과 평범한 JS 객체 사이를 오간다.
// 이 모듈만 REST 표현을 안다 — 위 계층은 평범한 객체만 다룬다.

import { FIRESTORE_BASE } from './config.js';

function toValue(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v)
      ? { integerValue: String(v) }
      : { doubleValue: v };
  }
  throw new TypeError('unsupported Firestore value: ' + typeof v);
}

function fromValue(v) {
  if ('nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  throw new TypeError('unsupported Firestore value: ' + JSON.stringify(v));
}

export function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined) continue;
    fields[k] = toValue(v);
  }
  return fields;
}

export function fromFirestoreFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) {
    out[k] = fromValue(v);
  }
  return out;
}

export class FirestoreError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'FirestoreError';
    this.status = status;
  }
}

function docUrl(uid, collection, docId) {
  return `${FIRESTORE_BASE}/users/${uid}/${collection}/${encodeURIComponent(docId)}`;
}

async function request(url, opts, idToken) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      ...(opts.headers || {}),
      'Authorization': 'Bearer ' + idToken,
      'Content-Type': 'application/json'
    }
  });
  if (!res.ok) {
    let message = res.status + '';
    try {
      const body = await res.json();
      message = (body && body.error && body.error.message) || message;
    } catch (_) { /* 본문이 JSON이 아니면 상태 코드만 남긴다 */ }
    throw new FirestoreError(res.status, message);
  }
  return res.json();
}

export async function listDocuments(uid, collection, idToken, { pageSize = 500 } = {}) {
  const url = `${FIRESTORE_BASE}/users/${uid}/${collection}`
    + `?pageSize=${pageSize}&orderBy=updated_at+desc`;
  const body = await request(url, { method: 'GET' }, idToken);
  return (body.documents || []).map(d => fromFirestoreFields(d.fields));
}

export async function writeDocument(uid, collection, docId, data, idToken) {
  await request(
    docUrl(uid, collection, docId),
    { method: 'PATCH', body: JSON.stringify({ fields: toFirestoreFields(data) }) },
    idToken
  );
}

export async function deleteDocument(uid, collection, docId, idToken) {
  try {
    await request(docUrl(uid, collection, docId), { method: 'DELETE' }, idToken);
  } catch (err) {
    // 이미 서버에 없으면 우리가 원한 결과다.
    if (err instanceof FirestoreError && err.status === 404) return;
    throw err;
  }
}
