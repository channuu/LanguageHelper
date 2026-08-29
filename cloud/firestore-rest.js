// cloud/firestore-rest.js
// Firestore REST v1의 값 표현과 평범한 JS 객체 사이를 오간다.
// 이 모듈만 REST 표현을 안다 — 위 계층은 평범한 객체만 다룬다.

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
