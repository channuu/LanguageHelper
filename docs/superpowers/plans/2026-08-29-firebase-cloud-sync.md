# Firebase 계정 + 클라우드 동기화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 확장과 Flutter 앱을 Firebase 계정 하나로 묶고, 저장한 단어·문장·타이머 기록이 수동 파일 왕복 없이 양쪽에 나타나게 한다.

**Architecture:** 로컬(`chrome.storage.local` / `LocalSQLiteRepository`)이 진실의 원천으로 남고, 그 위에 동기화 계층을 얹는다. 확장은 빌드 스텝 없이 Firebase Auth REST와 Firestore REST를 `fetch`로 직접 호출한다. 앱은 공식 `firebase_auth` / `cloud_firestore` 패키지를 쓴다. 충돌은 `updated_at` 기준 문서 통째 LWW로 해결한다.

**Tech Stack:** Chrome MV3 (vanilla JS, ES modules in service worker), Node 내장 `node --test`, Flutter 3 / Dart, sqflite, firebase_core·firebase_auth·cloud_firestore, Firestore REST v1, Identity Toolkit v1

**설계 문서:** `docs/superpowers/specs/2026-08-29-firebase-cloud-sync-design.md`

**이 계획의 범위:** 설계 문서 §13의 1~4단계(Firebase 준비 → 스키마 → 인증 → 동기화). 5단계(`.sqlite` 제거, 4탭화, JSON 내보내기)는 이 계획이 검증된 뒤 별도 계획으로 진행한다 — 순서가 뒤집히면 기존 사용자의 데이터 이동 경로가 잠시 끊긴다.

## Global Constraints

- **빌드 스텝을 도입하지 않는다.** 번들러, 트랜스파일러, `node_modules` 의존성을 추가하지 않는다. 테스트는 Node 내장 `node --test`만 쓴다.
- **확장의 클라우드 코드는 서비스워커에서만 로드한다.** `cloud/*.js`를 `manifest.json`의 `content_scripts`에 넣지 않는다. 인증 토큰이 영상 페이지 DOM 컨텍스트에 노출되면 안 된다.
- **Firestore 필드명은 snake_case.** `saved_at`, `content_title`, `content_id`, `review_count`, `next_review_at`, `review_level`, `last_reviewed_at`, `updated_at`.
- **`synced_at`은 로컬 전용.** Firestore 문서에 절대 쓰지 않는다.
- **비밀번호 입력 폼은 확장 자체 페이지(`auth/login.html`)에만 둔다.** 콘텐츠 스크립트에 만들지 않는다.
- **Firestore 보안 규칙 배포가 모든 클라이언트 작업보다 먼저다** (Task 1).
- UI 문구는 한국어. 기존 톤(`'✓ 문장 저장됨'`, `'내보낼 자막이 없어요'`)을 따른다.
- 커밋 메시지는 기존 규약(`feat:`, `fix:`, `test:`, `chore:`)을 따른다.

---

## Task 1: Firebase 프로젝트 준비와 보안 규칙 배포

**Files:**
- Create: `firestore.rules`
- Create: `cloud/config.js`
- Modify: `manifest.json` (host_permissions, permissions, service_worker type)
- Modify: `.gitignore:4-6`

**Interfaces:**
- Produces: `cloud/config.js`가 `export const FIREBASE = { apiKey, projectId }`를 내보낸다. 이후 모든 확장 클라우드 모듈이 이걸 import한다.

- [ ] **Step 1: Firebase 콘솔에서 프로젝트를 만든다 (수동)**

이 단계는 사람이 직접 해야 한다. 브라우저에서:

1. https://console.firebase.google.com 에서 프로젝트 생성 (이름 예: `english-helper`)
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable** (Email link는 끈 채로 둔다)
3. **Build → Firestore Database → Create database → Production mode**, 리전은 `asia-northeast3`(서울)
4. **프로젝트 설정 → 일반 → 내 앱 → 웹 앱 추가** → `apiKey`와 `projectId`를 적어둔다

- [ ] **Step 2: 보안 규칙 파일을 만든다**

`firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

- [ ] **Step 3: 규칙을 배포한다 (수동)**

Firebase 콘솔 **Firestore Database → 규칙** 탭에 위 내용을 붙여넣고 **게시**를 누른다.

배포 확인: 규칙 탭 상단에 "마지막 게시" 시각이 방금으로 갱신되어야 한다.

> 규칙이 배포되기 전에는 데이터가 무방비다. 이 단계를 건너뛰고 다음 태스크로 넘어가지 않는다.

- [ ] **Step 4: 확장 설정 파일을 만든다**

`cloud/config.js` — Step 1에서 적어둔 값으로 채운다. Firebase Web API 키는 비밀이 아니다(클라이언트 노출을 전제로 설계된 식별자이며, 실제 접근 통제는 Step 2의 규칙이 담당한다). 그러므로 이 파일은 저장소에 커밋한다.

```js
// cloud/config.js
// Firebase Web API 키는 비밀이 아니다. 클라이언트에 노출되는 것을 전제로
// 설계된 식별자이며, 실제 접근 통제는 firestore.rules가 담당한다.
export const FIREBASE = {
  apiKey: 'AIzaSy...',        // ← 콘솔의 실제 값으로 교체
  projectId: 'english-helper' // ← 콘솔의 실제 값으로 교체
};

export const IDENTITY_BASE = 'https://identitytoolkit.googleapis.com/v1';
export const TOKEN_BASE = 'https://securetoken.googleapis.com/v1';
export const FIRESTORE_BASE =
  `https://firestore.googleapis.com/v1/projects/${FIREBASE.projectId}/databases/(default)/documents`;
```

- [ ] **Step 5: manifest를 갱신한다**

`manifest.json`에서 세 곳을 고친다.

`permissions`에 `"alarms"` 추가 (Task 9의 주기 flush에 필요):

```json
  "permissions": ["storage", "activeTab", "tabs", "alarms"],
```

`host_permissions`에 세 호스트 추가:

```json
  "host_permissions": [
    "https://www.youtube.com/*",
    "https://www.netflix.com/*",
    "https://www.disneyplus.com/*",
    "https://*.coupangplay.com/*",
    "https://api.dictionaryapi.dev/*",
    "https://identitytoolkit.googleapis.com/*",
    "https://securetoken.googleapis.com/*",
    "https://firestore.googleapis.com/*"
  ],
```

`background`를 ES 모듈로 전환 (`cloud/*.js`를 `import`하기 위해. 서비스워커에는 `window`가 없어 콘텐츠 스크립트의 IIFE + `window.EH` 패턴을 그대로 쓸 수 없다):

```json
  "background": {
    "service_worker": "background/service_worker.js",
    "type": "module"
  },
```

- [ ] **Step 6: .gitignore의 잘못된 주석을 제거한다**

`.gitignore`에서 아래 세 줄을 삭제한다. Web API 키가 비밀이라는 전제가 틀렸고, 남겨두면 다음 사람이 헷갈린다.

```
# 보안상 Firebase 설정 파일을 Git에서 제외하고 싶다면 아래 주석을 해제하세요.
# (공개 저장소에 올릴 경우 필수)
# firebase-config.js
```

- [ ] **Step 7: 확장이 여전히 로드되는지 확인한다**

Chrome에서 `chrome://extensions` → 개발자 모드 → "압축해제된 확장 프로그램을 로드" (이미 로드돼 있으면 새로고침 아이콘).

기대: 오류 없이 로드된다. "Service worker registration failed"가 뜨면 `"type": "module"` 전환 후 `service_worker.js`가 아직 클래식 문법(`importScripts` 등)을 쓰고 있는지 확인한다 — 현재 파일은 순수 함수 선언뿐이라 그대로 모듈로 동작한다.

YouTube 영상을 하나 열어 자막 오버레이가 평소처럼 뜨는지 확인한다.

- [ ] **Step 8: 커밋**

```bash
git add firestore.rules cloud/config.js manifest.json .gitignore
git commit -m "chore: add Firebase config, security rules, and manifest permissions"
```

---

## Task 2: Node 테스트 하네스와 Firestore 값 변환

**Files:**
- Create: `package.json`
- Create: `cloud/firestore-rest.js`
- Test: `test/firestore-rest.test.js`

**Interfaces:**
- Consumes: 없음 (순수 함수)
- Produces:
  - `toFirestoreFields(obj: object): object` — 평범한 JS 객체를 Firestore REST의 `fields` 표현으로
  - `fromFirestoreFields(fields: object): object` — 그 역
  - 두 함수 모두 `null`, 문자열, 정수, 실수, 불리언을 다룬다. 그 외 타입은 입력에 나타나지 않는다.

- [ ] **Step 1: 테스트를 돌릴 수 있게 package.json을 만든다**

의존성은 넣지 않는다. `node --test`는 Node 18+ 내장이다.

```json
{
  "name": "english-helper-extension",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test test/"
  }
}
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`test/firestore-rest.test.js`:

```js
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
```

- [ ] **Step 3: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `Cannot find module '.../cloud/firestore-rest.js'`

- [ ] **Step 4: 변환 함수를 구현한다**

`cloud/firestore-rest.js`:

```js
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
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 6개 테스트 전부

- [ ] **Step 6: 커밋**

```bash
git add package.json cloud/firestore-rest.js test/firestore-rest.test.js
git commit -m "feat: add Firestore REST value encoding with node --test harness"
```

---

## Task 3: Firestore REST 호출부

**Files:**
- Modify: `cloud/firestore-rest.js`
- Test: `test/firestore-rest.test.js`

**Interfaces:**
- Consumes: `toFirestoreFields`, `fromFirestoreFields` (Task 2), `FIRESTORE_BASE` (Task 1)
- Produces:
  - `listDocuments(uid, collection, idToken, { pageSize }): Promise<Array<object>>` — 각 원소는 디코드된 문서(문서 id가 `id` 필드로 이미 들어있다). `updated_at` 내림차순.
  - `writeDocument(uid, collection, docId, data, idToken): Promise<void>`
  - `deleteDocument(uid, collection, docId, idToken): Promise<void>`
  - `class FirestoreError extends Error` — `status` 프로퍼티에 HTTP 상태 코드. Task 4의 401 감지가 이걸 본다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/firestore-rest.test.js` 끝에 추가한다. `globalThis.fetch`를 갈아끼워 검증한다.

```js
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `listDocuments is not a function` (import된 이름이 없음)

- [ ] **Step 3: 호출부를 구현한다**

`cloud/firestore-rest.js`의 import 줄과 함수들을 추가한다. 파일 맨 위에:

```js
import { FIRESTORE_BASE } from './config.js';
```

파일 끝에:

```js
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
    + `?pageSize=${pageSize}&orderBy=${encodeURIComponent('updated_at desc')}`;
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
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 12개 테스트 전부

- [ ] **Step 5: 커밋**

```bash
git add cloud/firestore-rest.js test/firestore-rest.test.js
git commit -m "feat: add Firestore REST list/write/delete calls"
```

---

## Task 4: 인증 모듈 (`cloud/auth.js`)

**Files:**
- Create: `cloud/auth.js`
- Test: `test/auth.test.js`

**Interfaces:**
- Consumes: `FIREBASE`, `IDENTITY_BASE`, `TOKEN_BASE` (Task 1)
- Produces:
  - `authErrorMessage(code: string): string` — Identity Toolkit 에러 코드를 한국어 문구로. 순수 함수.
  - `signUp(email, password): Promise<AuthState>`
  - `signIn(email, password): Promise<AuthState>`
  - `getAuth(): Promise<AuthState|null>` — `chrome.storage.local`의 `eh-auth`를 읽는다
  - `getValidToken(): Promise<string|null>` — 만료 60초 전이면 갱신 후 반환. 갱신 실패 시 `eh-auth`를 지우고 `null`
  - `signOutLocal(): Promise<void>` — `eh-auth`만 지운다. 로컬 캐시 정리는 Task 9의 호출자 책임
  - `AuthState = { uid, email, idToken, refreshToken, expiresAt }` (`expiresAt`은 epoch ms)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/auth.test.js`:

```js
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  authErrorMessage, signIn, signUp, getAuth, getValidToken, signOutLocal
} from '../cloud/auth.js';

// chrome.storage.local의 최소 대역. 서비스워커 밖(Node)에서 테스트하기 위한 것.
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
    json: async () => body
  };
}

let store;
beforeEach(() => { store = installFakeChrome(); });

test('maps known auth error codes to Korean copy', () => {
  assert.equal(authErrorMessage('EMAIL_EXISTS'), '이미 가입된 이메일이에요');
  assert.equal(authErrorMessage('INVALID_PASSWORD'), '이메일 또는 비밀번호가 맞지 않아요');
  assert.equal(authErrorMessage('EMAIL_NOT_FOUND'), '이메일 또는 비밀번호가 맞지 않아요');
  assert.equal(authErrorMessage('INVALID_LOGIN_CREDENTIALS'), '이메일 또는 비밀번호가 맞지 않아요');
  assert.equal(authErrorMessage('WEAK_PASSWORD : ...'), '비밀번호는 6자 이상이어야 해요');
  assert.equal(authErrorMessage('TOO_MANY_ATTEMPTS_TRY_LATER'), '잠시 후 다시 시도해 주세요');
});

test('falls back to a generic message for unknown codes', () => {
  assert.equal(authErrorMessage('SOMETHING_NEW'), '로그인에 실패했어요');
});

test('signIn stores the auth state', async () => {
  globalThis.fetch = async () => jsonResponse({
    localId: 'u1', email: 'a@b.c', idToken: 'ID', refreshToken: 'REFRESH', expiresIn: '3600'
  });

  const auth = await signIn('a@b.c', 'pw123456');

  assert.equal(auth.uid, 'u1');
  assert.equal(auth.idToken, 'ID');
  assert.equal(store['eh-auth'].refreshToken, 'REFRESH');
  assert.ok(store['eh-auth'].expiresAt > Date.now());
});

test('signUp posts to the signUp endpoint', async () => {
  let seenUrl;
  globalThis.fetch = async (url) => {
    seenUrl = url;
    return jsonResponse({
      localId: 'u2', email: 'x@y.z', idToken: 'ID2', refreshToken: 'R2', expiresIn: '3600'
    });
  };
  await signUp('x@y.z', 'pw123456');
  assert.match(seenUrl, /accounts:signUp\?key=/);
});

test('a failed sign-in throws with the mapped message', async () => {
  globalThis.fetch = async () =>
    jsonResponse({ error: { message: 'INVALID_LOGIN_CREDENTIALS' } }, 400);

  await assert.rejects(
    () => signIn('a@b.c', 'wrong'),
    (err) => err.message === '이메일 또는 비밀번호가 맞지 않아요'
  );
  assert.equal(store['eh-auth'], undefined);
});

test('getValidToken returns the stored token while it is still fresh', async () => {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'ID',
    refreshToken: 'R', expiresAt: Date.now() + 600000
  };
  globalThis.fetch = async () => { throw new Error('should not refresh'); };

  assert.equal(await getValidToken(), 'ID');
});

test('getValidToken refreshes an expired token and persists the new one', async () => {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'OLD',
    refreshToken: 'R', expiresAt: Date.now() - 1000
  };
  globalThis.fetch = async () => jsonResponse({
    id_token: 'NEW', refresh_token: 'R2', expires_in: '3600', user_id: 'u1'
  });

  assert.equal(await getValidToken(), 'NEW');
  assert.equal(store['eh-auth'].idToken, 'NEW');
  assert.equal(store['eh-auth'].refreshToken, 'R2');
});

test('getValidToken clears auth when the refresh itself fails', async () => {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'OLD',
    refreshToken: 'R', expiresAt: Date.now() - 1000
  };
  globalThis.fetch = async () => jsonResponse({ error: { message: 'TOKEN_EXPIRED' } }, 400);

  assert.equal(await getValidToken(), null);
  assert.equal(store['eh-auth'], undefined);
});

test('getValidToken returns null when signed out', async () => {
  assert.equal(await getValidToken(), null);
});

test('signOutLocal removes the stored auth', async () => {
  store['eh-auth'] = { uid: 'u1' };
  await signOutLocal();
  assert.equal(store['eh-auth'], undefined);
  assert.equal(await getAuth(), null);
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `Cannot find module '.../cloud/auth.js'`

- [ ] **Step 3: 인증 모듈을 구현한다**

`cloud/auth.js`:

```js
// cloud/auth.js
// Firebase Identity Toolkit REST를 감싼다. SDK를 번들하지 않는 이유는
// 설계 문서 §4.1 참고 — 이메일/비밀번호 방식은 OAuth 리다이렉트가 없어
// REST 호출 몇 개로 끝난다.
import { FIREBASE, IDENTITY_BASE, TOKEN_BASE } from './config.js';

const AUTH_KEY = 'eh-auth';
const REFRESH_MARGIN_MS = 60 * 1000;

const ERROR_COPY = {
  EMAIL_EXISTS: '이미 가입된 이메일이에요',
  EMAIL_NOT_FOUND: '이메일 또는 비밀번호가 맞지 않아요',
  INVALID_PASSWORD: '이메일 또는 비밀번호가 맞지 않아요',
  INVALID_LOGIN_CREDENTIALS: '이메일 또는 비밀번호가 맞지 않아요',
  INVALID_EMAIL: '이메일 형식을 확인해 주세요',
  WEAK_PASSWORD: '비밀번호는 6자 이상이어야 해요',
  TOO_MANY_ATTEMPTS_TRY_LATER: '잠시 후 다시 시도해 주세요',
  USER_DISABLED: '사용할 수 없는 계정이에요'
};

/**
 * Identity Toolkit의 에러 코드를 사용자 문구로 바꾼다.
 * 코드는 'WEAK_PASSWORD : Password should be...'처럼 꼬리가 붙어 오기도 한다.
 * 어느 쪽이 틀렸는지(이메일/비밀번호)는 구분해 알려주지 않는다.
 */
export function authErrorMessage(code) {
  const head = String(code || '').split(':')[0].trim();
  return ERROR_COPY[head] || '로그인에 실패했어요';
}

async function postJson(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(authErrorMessage(json && json.error && json.error.message));
  }
  return json;
}

async function persist(state) {
  await chrome.storage.local.set({ [AUTH_KEY]: state });
  return state;
}

function stateFromSignInResponse(json) {
  return {
    uid: json.localId,
    email: json.email,
    idToken: json.idToken,
    refreshToken: json.refreshToken,
    expiresAt: Date.now() + Number(json.expiresIn) * 1000
  };
}

export async function signUp(email, password) {
  const json = await postJson(
    `${IDENTITY_BASE}/accounts:signUp?key=${FIREBASE.apiKey}`,
    { email, password, returnSecureToken: true }
  );
  return persist(stateFromSignInResponse(json));
}

export async function signIn(email, password) {
  const json = await postJson(
    `${IDENTITY_BASE}/accounts:signInWithPassword?key=${FIREBASE.apiKey}`,
    { email, password, returnSecureToken: true }
  );
  return persist(stateFromSignInResponse(json));
}

export async function getAuth() {
  const res = await chrome.storage.local.get(AUTH_KEY);
  return res[AUTH_KEY] || null;
}

export async function signOutLocal() {
  await chrome.storage.local.remove(AUTH_KEY);
}

/**
 * 유효한 idToken을 돌려준다. 만료가 임박했으면 먼저 갱신한다.
 * 갱신에 실패하면(비밀번호 변경, 계정 삭제 등) 로그아웃 상태로 만들고 null.
 * 로컬 학습 데이터는 여기서 건드리지 않는다 — 사용자 의사에 의한
 * 로그아웃이 아니므로 미동기 항목이 남아 있을 수 있다 (설계 §4.4).
 */
export async function getValidToken() {
  const auth = await getAuth();
  if (!auth) return null;
  if (auth.expiresAt - REFRESH_MARGIN_MS > Date.now()) return auth.idToken;

  const res = await fetch(`${TOKEN_BASE}/token?key=${FIREBASE.apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: auth.refreshToken
    })
  });
  if (!res.ok) {
    await signOutLocal();
    return null;
  }
  const json = await res.json();
  const next = await persist({
    ...auth,
    idToken: json.id_token,
    refreshToken: json.refresh_token,
    expiresAt: Date.now() + Number(json.expires_in) * 1000
  });
  return next.idToken;
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 22개 테스트 전부

- [ ] **Step 5: 커밋**

```bash
git add cloud/auth.js test/auth.test.js
git commit -m "feat: add Firebase Identity Toolkit auth module for the extension"
```

---

## Task 5: 확장 로그인 페이지

**Files:**
- Create: `auth/login.html`
- Create: `auth/login.js`

**Interfaces:**
- Consumes: `signIn`, `signUp` (Task 4)
- Produces: `chrome.runtime.getURL('auth/login.html')`로 열리는 페이지. 로그인 성공 시 `chrome.runtime.sendMessage({ type: 'EH_AUTH_CHANGED' })`를 보내고 탭을 닫는다.

로그인 폼은 확장 자체 페이지에만 둔다. 오버레이(콘텐츠 스크립트)에 두면 YouTube·Netflix 페이지의 스크립트가 비밀번호 입력란을 읽을 수 있다 — 콘텐츠 스크립트는 JS 컨텍스트만 격리될 뿐 DOM은 호스트 페이지와 공유한다.

- [ ] **Step 1: 페이지 마크업을 만든다**

`auth/login.html` — `ui/tokens.css`를 재사용해 확장의 기존 시각 언어를 따른다.

```html
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>English Helper 로그인</title>
  <link rel="stylesheet" href="../ui/tokens.css">
  <style>
    body {
      margin: 0; min-height: 100vh;
      display: flex; align-items: center; justify-content: center;
      background: var(--eh-bg, #14110f);
      color: var(--eh-ink, #f5f0e8);
      font-family: system-ui, -apple-system, sans-serif;
    }
    .card { width: 320px; }
    h1 { font-size: 20px; margin: 0 0 4px; }
    .sub { font-size: 13px; opacity: .7; margin: 0 0 20px; }
    .tabs { display: flex; gap: 4px; margin-bottom: 16px; }
    .tab {
      flex: 1; padding: 8px; text-align: center; font-size: 13px;
      cursor: pointer; border-radius: 6px; opacity: .5;
    }
    .tab.active { background: rgba(255,255,255,.1); opacity: 1; }
    label { display: block; font-size: 12px; opacity: .7; margin-bottom: 4px; }
    input {
      width: 100%; box-sizing: border-box; padding: 10px;
      margin-bottom: 12px; border-radius: 6px;
      border: 1px solid rgba(255,255,255,.2);
      background: rgba(0,0,0,.25); color: inherit; font-size: 14px;
    }
    button {
      width: 100%; padding: 11px; border: 0; border-radius: 6px;
      background: var(--eh-accent, #e5a663); color: #14110f;
      font-size: 14px; font-weight: 600; cursor: pointer;
    }
    button[disabled] { opacity: .5; cursor: default; }
    .error { color: #ff8f7a; font-size: 13px; min-height: 18px; margin-top: 10px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>English Helper</h1>
    <p class="sub">저장한 단어를 모든 기기에서 보려면 로그인하세요.</p>
    <div class="tabs">
      <div class="tab active" id="tab-signin" data-mode="signin">로그인</div>
      <div class="tab" id="tab-signup" data-mode="signup">회원가입</div>
    </div>
    <label for="email">이메일</label>
    <input id="email" type="email" autocomplete="username">
    <label for="password">비밀번호</label>
    <input id="password" type="password" autocomplete="current-password">
    <button id="submit">로그인</button>
    <div class="error" id="error"></div>
  </div>
  <script type="module" src="login.js"></script>
</body>
</html>
```

- [ ] **Step 2: 페이지 동작을 구현한다**

`auth/login.js`:

```js
// auth/login.js
import { signIn, signUp, authErrorMessage } from '../cloud/auth.js';

let mode = 'signin';

const emailEl = document.getElementById('email');
const passwordEl = document.getElementById('password');
const submitEl = document.getElementById('submit');
const errorEl = document.getElementById('error');

function setMode(next) {
  mode = next;
  document.getElementById('tab-signin').classList.toggle('active', mode === 'signin');
  document.getElementById('tab-signup').classList.toggle('active', mode === 'signup');
  submitEl.textContent = mode === 'signin' ? '로그인' : '가입하고 시작하기';
  passwordEl.autocomplete = mode === 'signin' ? 'current-password' : 'new-password';
  errorEl.textContent = '';
}

document.querySelectorAll('.tab').forEach(t => {
  t.addEventListener('click', () => setMode(t.dataset.mode));
});

async function submit() {
  const email = emailEl.value.trim();
  const password = passwordEl.value;

  if (!email || !password) {
    errorEl.textContent = '이메일과 비밀번호를 입력해 주세요';
    return;
  }
  if (mode === 'signup' && password.length < 6) {
    errorEl.textContent = authErrorMessage('WEAK_PASSWORD');
    return;
  }

  submitEl.disabled = true;
  errorEl.textContent = '';
  try {
    await (mode === 'signin' ? signIn(email, password) : signUp(email, password));
    await chrome.runtime.sendMessage({ type: 'EH_AUTH_CHANGED' });
    window.close();
  } catch (err) {
    // signIn/signUp은 이미 사용자 문구로 바꿔서 던진다. 네트워크 실패만
    // 여기서 별도로 다룬다.
    errorEl.textContent = err instanceof TypeError
      ? '연결을 확인해 주세요'
      : err.message;
    submitEl.disabled = false;
  }
}

submitEl.addEventListener('click', submit);
passwordEl.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
emailEl.addEventListener('keydown', (e) => { if (e.key === 'Enter') passwordEl.focus(); });

setMode('signin');
```

- [ ] **Step 3: 수동으로 회원가입을 확인한다**

`chrome://extensions`에서 확장을 새로고침한 뒤, 서비스워커 콘솔("서비스 워커" 링크)에서:

```js
chrome.tabs.create({ url: chrome.runtime.getURL('auth/login.html') })
```

"회원가입" 탭에서 실제 이메일과 6자 이상 비밀번호로 가입한다.

기대:
- 탭이 저절로 닫힌다 (`EH_AUTH_CHANGED` 핸들러가 아직 없어 `sendMessage`가 거부될 수 있는데, `await`가 던지면 탭이 안 닫힌다. 그럴 경우 콘솔의 "Receiving end does not exist"는 Task 6에서 해소되므로 지금은 무시하고 다음 단계로 확인한다)
- Firebase 콘솔 **Authentication → Users**에 방금 이메일이 나타난다

- [ ] **Step 4: 저장된 인증 상태를 확인한다**

서비스워커 콘솔에서:

```js
chrome.storage.local.get('eh-auth').then(r => console.log(r['eh-auth']))
```

기대: `{ uid, email, idToken, refreshToken, expiresAt }`가 찍히고 `expiresAt`이 미래 시각이다.

- [ ] **Step 5: 잘못된 비밀번호를 확인한다**

로그인 페이지를 다시 열어 같은 이메일에 틀린 비밀번호로 "로그인"을 누른다.

기대: "이메일 또는 비밀번호가 맞지 않아요"가 표시되고 버튼이 다시 활성화된다.

- [ ] **Step 6: 커밋**

```bash
git add auth/login.html auth/login.js
git commit -m "feat: add extension login page"
```

---

## Task 6: 확장 저장 항목 스키마 마이그레이션

**Files:**
- Create: `cloud/migrate.js`
- Test: `test/migrate.test.js`
- Modify: `core/storage.js:14-40`

**Interfaces:**
- Consumes: 없음 (순수 함수)
- Produces:
  - `migrateWord(item: object): object`, `migrateSentence(item: object): object` — camelCase 항목을 snake_case + `updated_at`/`synced_at`으로. 이미 마이그레이션된 항목은 그대로 통과시킨다(멱등).
  - `SCHEMA_VERSION = 1` — `chrome.storage.local`의 `eh-schema-version`에 기록할 값

기존 확장 항목은 `savedAt`/`contentTitle`/`reviewCount` 같은 camelCase이고, 앱이 쓰는 `review_level`/`last_reviewed_at`도 없다. Firestore는 snake_case로 통일하므로(설계 §6.1) 여기서 한 번 바꿔둔다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/migrate.test.js`:

```js
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `Cannot find module '.../cloud/migrate.js'`

- [ ] **Step 3: 마이그레이션 함수를 구현한다**

`cloud/migrate.js`:

```js
// cloud/migrate.js
// 확장의 저장 항목을 Firestore와 같은 snake_case 스키마로 옮긴다.
// 멱등이다 — 서비스워커가 몇 번 재시작해도 안전하게 다시 돌릴 수 있다.

export const SCHEMA_VERSION = 1;

function pick(item, snake, camel, fallback) {
  if (item[snake] !== undefined) return item[snake];
  if (item[camel] !== undefined) return item[camel];
  return fallback;
}

function common(item) {
  const savedAt = pick(item, 'saved_at', 'savedAt', null)
    || new Date().toISOString();
  return {
    id: item.id,
    platform: item.platform || '',
    content_title: pick(item, 'content_title', 'contentTitle', ''),
    content_id: pick(item, 'content_id', 'contentId', ''),
    timestamp: item.timestamp || 0,
    saved_at: savedAt,
    review_count: pick(item, 'review_count', 'reviewCount', 0),
    next_review_at: pick(item, 'next_review_at', 'nextReviewAt', null),
    review_level: pick(item, 'review_level', 'reviewLevel', 0),
    last_reviewed_at: pick(item, 'last_reviewed_at', 'lastReviewedAt', null),
    updated_at: pick(item, 'updated_at', 'updatedAt', null) || savedAt,
    synced_at: item.synced_at !== undefined ? item.synced_at : null
  };
}

export function migrateWord(item) {
  return {
    ...common(item),
    word: item.word || '',
    definition: item.definition || '',
    sentence: item.sentence || '',
    translation: item.translation || ''
  };
}

export function migrateSentence(item) {
  return {
    ...common(item),
    original: item.original || '',
    translation: item.translation || ''
  };
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 30개 테스트 전부

- [ ] **Step 5: 새로 저장되는 항목도 새 스키마로 만든다**

`core/storage.js`의 `saveWord`와 `saveSentence`가 만드는 객체를 snake_case로 바꾼다. 이 파일은 콘텐츠 스크립트라 ES 모듈 import를 쓸 수 없으므로 필드를 직접 적는다.

`core/storage.js:14-27`의 `saveWord` 내부 `item`을 교체:

```js
      const now = new Date().toISOString();
      const item = {
        id: generateId(),
        word, definition: definition || '', sentence: sentence || '',
        translation: translation || '',
        platform: meta.platform,
        content_title: meta.title,
        content_id: meta.contentId,
        timestamp: timestamp || 0,
        saved_at: now,
        review_count: 0, next_review_at: null,
        review_level: 0, last_reviewed_at: null,
        updated_at: now, synced_at: null
      };
```

`core/storage.js:30-40`의 `saveSentence` 내부 `item`을 교체:

```js
      const now = new Date().toISOString();
      const item = {
        id: generateId(),
        original, translation: translation || '',
        platform: meta.platform,
        content_title: meta.title,
        content_id: meta.contentId,
        timestamp: timestamp || 0,
        saved_at: now,
        review_count: 0, next_review_at: null,
        review_level: 0, last_reviewed_at: null,
        updated_at: now, synced_at: null
      };
```

- [ ] **Step 6: 라이브러리 패널의 필드 참조를 고친다**

`core/library-panel.js:32-34`의 `currentVideoCount`가 `contentId`를 읽고 있다. snake_case로 바꾼다:

```js
    return words.filter(w => w.content_id === contentId).length +
           sentences.filter(s => s.content_id === contentId).length;
```

같은 파일에서 `w.timestamp`, `s.timestamp`, `w.word`, `w.translation`, `s.original`은 이름이 그대로라 손댈 필요 없다.

- [ ] **Step 7: 수동으로 저장을 확인한다**

확장을 새로고침하고 YouTube 영상에서 자막의 단어를 클릭해 "단어 저장"을 누른다. 서비스워커 콘솔에서:

```js
chrome.storage.local.get('eh-words').then(r => console.log(r['eh-words'][0]))
```

기대: `content_title`, `saved_at`, `updated_at`이 있고 `synced_at`이 `null`이며, `contentTitle`/`savedAt`은 없다.

- [ ] **Step 8: 커밋**

```bash
git add cloud/migrate.js test/migrate.test.js core/storage.js core/library-panel.js
git commit -m "feat: migrate extension items to snake_case schema with updated_at"
```

---

## Task 7: 병합 규칙 (순수 함수)

**Files:**
- Create: `cloud/merge.js`
- Test: `test/merge.test.js`

**Interfaces:**
- Consumes: 없음 (순수 함수)
- Produces:
  - `planMerge(local: Array<Item>, remote: Array<Item>): { toWriteLocal: Array<Item>, toDeleteLocal: Array<string>, toPush: Array<Item> }`
  - `Item`은 최소한 `{ id, updated_at, synced_at? }`을 가진 객체다. `synced_at`은 원격 항목에는 없다.
  - 이 함수는 확장과 앱 양쪽에서 같은 규칙을 쓴다. 앱 쪽 Dart 구현(Task 11)이 이 테스트와 같은 케이스를 갖는다.

설계 §7.3의 네 규칙을 그대로 옮긴다. 특히 규칙 1(미동기 항목 보존)과 규칙 4(삭제 전파)가 이 계획에서 가장 잘못되기 쉬운 부분이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/merge.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planMerge } from '../cloud/merge.js';

const T1 = '2026-08-01T00:00:00.000Z';
const T2 = '2026-08-02T00:00:00.000Z';

const local = (id, updated, synced) => ({ id, updated_at: updated, synced_at: synced });
const remote = (id, updated) => ({ id, updated_at: updated });

test('rule 1: an unsynced local item is pushed and never touched by the pull', () => {
  const r = planMerge([local('a', T1, null)], []);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toDeleteLocal, []);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 1 holds even when the server has an older copy', () => {
  // The local edit has not been uploaded yet, so it must win regardless.
  const r = planMerge([local('a', T2, null)], [remote('a', T1)]);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 2: the newer updated_at wins — local newer means push', () => {
  const r = planMerge([local('a', T2, T1)], [remote('a', T1)]);
  assert.deepEqual(r.toPush.map(i => i.id), ['a']);
  assert.deepEqual(r.toWriteLocal, []);
});

test('rule 2: remote newer means overwrite local', () => {
  const r = planMerge([local('a', T1, T1)], [remote('a', T2)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['a']);
  assert.deepEqual(r.toPush, []);
});

test('rule 2: a tie goes to the server', () => {
  // Clock skew between devices must not make them overwrite each other forever.
  const r = planMerge([local('a', T1, T1)], [remote('a', T1)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['a']);
  assert.deepEqual(r.toPush, []);
});

test('rule 3: a remote-only item is inserted locally', () => {
  const r = planMerge([], [remote('b', T1)]);
  assert.deepEqual(r.toWriteLocal.map(i => i.id), ['b']);
  assert.deepEqual(r.toDeleteLocal, []);
});

test('rule 4: a synced local item missing from the server was deleted elsewhere', () => {
  const r = planMerge([local('c', T1, T1)], []);
  assert.deepEqual(r.toDeleteLocal, ['c']);
  assert.deepEqual(r.toPush, []);
});

test('handles all four rules together', () => {
  const r = planMerge(
    [local('unsynced', T2, null), local('older', T1, T1), local('gone', T1, T1)],
    [remote('older', T2), remote('new', T1)]
  );
  assert.deepEqual(r.toPush.map(i => i.id), ['unsynced']);
  assert.deepEqual(r.toWriteLocal.map(i => i.id).sort(), ['new', 'older']);
  assert.deepEqual(r.toDeleteLocal, ['gone']);
});

test('empty on both sides is a no-op', () => {
  assert.deepEqual(planMerge([], []), {
    toWriteLocal: [], toDeleteLocal: [], toPush: []
  });
});

test('carries the full remote record into toWriteLocal', () => {
  const doc = { id: 'a', updated_at: T2, word: 'hi', review_count: 3 };
  const r = planMerge([], [doc]);
  assert.deepEqual(r.toWriteLocal[0], doc);
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `Cannot find module '.../cloud/merge.js'`

- [ ] **Step 3: 병합 함수를 구현한다**

`cloud/merge.js`:

```js
// cloud/merge.js
// 설계 문서 §7.3의 병합 규칙. 순수 함수다 — chrome.*도 fetch도 쓰지 않는다.
// 앱의 sync_service.dart가 같은 규칙을 Dart로 구현한다.

/**
 * @param {Array<{id: string, updated_at: string, synced_at: ?string}>} local
 * @param {Array<{id: string, updated_at: string}>} remote
 */
export function planMerge(local, remote) {
  const remoteById = new Map(remote.map(r => [r.id, r]));
  const localById = new Map(local.map(l => [l.id, l]));

  const toWriteLocal = [];
  const toDeleteLocal = [];
  const toPush = [];

  for (const item of local) {
    // 규칙 1 — 아직 안 올라간 항목은 서버에 없는 게 당연하다. 절대 덮지 않는다.
    if (item.synced_at == null) {
      toPush.push(item);
      continue;
    }
    const server = remoteById.get(item.id);
    if (!server) {
      // 규칙 4 — 올린 적 있는데 서버에 없다 = 다른 기기에서 삭제됐다.
      toDeleteLocal.push(item.id);
      continue;
    }
    // 규칙 2 — 늦은 쪽이 이긴다. 동률이면 서버.
    if (item.updated_at > server.updated_at) {
      toPush.push(item);
    } else {
      toWriteLocal.push(server);
    }
  }

  // 규칙 3 — 서버에만 있으면 로컬에 넣는다.
  for (const server of remote) {
    if (!localById.has(server.id)) toWriteLocal.push(server);
  }

  return { toWriteLocal, toDeleteLocal, toPush };
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 40개 테스트 전부

- [ ] **Step 5: 커밋**

```bash
git add cloud/merge.js test/merge.test.js
git commit -m "feat: add LWW merge rules shared by extension and app"
```

---

## Task 8: 확장 동기화 엔진

**Files:**
- Create: `cloud/sync.js`

**Interfaces:**
- Consumes: `getAuth`/`getValidToken`/`signOutLocal` (Task 4), `listDocuments`/`writeDocument`/`deleteDocument`/`FirestoreError` (Task 3), `migrateWord`/`migrateSentence`/`SCHEMA_VERSION` (Task 6), `planMerge` (Task 7)
- Produces:
  - `ensureMigrated(): Promise<void>` — `eh-schema-version`이 없으면 기존 항목을 마이그레이션하고 기록한다
  - `syncNow(): Promise<{ ok: boolean, pending: number }>` — push 후 pull. 미로그인이면 `{ ok: false, pending: 0 }`
  - `queueDelete(entity, docId): Promise<void>` — `eh-sync-queue`에 삭제를 기록
  - `getSyncStatus(): Promise<{ lastSyncAt: ?string, pending: number }>`
  - `clearLocalData(): Promise<void>` — 로그아웃/계정 전환용. 학습 항목과 큐를 비운다

`chrome.storage.local` 키: `eh-words`, `eh-sentences`(항목 배열), `eh-sync-queue`(`[{ entity, docId }]`), `eh-last-sync`(ISO 문자열), `eh-schema-version`(숫자), `eh-auth`(Task 4).

- [ ] **Step 1: 동기화 엔진을 구현한다**

`cloud/sync.js`:

```js
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
const LAST_SYNC_KEY = 'eh-last-sync';
const VERSION_KEY = 'eh-schema-version';
const MAX_ITEMS = 500;

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
  let changed = false;

  for (const item of items) {
    if (item.synced_at != null) continue;
    await writeDocument(uid, entity, item.id, forRemote(item), token);
    item.synced_at = now;
    changed = true;
  }
  if (changed) await write(KEYS[entity], items);
}

async function pushDeletes(uid, token) {
  const queue = await read(QUEUE_KEY, []);
  if (queue.length === 0) return;

  const remaining = [];
  for (const entry of queue) {
    try {
      await deleteDocument(uid, entry.entity, entry.docId, token);
    } catch (err) {
      remaining.push(entry);
    }
  }
  await write(QUEUE_KEY, remaining);
}

async function pullEntity(uid, entity, token) {
  const remote = await listDocuments(uid, entity, token, { pageSize: MAX_ITEMS });
  const local = await read(KEYS[entity], []);
  const { toWriteLocal, toDeleteLocal } = planMerge(local, remote);

  const byId = new Map(local.map(i => [i.id, i]));
  for (const id of toDeleteLocal) byId.delete(id);

  const now = new Date().toISOString();
  for (const doc of toWriteLocal) {
    // 서버에서 온 문서는 정의상 동기화된 상태다.
    byId.set(doc.id, { ...doc, synced_at: now });
  }

  const merged = [...byId.values()]
    .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))
    .slice(0, MAX_ITEMS);

  await write(KEYS[entity], merged);
}

/**
 * 밀린 것을 먼저 올리고, 그다음 내려받는다.
 * 401은 getValidToken이 이미 갱신을 시도한 뒤이므로 재시도하지 않는다.
 */
export async function syncNow() {
  await ensureMigrated();

  const auth = await getAuth();
  if (!auth) return { ok: false, pending: 0 };

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
```

- [ ] **Step 2: 커밋**

이 모듈은 `chrome.storage`와 네트워크에 얽혀 있어 단위 테스트 대상이 아니다(설계 §12). 배선은 Task 9, 실제 동작 확인은 Task 9의 수동 검증에서 한다.

```bash
git add cloud/sync.js
git commit -m "feat: add extension sync engine with push, pull, and delete queue"
```

---

## Task 9: 서비스워커 배선과 로그인 강제

**Files:**
- Modify: `background/service_worker.js`

**Interfaces:**
- Consumes: Task 4·6·8의 모든 export
- Produces: 새 메시지 타입 —
  - `EH_AUTH_STATE` → `{ success: true, signedIn: boolean, email: ?string }`
  - `EH_OPEN_LOGIN` → 로그인 탭을 연다
  - `EH_AUTH_CHANGED` → 로그인 직후 로그인 페이지가 보낸다. 계정 전환 감지 + 즉시 동기화 + 탭 브로드캐스트
  - `EH_SIGN_OUT` → `{ success: boolean, pending: number }`. `pending > 0`이고 `force`가 아니면 거부한다
  - `EH_SYNC_NOW` → `{ success: boolean, pending: number }`
  - `EH_SYNC_STATUS` → `{ success: true, lastSyncAt, pending }`
- 기존 `SAVE_WORD`/`SAVE_SENTENCE`/`GET_ALL`/`DELETE_ITEM`은 미로그인 시 `{ success: false, error: 'auth_required' }`

UI에서 막는 것과 별개로 서비스워커가 강제 지점이다. 콘텐츠 스크립트는 호스트 페이지와 DOM을 공유하므로 UI 조건만으로는 경계가 되지 못한다(설계 §5).

- [ ] **Step 1: import와 헬퍼를 파일 맨 위에 추가한다**

`background/service_worker.js`의 첫 줄(`// background/service_worker.js`) 바로 아래에 넣는다:

```js
import { getAuth, signOutLocal } from '../cloud/auth.js';
import {
  syncNow, ensureMigrated, queueDelete, getSyncStatus, clearLocalData
} from '../cloud/sync.js';

const LAST_UID_KEY = 'eh-last-uid';
const SUPPORTED_MATCHES = [
  'https://www.youtube.com/*',
  'https://www.netflix.com/*',
  'https://www.disneyplus.com/*',
  'https://*.coupangplay.com/*'
];

/** 열려 있는 지원 플랫폼 탭들에 인증 상태 변화를 알린다. */
async function broadcastAuthChanged() {
  const tabs = await chrome.tabs.query({ url: SUPPORTED_MATCHES });
  for (const tab of tabs) {
    // 콘텐츠 스크립트가 아직 없는 탭은 조용히 무시한다.
    chrome.tabs.sendMessage(tab.id, { type: 'EH_AUTH_CHANGED' }).catch(() => {});
  }
}

/** 다른 계정으로 로그인했으면 이전 계정의 로컬 캐시를 지운다 (설계 §4.4). */
async function handleAccountSwitch(uid) {
  const res = await chrome.storage.local.get(LAST_UID_KEY);
  const lastUid = res[LAST_UID_KEY];
  if (lastUid && lastUid !== uid) {
    await clearLocalData();
  }
  await chrome.storage.local.set({ [LAST_UID_KEY]: uid });
}
```

- [ ] **Step 2: 인증이 필요한 핸들러에 게이트를 건다**

`handleMessage` 함수 본문 맨 위, `switch` 문 바로 앞에 추가한다:

```js
async function handleMessage(message) {
  const AUTH_REQUIRED = ['SAVE_WORD', 'SAVE_SENTENCE', 'GET_ALL', 'DELETE_ITEM'];
  if (AUTH_REQUIRED.includes(message.type) && !(await getAuth())) {
    return { success: false, error: 'auth_required' };
  }

  switch (message.type) {
```

- [ ] **Step 3: 저장 핸들러가 저장 직후 푸시하게 한다**

`SAVE_WORD` 케이스를 교체한다:

```js
    case 'SAVE_WORD': {
      await ensureMigrated();
      const result = await chrome.storage.local.get('eh-words');
      const words = result['eh-words'] || [];
      words.unshift(message.payload);
      if (words.length > 500) words.splice(500);
      await chrome.storage.local.set({ 'eh-words': words });
      // 로컬 저장은 이미 끝났다. 업로드 실패는 미동기 상태로 남을 뿐이다.
      syncNow().catch(err => console.warn('[EH BG] sync after save', err));
      return { success: true, id: message.payload.id };
    }
```

`SAVE_SENTENCE` 케이스를 같은 모양으로 교체한다:

```js
    case 'SAVE_SENTENCE': {
      await ensureMigrated();
      const result = await chrome.storage.local.get('eh-sentences');
      const sentences = result['eh-sentences'] || [];
      sentences.unshift(message.payload);
      if (sentences.length > 500) sentences.splice(500);
      await chrome.storage.local.set({ 'eh-sentences': sentences });
      syncNow().catch(err => console.warn('[EH BG] sync after save', err));
      return { success: true, id: message.payload.id };
    }
```

- [ ] **Step 4: GET_ALL과 DELETE_ITEM을 갱신한다**

`GET_ALL` 케이스를 교체 — 마이그레이션이 먼저 돌아야 한다:

```js
    case 'GET_ALL': {
      await ensureMigrated();
      const result = await chrome.storage.local.get(['eh-words', 'eh-sentences']);
      return {
        success: true,
        words: result['eh-words'] || [],
        sentences: result['eh-sentences'] || []
      };
    }
```

`DELETE_ITEM` 케이스를 교체 — 삭제를 큐에 남겨 다른 기기까지 전파되게 한다:

```js
    case 'DELETE_ITEM': {
      const { type, id } = message.payload;
      const entity = type === 'word' ? 'words' : 'sentences';
      const key = 'eh-' + entity;
      const result = await chrome.storage.local.get(key);
      const items = (result[key] || []).filter(i => i.id !== id);
      await chrome.storage.local.set({ [key]: items });
      await queueDelete(entity, id);
      syncNow().catch(err => console.warn('[EH BG] sync after delete', err));
      return { success: true };
    }
```

- [ ] **Step 5: 인증·동기화 메시지 핸들러를 추가한다**

`default:` 케이스 바로 앞에 넣는다:

```js
    case 'EH_AUTH_STATE': {
      const auth = await getAuth();
      return { success: true, signedIn: !!auth, email: auth ? auth.email : null };
    }

    case 'EH_OPEN_LOGIN': {
      await chrome.tabs.create({ url: chrome.runtime.getURL('auth/login.html') });
      return { success: true };
    }

    case 'EH_AUTH_CHANGED': {
      const auth = await getAuth();
      if (auth) await handleAccountSwitch(auth.uid);
      const result = await syncNow();
      await broadcastAuthChanged();
      return { success: true, pending: result.pending };
    }

    case 'EH_SYNC_NOW': {
      const result = await syncNow();
      return { success: result.ok, pending: result.pending };
    }

    case 'EH_SYNC_STATUS': {
      const status = await getSyncStatus();
      return { success: true, ...status };
    }

    case 'EH_SIGN_OUT': {
      // 로그아웃 전에 밀린 것을 먼저 밀어낸다. 남으면 호출자가 확인받아야
      // 한다 — 로그아웃은 로컬 캐시를 비우므로 미동기 항목이 유실된다.
      const result = await syncNow();
      if (result.pending > 0 && !(message.payload && message.payload.force)) {
        return { success: false, error: 'pending', pending: result.pending };
      }
      await signOutLocal();
      await clearLocalData();
      await chrome.storage.local.remove('eh-last-uid');
      await broadcastAuthChanged();
      return { success: true, pending: 0 };
    }
```

- [ ] **Step 6: 시작 시 동기화와 주기 flush를 건다**

파일 맨 끝에 추가한다:

```js
// 서비스워커는 수시로 종료된다. 시작할 때마다 한 번 맞추고,
// 그 뒤로는 알람으로 밀린 것을 밀어낸다.
chrome.runtime.onStartup.addListener(() => {
  syncNow().catch(err => console.warn('[EH BG] startup sync', err));
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create('eh-sync', { periodInMinutes: 15 });
  syncNow().catch(err => console.warn('[EH BG] install sync', err));
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== 'eh-sync') return;
  syncNow().catch(err => console.warn('[EH BG] alarm sync', err));
});
```

- [ ] **Step 7: 미로그인 거부를 확인한다**

확장을 새로고침한다. 서비스워커 콘솔에서 먼저 로그아웃 상태로 만든다:

```js
chrome.storage.local.remove('eh-auth')
```

그다음:

```js
chrome.runtime.sendMessage({ type: 'SAVE_WORD', payload: { id: 'x' } })
  .then(console.log)
```

기대: `{ success: false, error: 'auth_required' }`

- [ ] **Step 8: 로그인 후 실제 동기화를 확인한다**

서비스워커 콘솔에서 로그인 페이지를 열고 Task 5에서 만든 계정으로 로그인한다:

```js
chrome.tabs.create({ url: chrome.runtime.getURL('auth/login.html') })
```

로그인 후 YouTube 영상에서 단어를 하나 저장한다. 그다음 서비스워커 콘솔에서:

```js
chrome.storage.local.get(['eh-words', 'eh-last-sync'])
  .then(r => console.log(r['eh-words'][0].synced_at, r['eh-last-sync']))
```

기대: `synced_at`이 `null`이 아니고 `eh-last-sync`에 방금 시각이 있다.

Firebase 콘솔 **Firestore Database → 데이터**에서 `users/{uid}/words/{id}` 문서가 보이고, 필드가 snake_case이며 **`synced_at` 필드는 없어야 한다.**

- [ ] **Step 9: 삭제 전파를 확인한다**

Firebase 콘솔에서 방금 문서를 직접 삭제한다. 서비스워커 콘솔에서:

```js
chrome.runtime.sendMessage({ type: 'EH_SYNC_NOW' }).then(console.log)
chrome.storage.local.get('eh-words').then(r => console.log(r['eh-words'].length))
```

기대: 로컬 항목 수가 하나 줄어 있다 (병합 규칙 4).

- [ ] **Step 10: 로그아웃 가드를 확인한다**

기내 모드를 흉내 내기 위해 서비스워커 콘솔에서 `fetch`를 잠시 막고 단어를 하나 저장한 뒤 로그아웃을 시도한다:

```js
const realFetch = globalThis.fetch;
globalThis.fetch = () => Promise.reject(new TypeError('offline'));
// (YouTube 탭에서 단어 하나 저장)
chrome.runtime.sendMessage({ type: 'EH_SIGN_OUT' }).then(console.log)
```

기대: `{ success: false, error: 'pending', pending: 1 }`

되돌린다: `globalThis.fetch = realFetch`

- [ ] **Step 11: 커밋**

```bash
git add background/service_worker.js
git commit -m "feat: wire auth gate and cloud sync into the service worker"
```

---

## Task 10: 확장 UI — 로그인 유도와 동기화 상태

**Files:**
- Modify: `core/word-popup.js:82-100`
- Modify: `core/script-panel.js:713-724`
- Modify: `core/library-panel.js:20-29`, `:37-60`
- Modify: `ui/overlay.css`

**Interfaces:**
- Consumes: `EH_OPEN_LOGIN`, `EH_AUTH_STATE`, `EH_SYNC_STATUS`, `EH_SIGN_OUT` (Task 9)
- Produces: 없음 (UI 종단)

저장 버튼은 비활성 처리하지 않는다. 비활성 버튼은 이유를 설명하지 못한다 — 누르면 안내를 띄운다(설계 §5).

- [ ] **Step 1: 공통 로그인 유도 헬퍼를 만든다**

`core/subtitle-engine.js`의 `window.EH.showToast` 정의(현재 293행) 바로 아래에 추가한다. 이 파일은 모든 플랫폼의 콘텐츠 스크립트에 이미 들어 있다.

```js
  /**
   * 저장류 메시지의 응답이 auth_required이면 안내를 띄우고 true를 돌려준다.
   * 로그인 폼 자체는 확장 페이지에서만 띄운다 — 콘텐츠 스크립트는 호스트
   * 페이지와 DOM을 공유하므로 여기서 비밀번호를 받으면 안 된다.
   */
  window.EH.handleAuthRequired = function (res) {
    if (!res || res.error !== 'auth_required') return false;
    window.EH.showToast?.('로그인이 필요해요 · 클릭해서 로그인');
    const toast = document.getElementById('eh-toast');
    if (toast) {
      toast.style.cursor = 'pointer';
      toast.onclick = () => {
        chrome.runtime.sendMessage({ type: 'EH_OPEN_LOGIN' });
        toast.onclick = null;
      };
    }
    return true;
  };
```

- [ ] **Step 2: 단어 팝업의 저장 경로에 붙인다**

`core/word-popup.js:82-101`의 두 리스너를 교체한다:

```js
    document.getElementById('eh-save-word').addEventListener('click', () => {
      window.EH.Storage.saveWord({
        word, definition: dict?.definition || '',
        sentence, translation, timestamp
      }).then((res) => {
        if (window.EH.handleAuthRequired(res)) return;
        window.EH.showToast?.(`✓ "${word}" 저장됨`);
        document.dispatchEvent(new CustomEvent('eh-item-saved'));
        hide();
      });
    });

    document.getElementById('eh-save-sent').addEventListener('click', () => {
      window.EH.Storage.saveSentence({ original: sentence, translation, timestamp })
        .then((res) => {
          if (window.EH.handleAuthRequired(res)) return;
          window.EH.showToast?.('✓ 문장 저장됨');
          document.dispatchEvent(new CustomEvent('eh-item-saved'));
          hide();
        });
    });
```

- [ ] **Step 3: 스크립트 패널의 문장 저장에 붙인다**

`core/script-panel.js:715-722`의 `saveSentence` 호출을 찾아 응답을 검사하게 바꾼다:

```js
            window.EH.Storage.saveSentence({
              original: enText,
              translation: koText,
              timestamp: cue.start
            }).then((res) => {
              if (window.EH.handleAuthRequired(res)) return;
              window.EH.showToast?.('✓ 문장 저장됨');
            });
```

> `enText`/`koText`/`cue`는 기존 코드의 지역 변수명이다. 실제 파일의 이름을 그대로 쓰고, 바뀌는 것은 `.then` 콜백 안뿐이다.

- [ ] **Step 4: 라이브러리 패널이 인증 상태를 읽게 한다**

`core/library-panel.js:20-29`의 `loadData`를 교체한다:

```js
  let signedIn = false;
  let email = null;
  let syncStatus = { lastSyncAt: null, pending: 0 };

  async function loadData() {
    try {
      const auth = await chrome.runtime.sendMessage({ type: 'EH_AUTH_STATE' });
      signedIn = !!(auth && auth.signedIn);
      email = auth ? auth.email : null;

      if (!signedIn) {
        words = [];
        sentences = [];
        return;
      }

      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      words = (res && res.words) || [];
      sentences = (res && res.sentences) || [];
      syncStatus = await chrome.runtime.sendMessage({ type: 'EH_SYNC_STATUS' });
    } catch (_) {
      words = [];
      sentences = [];
    }
  }
```

`let words = [];` 선언 위에 `signedIn`/`email`/`syncStatus`를 두어야 하므로, 파일 상단의 선언부(4-8행)에 함께 넣는다.

- [ ] **Step 5: 미로그인 화면과 동기화 표시를 렌더한다**

`core/library-panel.js`의 `render` 함수를 교체한다. `.eh-library-footer`의 SQLite 내보내기 버튼은 이 계획에서 그대로 둔다 — 제거는 다음 계획(§13 5단계)의 몫이다.

```js
  function formatSyncTime(iso) {
    if (!iso) return '아직 동기화 안 됨';
    const d = new Date(iso);
    return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')} 동기화됨`;
  }

  function render() {
    if (!signedIn) {
      panelEl.innerHTML = `
        <div class="eh-library-header">
          <span class="eh-library-title">SAVED LIBRARY</span>
          <span class="eh-library-close" id="eh-library-close">✕</span>
        </div>
        <div class="eh-library-signin">
          <div class="eh-library-signin-msg">저장한 단어를 보려면 로그인하세요.</div>
          <div class="eh-library-signin-btn" id="eh-library-signin">로그인</div>
        </div>
      `;
      panelEl.querySelector('#eh-library-close').addEventListener('click', hide);
      panelEl.querySelector('#eh-library-signin').addEventListener('click', () => {
        chrome.runtime.sendMessage({ type: 'EH_OPEN_LOGIN' });
      });
      return;
    }

    const items = tab === 'w' ? words : sentences;
    panelEl.innerHTML = `
      <div class="eh-library-header">
        <span class="eh-library-title">SAVED LIBRARY</span>
        <span class="eh-library-close" id="eh-library-close">✕</span>
      </div>
      <div class="eh-library-sync">
        <span class="eh-library-sync-time">${esc(formatSyncTime(syncStatus.lastSyncAt))}</span>
        ${syncStatus.pending > 0
          ? `<span class="eh-library-sync-pending">${syncStatus.pending}개 대기 중</span>`
          : ''}
        <span style="flex:1"></span>
        <span class="eh-library-signout" id="eh-library-signout">${esc(email || '')} · 로그아웃</span>
      </div>
      <div class="eh-library-tabs">
        <div class="eh-library-tab${tab === 'w' ? ' active' : ''}" data-tab="w">단어 ${words.length}</div>
        <div class="eh-library-tab${tab === 's' ? ' active' : ''}" data-tab="s">문장 ${sentences.length}</div>
        <span style="flex:1"></span>
        <span class="eh-library-video-count">이 영상 ${currentVideoCount()}</span>
      </div>
      <div class="eh-library-list">
        ${items.length === 0
          ? '<div class="eh-library-empty">저장한 항목이 없습니다</div>'
          : items.map(it => tab === 'w' ? wordCard(it) : sentenceCard(it)).join('')}
      </div>
      <div class="eh-library-footer">
        <div class="eh-library-export-btn" id="eh-library-export">SQLite 내보내기<span class="eh-library-export-ext">.sqlite</span></div>
        <div class="eh-library-hint">내보낸 파일은 앱의 가져오기 화면에서 불러옵니다.</div>
      </div>
    `;

    panelEl.querySelector('#eh-library-close').addEventListener('click', hide);

    panelEl.querySelector('#eh-library-signout').addEventListener('click', async () => {
      let res = await chrome.runtime.sendMessage({ type: 'EH_SIGN_OUT' });
      if (!res.success && res.error === 'pending') {
        const ok = confirm(
          `${res.pending}개 항목이 아직 저장되지 않았어요. 로그아웃하면 사라집니다. 계속할까요?`
        );
        if (!ok) return;
        res = await chrome.runtime.sendMessage({
          type: 'EH_SIGN_OUT', payload: { force: true }
        });
      }
      await loadData();
      render();
    });

    panelEl.querySelectorAll('.eh-library-tab').forEach(t => {
      t.addEventListener('click', () => { tab = t.dataset.tab; render(); });
    });

    panelEl.querySelectorAll('.eh-library-jump').forEach(el => {
      el.addEventListener('click', () => {
        const t = Number(el.dataset.timestamp);
        window.EH.adapter?.seekTo?.(t);
      });
    });

    panelEl.querySelector('#eh-library-export').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      const original = btn.innerHTML;
      btn.textContent = '내보내는 중...';
      try {
        await window.EH.SqliteExport.exportAll(words, sentences);
        btn.innerHTML = original;
      } catch (err) {
        console.error('[EH LibraryPanel] sqlite export failed', err);
        btn.textContent = '내보내기 실패';
        setTimeout(() => { btn.innerHTML = original; }, 2000);
      }
    });
  }
```

- [ ] **Step 6: 인증 변화에 패널이 반응하게 한다**

`core/library-panel.js`의 IIFE 끝(`})();` 바로 앞)에 추가한다:

```js
  chrome.runtime.onMessage.addListener((message) => {
    if (message.type !== 'EH_AUTH_CHANGED') return;
    if (!panelEl || !open) return;
    loadData().then(render);
  });
```

- [ ] **Step 7: 스타일을 추가한다**

`ui/overlay.css` 끝에 추가한다:

```css
/* 라이브러리 패널 — 로그인 유도와 동기화 상태 */
.eh-library-signin {
  padding: 32px 20px;
  display: flex; flex-direction: column; align-items: center; gap: 14px;
}
.eh-library-signin-msg { font-size: 13px; opacity: .75; text-align: center; }
.eh-library-signin-btn {
  padding: 8px 20px; border-radius: 6px; cursor: pointer;
  background: var(--eh-accent); color: #14110f;
  font-size: 13px; font-weight: 600;
}
.eh-library-sync {
  display: flex; align-items: center; gap: 8px;
  padding: 6px 12px; font-size: 11px; opacity: .65;
}
.eh-library-sync-pending { color: var(--eh-accent); opacity: 1; }
.eh-library-signout { cursor: pointer; text-decoration: underline; }
```

- [ ] **Step 8: 미로그인 흐름을 확인한다**

서비스워커 콘솔에서 `chrome.storage.local.remove('eh-auth')`로 로그아웃하고 YouTube 영상을 새로고침한다.

기대:
- 자막 오버레이와 스크립트 패널은 평소대로 동작한다
- 라이브러리 패널을 열면 "저장한 단어를 보려면 로그인하세요"와 로그인 버튼이 보인다
- 자막의 단어를 클릭해 "단어 저장"을 누르면 "로그인이 필요해요 · 클릭해서 로그인" 토스트가 뜨고, 토스트를 클릭하면 로그인 탭이 열린다

- [ ] **Step 9: 로그인 후 흐름을 확인한다**

열린 탭에서 로그인한다.

기대:
- 탭이 닫히고, YouTube 탭의 라이브러리 패널이 저절로 목록 화면으로 바뀐다 (Step 6의 브로드캐스트)
- 단어를 저장하면 `✓ "..." 저장됨` 토스트가 뜬다
- 라이브러리 패널 상단에 "HH:MM 동기화됨"과 계정 이메일이 보인다

- [ ] **Step 10: 커밋**

```bash
git add core/subtitle-engine.js core/word-popup.js core/script-panel.js core/library-panel.js ui/overlay.css
git commit -m "feat: add sign-in prompts and sync status to the extension overlay"
```

---

## Task 11: 앱 DB 마이그레이션 v3 → v4

**Files:**
- Modify: `mobile/lib/data/database.dart:42-94`
- Test: `mobile/test/data/database_migration_test.dart` (신규)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `openAppDatabase`가 버전 4를 연다
  - 4개 테이블(`words`, `sentences`, `study_sessions`, `weekly_goals`)에 `updated_at TEXT`, `synced_at TEXT` 컬럼
  - `sync_queue(entity TEXT, doc_id TEXT, PRIMARY KEY(entity, doc_id))` 테이블

기존 행은 `updated_at`을 생성 시각으로 채우고 `synced_at`은 `NULL`로 둔다. **이 마이그레이션 자체가 곧 "기존 데이터 전량 업로드 대상" 표시**가 된다(설계 §6.4).

> **`kWordsColumns` / `kSentencesColumns`는 건드리지 않는다.** 이름이 앱 DB 스키마처럼 보이지만 `hasValidSchema`가 *가져오기 파일*을 검증하는 데만 쓰는 상수다(`repository.dart`의 `mergeFromFile`). 여기에 새 컬럼을 넣으면 기존 `.sqlite` 백업 파일이 전부 "올바른 백업 파일이 아닙니다"로 거부된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`mobile/test/data/database_migration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v4 이전 스키마의 DB를 만든다 — 마이그레이션 경로를 실제로 태우기 위해서다.
Future<Database> openV3(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE words (
            id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT,
            sentence TEXT, translation TEXT, platform TEXT,
            content_title TEXT, content_id TEXT, timestamp REAL,
            saved_at TEXT, review_count INTEGER DEFAULT 0,
            next_review_at TEXT, review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sentences (
            id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT,
            platform TEXT, content_title TEXT, content_id TEXT,
            timestamp REAL, saved_at TEXT, review_count INTEGER DEFAULT 0,
            next_review_at TEXT, review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE study_sessions (
            id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL, saved_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE weekly_goals (
            id TEXT PRIMARY KEY, target_minutes INTEGER NOT NULL,
            effective_from TEXT NOT NULL, created_at TEXT NOT NULL
          )
        ''');
      },
    ),
  );
}

Future<Set<String>> columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v3 데이터가 있는 DB를 v4로 올리면 sync 컬럼이 채워진다', () async {
    final path = inMemoryDatabasePath;
    var db = await openV3(path);
    await db.insert('words', {
      'id': 'w1', 'word': 'ephemeral', 'platform': 'youtube',
      'content_title': 'T', 'content_id': 'v1', 'timestamp': 12.0,
      'saved_at': '2026-08-01T00:00:00.000Z', 'review_count': 0,
      'review_level': 0,
    });
    await db.insert('study_sessions', {
      'id': 's1', 'started_at': '2026-08-01T00:00:00.000Z',
      'ended_at': '2026-08-01T00:30:00.000Z', 'duration_seconds': 1800,
      'saved_at': '2026-08-01T00:30:00.000Z',
    });
    // 같은 in-memory 핸들을 유지해야 마이그레이션이 같은 DB에 적용된다.
    db = await openAppDatabase(path);

    expect(await columnsOf(db, 'words'), contains('updated_at'));
    expect(await columnsOf(db, 'words'), contains('synced_at'));
    expect(await columnsOf(db, 'sentences'), contains('updated_at'));
    expect(await columnsOf(db, 'study_sessions'), contains('updated_at'));
    expect(await columnsOf(db, 'weekly_goals'), contains('synced_at'));

    final word = (await db.query('words', where: 'id = ?', whereArgs: ['w1'])).single;
    expect(word['updated_at'], '2026-08-01T00:00:00.000Z');
    expect(word['synced_at'], isNull);

    final session =
        (await db.query('study_sessions', where: 'id = ?', whereArgs: ['s1'])).single;
    expect(session['updated_at'], '2026-08-01T00:30:00.000Z');
    expect(session['synced_at'], isNull);

    await db.close();
  });

  test('sync_queue 테이블이 생긴다', () async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    await db.insert('sync_queue', {'entity': 'words', 'doc_id': 'w1'});
    expect((await db.query('sync_queue')).length, 1);
    await db.close();
  });

  test('새 DB도 같은 컬럼을 갖는다', () async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    expect(await columnsOf(db, 'words'), contains('updated_at'));
    expect(await columnsOf(db, 'weekly_goals'), contains('updated_at'));
    await db.close();
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/data/database_migration_test.dart`
Expected: FAIL — `no such column: updated_at` 또는 `no such table: sync_queue`

- [ ] **Step 3: 마이그레이션을 구현한다**

`mobile/lib/data/database.dart`의 `_addReviewLevelColumns` 함수 아래에 추가한다:

```dart
const List<String> _syncedTables = [
  'words', 'sentences', 'study_sessions', 'weekly_goals',
];

/// 각 테이블에서 "이 행이 생긴 시각"으로 볼 컬럼. 기존 행의 updated_at을
/// 여기서 채운다 — 그 결과 마이그레이션 자체가 전량 업로드 대상 표시가 된다.
const Map<String, String> _createdAtColumn = {
  'words': 'saved_at',
  'sentences': 'saved_at',
  'study_sessions': 'saved_at',
  'weekly_goals': 'created_at',
};

Future<void> _addSyncColumns(Database db) async {
  for (final table in _syncedTables) {
    await db.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE $table ADD COLUMN synced_at TEXT');
    await db.execute(
      'UPDATE $table SET updated_at = ${_createdAtColumn[table]}',
    );
  }
  await _createSyncQueueTable(db);
}

Future<void> _createSyncQueueTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_queue (
      entity TEXT NOT NULL,
      doc_id TEXT NOT NULL,
      PRIMARY KEY (entity, doc_id)
    )
  ''');
}
```

- [ ] **Step 4: 새 DB 생성 경로에도 컬럼을 넣는다**

`openAppDatabase`에서 `version: 3`을 `version: 4`로 바꾸고, `onCreate`의 `words` 테이블 정의에서 `last_reviewed_at TEXT` 뒤에 두 컬럼을 추가한다:

```dart
            review_level INTEGER NOT NULL DEFAULT 0,
            last_reviewed_at TEXT,
            updated_at TEXT,
            synced_at TEXT
```

`sentences` 테이블 정의에도 똑같이 추가한다.

`_createTimerTables`의 두 테이블에도 추가한다:

```dart
Future<void> _createTimerTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS study_sessions (
      id TEXT PRIMARY KEY,
      started_at TEXT NOT NULL,
      ended_at TEXT NOT NULL,
      duration_seconds INTEGER NOT NULL,
      saved_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_goals (
      id TEXT PRIMARY KEY,
      target_minutes INTEGER NOT NULL,
      effective_from TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');
}
```

> `_createTimerTables`는 v1→v2 업그레이드 경로에서도 호출된다. 거기서 이미 새 컬럼이 붙은 채로 만들어지므로, `onUpgrade`에서 `oldVersion < 2`와 `oldVersion < 4`가 둘 다 걸리면 `duplicate column name` 오류가 난다. 다음 스텝에서 이를 막는다.

- [ ] **Step 5: onUpgrade를 갱신한다**

`openAppDatabase`의 `onUpgrade`를 교체한다:

```dart
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTimerTables(db);
        }
        if (oldVersion < 3) {
          await _addReviewLevelColumns(db);
        }
        if (oldVersion < 4) {
          // v2 미만에서 올라온 경우 타이머 테이블은 방금 새 스키마로
          // 만들어졌으니 words/sentences에만 컬럼을 붙인다.
          final tables = oldVersion < 2
              ? ['words', 'sentences']
              : _syncedTables;
          for (final table in tables) {
            await db.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT');
            await db.execute('ALTER TABLE $table ADD COLUMN synced_at TEXT');
            await db.execute(
              'UPDATE $table SET updated_at = ${_createdAtColumn[table]}',
            );
          }
          await _createSyncQueueTable(db);
        }
      },
```

`_addSyncColumns`는 이 분기 로직으로 대체되므로 Step 3에서 만든 그 함수는 삭제하고, `_syncedTables`·`_createdAtColumn`·`_createSyncQueueTable`만 남긴다.

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test test/data/database_migration_test.dart`
Expected: PASS — 3개 테스트

- [ ] **Step 7: 기존 테스트가 깨지지 않았는지 확인한다**

Run: `cd mobile && flutter test`
Expected: PASS — 전부

- [ ] **Step 8: 커밋**

```bash
git add mobile/lib/data/database.dart mobile/test/data/database_migration_test.dart
git commit -m "feat: migrate app database to v4 with sync columns and queue"
```

---

## Task 12: 모델과 저장소에 동기화 필드 배선

**Files:**
- Modify: `mobile/lib/data/models/word.dart`
- Modify: `mobile/lib/data/models/sentence.dart`
- Modify: `mobile/lib/data/repository.dart`
- Test: `mobile/test/data/repository_test.dart`

**Interfaces:**
- Consumes: Task 11의 스키마
- Produces:
  - `Word`/`Sentence`에 `String updatedAt`, `String? syncedAt` 필드와 `toMap`/`fromMap` 왕복
  - `LearningRepository`에 `Future<List<SyncQueueEntry>> getSyncQueue()`, `Future<void> queueDelete(String entity, String docId)`, `Future<void> clearSyncQueueEntry(String entity, String docId)`, `Future<void> clearAllLocalData()` 추가
  - `class SyncQueueEntry { final String entity; final String docId; }`
  - 모든 쓰기 경로(`saveWord`, `markWordReviewed`, `setWordReviewLevel` 등)가 `updatedAt = now`, `syncedAt = null`로 남긴다
  - `deleteWord`/`deleteSentence`가 `sync_queue`에 항목을 남긴다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`mobile/test/data/repository_test.dart` 끝에 추가한다 (기존 `main()` 안, 마지막 테스트 뒤).

```dart
  test('saveWord는 updatedAt을 채우고 syncedAt을 비운다', () async {
    final repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    await repo.saveWord(Word(
      id: 'w1', word: 'hi', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
    ));

    final saved = (await repo.getWords()).single;
    expect(saved.updatedAt, '2026-08-01T00:00:00.000Z');
    expect(saved.syncedAt, isNull);
  });

  test('markWordReviewed는 updatedAt을 밀고 syncedAt을 되돌린다', () async {
    final repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    await repo.saveWord(Word(
      id: 'w1', word: 'hi', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
      syncedAt: '2026-08-01T00:00:00.000Z',
    ));

    await repo.markWordReviewed('w1');

    final reviewed = (await repo.getWords()).single;
    expect(reviewed.syncedAt, isNull, reason: '복습은 다시 올려야 할 변경이다');
    expect(
      DateTime.parse(reviewed.updatedAt).isAfter(DateTime.parse('2026-08-01T00:00:00.000Z')),
      isTrue,
    );
  });

  test('deleteWord는 sync_queue에 삭제를 남긴다', () async {
    final repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    await repo.saveWord(Word(
      id: 'w1', word: 'hi', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
    ));

    await repo.deleteWord('w1');

    final queue = await repo.getSyncQueue();
    expect(queue.length, 1);
    expect(queue.single.entity, 'words');
    expect(queue.single.docId, 'w1');
  });

  test('clearSyncQueueEntry는 해당 항목만 지운다', () async {
    final repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    await repo.queueDelete('words', 'w1');
    await repo.queueDelete('sentences', 's1');

    await repo.clearSyncQueueEntry('words', 'w1');

    final queue = await repo.getSyncQueue();
    expect(queue.length, 1);
    expect(queue.single.entity, 'sentences');
  });

  test('clearAllLocalData는 학습 데이터와 큐를 모두 비운다', () async {
    final repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    await repo.saveWord(Word(
      id: 'w1', word: 'hi', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
    ));
    await repo.queueDelete('sentences', 's1');

    await repo.clearAllLocalData();

    expect(await repo.getWords(), isEmpty);
    expect(await repo.getSyncQueue(), isEmpty);
  });
```

> `openTestDb`와 `fakePrefs`는 기존 `repository_test.dart`가 이미 쓰는 헬퍼다. 파일 상단의 실제 이름을 확인해 맞춘다.

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/data/repository_test.dart`
Expected: FAIL — `No named parameter with the name 'updatedAt'`

- [ ] **Step 3: Word 모델에 필드를 추가한다**

`mobile/lib/data/models/word.dart`에서 네 곳을 고친다.

필드 선언에 추가 (`lastReviewedAt` 아래):

```dart
  final String updatedAt;
  final String? syncedAt;
```

생성자에 추가 (`this.lastReviewedAt,` 아래):

```dart
    required this.updatedAt,
    this.syncedAt,
```

`toMap`에 추가 (`'last_reviewed_at': lastReviewedAt,` 아래):

```dart
        'updated_at': updatedAt,
        'synced_at': syncedAt,
```

`fromMap`에 추가 (`lastReviewedAt: ...` 아래). 마이그레이션이 채우므로 보통은 값이 있지만, 없으면 `saved_at`으로 물러선다:

```dart
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
```

`copyWith`에도 추가한다. 시그니처에:

```dart
    String? updatedAt,
    Object? syncedAt = _unset,
```

반환하는 `Word(...)`에:

```dart
        updatedAt: updatedAt ?? this.updatedAt,
        syncedAt: identical(syncedAt, _unset)
            ? this.syncedAt
            : syncedAt as String?,
```

- [ ] **Step 4: Sentence 모델에 같은 변경을 한다**

`mobile/lib/data/models/sentence.dart`에 Step 3과 똑같은 다섯 군데 변경을 적용한다. 필드 선언, 생성자, `toMap`, `fromMap`, `copyWith` — 코드는 Step 3과 글자 그대로 동일하다(`Word(` 대신 `Sentence(`).

- [ ] **Step 5: 저장소의 쓰기 경로를 갱신한다**

`mobile/lib/data/repository.dart`에서:

`InvalidBackupFileException` 클래스 아래에 추가:

```dart
class SyncQueueEntry {
  final String entity;
  final String docId;
  const SyncQueueEntry({required this.entity, required this.docId});
}
```

`abstract class LearningRepository`에 메서드 4개 추가:

```dart
  Future<List<SyncQueueEntry>> getSyncQueue();
  Future<void> queueDelete(String entity, String docId);
  Future<void> clearSyncQueueEntry(String entity, String docId);
  Future<void> clearAllLocalData();
```

`LocalSQLiteRepository`에 구현을 추가한다:

```dart
  @override
  Future<List<SyncQueueEntry>> getSyncQueue() async {
    final db = await _database;
    final rows = await db.query('sync_queue');
    return rows
        .map((r) => SyncQueueEntry(
              entity: r['entity'] as String,
              docId: r['doc_id'] as String,
            ))
        .toList();
  }

  @override
  Future<void> queueDelete(String entity, String docId) async {
    final db = await _database;
    await db.insert(
      'sync_queue',
      {'entity': entity, 'doc_id': docId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearSyncQueueEntry(String entity, String docId) async {
    final db = await _database;
    await db.delete('sync_queue',
        where: 'entity = ? AND doc_id = ?', whereArgs: [entity, docId]);
  }

  @override
  Future<void> clearAllLocalData() async {
    final db = await _database;
    await db.delete('words');
    await db.delete('sentences');
    await db.delete('study_sessions');
    await db.delete('weekly_goals');
    await db.delete('sync_queue');
    notifyListeners();
  }
```

`deleteWord`와 `deleteSentence`가 큐를 남기게 바꾼다:

```dart
  @override
  Future<void> deleteWord(String id) async {
    final db = await _database;
    await db.delete('words', where: 'id = ?', whereArgs: [id]);
    await queueDelete('words', id);
    notifyListeners();
  }

  @override
  Future<void> deleteSentence(String id) async {
    final db = await _database;
    await db.delete('sentences', where: 'id = ?', whereArgs: [id]);
    await queueDelete('sentences', id);
    notifyListeners();
  }
```

- [ ] **Step 6: 복습 경로가 동기화 상태를 되돌리게 한다**

`markWordReviewed`의 `final updated = word.copyWith(` 호출에 두 인자를 추가한다. `markSentenceReviewed`, `setWordReviewLevel`, `setSentenceReviewLevel`의 `copyWith` 호출 네 곳 모두 같은 두 줄을 넣는다:

```dart
      updatedAt: now.toIso8601String(),
      syncedAt: null,
```

`copyWith`의 `syncedAt`은 `Object? syncedAt = _unset`이라 명시적으로 `null`을 넘기면 실제로 `null`로 설정된다 — 이게 의도다. 복습은 다시 올려야 할 변경이다.

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test`
Expected: PASS — 전부. 컴파일 오류가 나면 `Word(`/`Sentence(` 생성자 호출부에 `updatedAt:`이 빠진 곳이다. 테스트 픽스처와 `mergeFromFile`이 후보다.

`mergeFromFile`은 가져온 행 맵을 그대로 `db.insert`하므로 `updated_at`이 없는 채로 들어간다. 그 행들은 `fromMap`의 `saved_at` 폴백으로 읽히고 `synced_at`이 `null`이라 다음 동기화 때 업로드된다 — 의도한 동작이다.

- [ ] **Step 8: 커밋**

```bash
git add mobile/lib/data/models/word.dart mobile/lib/data/models/sentence.dart mobile/lib/data/repository.dart mobile/test/data/repository_test.dart
git commit -m "feat: add sync fields and delete queue to app models and repository"
```

---

## Task 13: 앱 인증 — Firebase 초기화, AuthService, 로그인 게이트

**Files:**
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/firebase_options.dart` (생성 도구가 만든다)
- Create: `mobile/lib/data/sync/auth_service.dart`
- Create: `mobile/lib/features/auth/login_screen.dart`
- Create: `mobile/lib/features/auth/auth_gate.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/app.dart:11-22`
- Test: `mobile/test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `abstract class AuthService` — `Stream<AuthUser?> authStateChanges()`, `AuthUser? get currentUser`, `Future<void> signIn(String, String)`, `Future<void> signUp(String, String)`, `Future<void> signOut()`
  - `class AuthUser { final String uid; final String email; }`
  - `class FirebaseAuthService implements AuthService`
  - `String authErrorMessage(String code)` — 확장의 `cloud/auth.js`와 같은 문구
  - `AuthGate` 위젯 — 미로그인이면 `LoginScreen`, 로그인이면 `child`

- [ ] **Step 1: 의존성을 추가한다**

`mobile/pubspec.yaml`의 `dependencies:` 아래에 추가한다:

```yaml
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
```

Run: `cd mobile && flutter pub get`
Expected: 성공. 버전 충돌이 나면 `flutter pub add firebase_core firebase_auth cloud_firestore`로 현재 Flutter SDK에 맞는 버전을 받는다.

- [ ] **Step 2: FlutterFire 설정을 만든다 (수동)**

```bash
dart pub global activate flutterfire_cli
cd mobile && flutterfire configure --project=<Task 1의 projectId>
```

플랫폼은 iOS와 Android를 고른다. 이 명령이 `mobile/lib/firebase_options.dart`를 만들고 `mobile/ios/Runner/GoogleService-Info.plist`를 넣는다.

확인: `ls mobile/lib/firebase_options.dart mobile/ios/Runner/GoogleService-Info.plist` — 둘 다 존재해야 한다.

- [ ] **Step 3: 실패하는 테스트를 쓴다**

`mobile/test/features/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper/data/sync/auth_service.dart';
import 'package:english_helper/features/auth/login_screen.dart';

class FakeAuthService implements AuthService {
  String? signedInEmail;
  String? signedUpEmail;
  Object? throwOnSignIn;

  @override
  AuthUser? currentUser;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> signIn(String email, String password) async {
    if (throwOnSignIn != null) throw throwOnSignIn!;
    signedInEmail = email;
  }

  @override
  Future<void> signUp(String email, String password) async {
    signedUpEmail = email;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

Future<void> pumpLogin(WidgetTester tester, AuthService auth) {
  return tester.pumpWidget(
    MaterialApp(home: LoginScreen(authService: auth)),
  );
}

void main() {
  testWidgets('이메일과 비밀번호를 넣고 로그인하면 authService를 호출한다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'pw123456');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedInEmail, 'a@b.c');
  });

  testWidgets('빈 입력이면 호출하지 않고 안내를 띄운다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedInEmail, isNull);
    expect(find.text('이메일과 비밀번호를 입력해 주세요'), findsOneWidget);
  });

  testWidgets('회원가입 탭에서 6자 미만 비밀번호는 막는다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'pw12');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedUpEmail, isNull);
    expect(find.text('비밀번호는 6자 이상이어야 해요'), findsOneWidget);
  });

  testWidgets('인증 실패 메시지를 화면에 보여준다', (tester) async {
    final auth = FakeAuthService()
      ..throwOnSignIn = AuthException('이메일 또는 비밀번호가 맞지 않아요');
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'wrongpw');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('이메일 또는 비밀번호가 맞지 않아요'), findsOneWidget);
  });

  test('에러 코드를 확장과 같은 문구로 옮긴다', () {
    expect(authErrorMessage('email-already-in-use'), '이미 가입된 이메일이에요');
    expect(authErrorMessage('wrong-password'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('user-not-found'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('invalid-credential'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('weak-password'), '비밀번호는 6자 이상이어야 해요');
    expect(authErrorMessage('too-many-requests'), '잠시 후 다시 시도해 주세요');
    expect(authErrorMessage('network-request-failed'), '연결을 확인해 주세요');
    expect(authErrorMessage('something-else'), '로그인에 실패했어요');
  });
}
```

- [ ] **Step 4: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:english_helper/data/sync/auth_service.dart'`

- [ ] **Step 5: AuthService를 구현한다**

`mobile/lib/data/sync/auth_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart' as fb;

class AuthUser {
  final String uid;
  final String email;
  const AuthUser({required this.uid, required this.email});
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

const Map<String, String> _errorCopy = {
  'email-already-in-use': '이미 가입된 이메일이에요',
  'user-not-found': '이메일 또는 비밀번호가 맞지 않아요',
  'wrong-password': '이메일 또는 비밀번호가 맞지 않아요',
  'invalid-credential': '이메일 또는 비밀번호가 맞지 않아요',
  'invalid-email': '이메일 형식을 확인해 주세요',
  'weak-password': '비밀번호는 6자 이상이어야 해요',
  'too-many-requests': '잠시 후 다시 시도해 주세요',
  'user-disabled': '사용할 수 없는 계정이에요',
  'network-request-failed': '연결을 확인해 주세요',
};

/// 확장의 cloud/auth.js와 같은 문구를 쓴다. 어느 쪽이 틀렸는지
/// (이메일/비밀번호) 구분해 알려주지 않는다.
String authErrorMessage(String code) =>
    _errorCopy[code] ?? '로그인에 실패했어요';

abstract class AuthService {
  Stream<AuthUser?> authStateChanges();
  AuthUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  final fb.FirebaseAuth _auth;

  FirebaseAuthService({fb.FirebaseAuth? auth})
      : _auth = auth ?? fb.FirebaseAuth.instance;

  static AuthUser? _toUser(fb.User? user) => user == null
      ? null
      : AuthUser(uid: user.uid, email: user.email ?? '');

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
```

- [ ] **Step 6: 로그인 화면을 구현한다**

`mobile/lib/features/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/sync/auth_service.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUpMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해 주세요');
      return;
    }
    if (_signUpMode && password.length < 6) {
      setState(() => _error = authErrorMessage('weak-password'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUpMode) {
        await widget.authService.signUp(email, password);
      } else {
        await widget.authService.signIn(email, password);
      }
      // 성공하면 AuthGate가 인증 스트림을 보고 화면을 바꾼다.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '로그인에 실패했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? AppColors.ink : AppColors.inkTertiary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('English Helper',
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),
                const Text(
                  '저장한 단어를 모든 기기에서 보려면 로그인하세요.',
                  style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  _tab('로그인', !_signUpMode,
                      () => setState(() { _signUpMode = false; _error = null; })),
                  _tab('회원가입', _signUpMode,
                      () => setState(() { _signUpMode = true; _error = null; })),
                ]),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '이메일'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '비밀번호'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_signUpMode ? '가입하고 시작하기' : '로그인'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 20,
                  child: Text(
                    _error ?? '',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFCC5C43)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

> `AppColors.surface` / `AppColors.ink` / `AppColors.inkSecondary` / `AppColors.inkTertiary`는 `theme/app_theme.dart`에 이미 있는 이름이다. 실제 파일의 이름과 다르면 그쪽에 맞춘다.

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test test/features/auth/login_screen_test.dart`
Expected: PASS — 5개

- [ ] **Step 8: 게이트를 만든다**

`mobile/lib/features/auth/auth_gate.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/sync/auth_service.dart';
import 'login_screen.dart';

/// 인증 상태에 따라 로그인 화면과 앱 본체를 가른다.
/// 앱은 로그인이 필수다 — 미로그인 상태로는 아무것도 할 수 없다.
class AuthGate extends StatelessWidget {
  final AuthService authService;
  final Widget child;

  const AuthGate({super.key, required this.authService, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return LoginScreen(authService: authService);
        }
        return child;
      },
    );
  }
}
```

- [ ] **Step 9: main.dart와 app.dart를 배선한다**

`mobile/lib/main.dart`를 교체한다:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';
import 'data/study_timer_repository.dart';
import 'data/sync/auth_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(),
        ),
        Provider<AuthService>(create: (_) => FirebaseAuthService()),
      ],
      child: const EnglishHelperApp(),
    ),
  );
}
```

`mobile/lib/app.dart`의 `EnglishHelperApp.build`에서 `home:`을 게이트로 감싼다:

```dart
      home: Builder(
        builder: (context) => AuthGate(
          authService: context.read<AuthService>(),
          child: const _RootShell(),
        ),
      ),
```

`app.dart` 상단에 import를 추가한다:

```dart
import 'package:provider/provider.dart';

import 'data/sync/auth_service.dart';
import 'features/auth/auth_gate.dart';
```

- [ ] **Step 10: 기존 테스트를 고친다**

Run: `cd mobile && flutter test`

`main_test.dart`가 `EnglishHelperApp`을 직접 띄운다면 `AuthService` 프로바이더가 없어 실패한다. `FakeAuthService`(Step 3의 것과 같은 모양, `currentUser`를 미리 채운 것)를 `Provider<AuthService>.value`로 감싸 넣는다.

Expected: PASS — 전부

- [ ] **Step 11: 실기기/시뮬레이터에서 확인한다**

Run: `cd mobile && flutter run`

기대:
- 앱이 로그인 화면으로 시작한다
- Task 5에서 만든 계정으로 로그인하면 홈 화면으로 넘어간다
- 앱을 완전히 종료했다 다시 열면 로그인 화면 없이 바로 홈으로 간다 (세션 복원)

- [ ] **Step 12: 커밋**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/firebase_options.dart mobile/ios/Runner/GoogleService-Info.plist mobile/lib/data/sync/auth_service.dart mobile/lib/features/auth/ mobile/lib/main.dart mobile/lib/app.dart mobile/test/
git commit -m "feat: add Firebase auth and login gate to the app"
```

---

## Task 14: 앱 병합 규칙 (순수 함수)

**Files:**
- Create: `mobile/lib/data/sync/merge.dart`
- Test: `mobile/test/data/sync/merge_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `class SyncRecord { final String id; final String updatedAt; final String? syncedAt; final Map<String, Object?> data; }`
  - `class MergePlan { final List<SyncRecord> toWriteLocal; final List<String> toDeleteLocal; final List<SyncRecord> toPush; }`
  - `MergePlan planMerge({required List<SyncRecord> local, required List<SyncRecord> remote})`

확장의 `cloud/merge.js`와 **글자 그대로 같은 규칙**이다. 두 구현이 갈라지면 기기마다 다른 결과가 나오므로, 테스트 케이스도 `test/merge.test.js`와 1:1로 맞춘다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`mobile/test/data/sync/merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper/data/sync/merge.dart';

const t1 = '2026-08-01T00:00:00.000Z';
const t2 = '2026-08-02T00:00:00.000Z';

SyncRecord local(String id, String updated, String? synced) =>
    SyncRecord(id: id, updatedAt: updated, syncedAt: synced, data: {'id': id});

SyncRecord remote(String id, String updated) =>
    SyncRecord(id: id, updatedAt: updated, syncedAt: null, data: {'id': id});

void main() {
  test('규칙 1: 미동기 항목은 푸시하고 풀이 건드리지 않는다', () {
    final r = planMerge(local: [local('a', t1, null)], remote: []);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toDeleteLocal, isEmpty);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 1: 서버에 더 오래된 사본이 있어도 미동기가 이긴다', () {
    final r = planMerge(local: [local('a', t2, null)], remote: [remote('a', t1)]);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 2: 로컬이 더 최신이면 푸시', () {
    final r = planMerge(local: [local('a', t2, t1)], remote: [remote('a', t1)]);
    expect(r.toPush.map((e) => e.id), ['a']);
    expect(r.toWriteLocal, isEmpty);
  });

  test('규칙 2: 서버가 더 최신이면 로컬을 덮어쓴다', () {
    final r = planMerge(local: [local('a', t1, t1)], remote: [remote('a', t2)]);
    expect(r.toWriteLocal.map((e) => e.id), ['a']);
    expect(r.toPush, isEmpty);
  });

  test('규칙 2: 동률이면 서버가 이긴다', () {
    // 기기 시계 오차로 서로를 무한히 덮어쓰는 것을 막는다.
    final r = planMerge(local: [local('a', t1, t1)], remote: [remote('a', t1)]);
    expect(r.toWriteLocal.map((e) => e.id), ['a']);
    expect(r.toPush, isEmpty);
  });

  test('규칙 3: 서버에만 있으면 로컬에 넣는다', () {
    final r = planMerge(local: [], remote: [remote('b', t1)]);
    expect(r.toWriteLocal.map((e) => e.id), ['b']);
    expect(r.toDeleteLocal, isEmpty);
  });

  test('규칙 4: 올린 적 있는데 서버에 없으면 다른 기기에서 삭제된 것이다', () {
    final r = planMerge(local: [local('c', t1, t1)], remote: []);
    expect(r.toDeleteLocal, ['c']);
    expect(r.toPush, isEmpty);
  });

  test('네 규칙이 함께 동작한다', () {
    final r = planMerge(
      local: [local('unsynced', t2, null), local('older', t1, t1), local('gone', t1, t1)],
      remote: [remote('older', t2), remote('new', t1)],
    );
    expect(r.toPush.map((e) => e.id), ['unsynced']);
    expect(r.toWriteLocal.map((e) => e.id).toList()..sort(), ['new', 'older']);
    expect(r.toDeleteLocal, ['gone']);
  });

  test('양쪽이 비어 있으면 아무것도 하지 않는다', () {
    final r = planMerge(local: [], remote: []);
    expect(r.toWriteLocal, isEmpty);
    expect(r.toDeleteLocal, isEmpty);
    expect(r.toPush, isEmpty);
  });

  test('원격 레코드를 통째로 toWriteLocal에 싣는다', () {
    final doc = SyncRecord(
      id: 'a', updatedAt: t2, syncedAt: null,
      data: {'id': 'a', 'word': 'hi', 'review_count': 3},
    );
    final r = planMerge(local: [], remote: [doc]);
    expect(r.toWriteLocal.single.data, doc.data);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/data/sync/merge_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../data/sync/merge.dart'`

- [ ] **Step 3: 병합 함수를 구현한다**

`mobile/lib/data/sync/merge.dart`:

```dart
/// 설계 문서 §7.3의 병합 규칙. 순수 함수다 — DB도 네트워크도 건드리지 않는다.
/// 확장의 cloud/merge.js와 같은 규칙이며, 두 구현이 갈라지면 기기마다
/// 다른 결과가 나온다.

class SyncRecord {
  final String id;
  final String updatedAt;
  final String? syncedAt;
  final Map<String, Object?> data;

  const SyncRecord({
    required this.id,
    required this.updatedAt,
    required this.syncedAt,
    required this.data,
  });
}

class MergePlan {
  final List<SyncRecord> toWriteLocal;
  final List<String> toDeleteLocal;
  final List<SyncRecord> toPush;

  const MergePlan({
    required this.toWriteLocal,
    required this.toDeleteLocal,
    required this.toPush,
  });
}

MergePlan planMerge({
  required List<SyncRecord> local,
  required List<SyncRecord> remote,
}) {
  final remoteById = {for (final r in remote) r.id: r};
  final localIds = {for (final l in local) l.id};

  final toWriteLocal = <SyncRecord>[];
  final toDeleteLocal = <String>[];
  final toPush = <SyncRecord>[];

  for (final item in local) {
    // 규칙 1 — 아직 안 올라간 항목은 서버에 없는 게 당연하다. 절대 덮지 않는다.
    if (item.syncedAt == null) {
      toPush.add(item);
      continue;
    }
    final server = remoteById[item.id];
    if (server == null) {
      // 규칙 4 — 올린 적 있는데 서버에 없다 = 다른 기기에서 삭제됐다.
      toDeleteLocal.add(item.id);
      continue;
    }
    // 규칙 2 — 늦은 쪽이 이긴다. 동률이면 서버.
    if (item.updatedAt.compareTo(server.updatedAt) > 0) {
      toPush.add(item);
    } else {
      toWriteLocal.add(server);
    }
  }

  // 규칙 3 — 서버에만 있으면 로컬에 넣는다.
  for (final server in remote) {
    if (!localIds.contains(server.id)) toWriteLocal.add(server);
  }

  return MergePlan(
    toWriteLocal: toWriteLocal,
    toDeleteLocal: toDeleteLocal,
    toPush: toPush,
  );
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test test/data/sync/merge_test.dart`
Expected: PASS — 10개

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/data/sync/merge.dart mobile/test/data/sync/merge_test.dart
git commit -m "feat: add LWW merge rules to the app"
```

---

## Task 15: 앱 동기화 서비스

**Files:**
- Create: `mobile/lib/data/sync/sync_service.dart`
- Test: `mobile/test/data/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `planMerge`/`SyncRecord` (Task 14), `LearningRepository` (Task 12), `StudyTimerRepository`, `AuthService` (Task 13)
- Produces:
  - `abstract class RemoteStore` — `Future<List<Map<String, Object?>>> list(String uid, String collection)`, `Future<void> write(String uid, String collection, String docId, Map<String, Object?> data)`, `Future<void> delete(String uid, String collection, String docId)`
  - `class FirestoreRemoteStore implements RemoteStore`
  - `class SyncService extends ChangeNotifier` — `Future<SyncResult> syncNow(String uid)`, `Future<SyncResult> signOut(String uid, {bool force = false})`, `Future<void> onSignedIn(String uid)`, `String? get lastSyncAt`, `int get pending`
  - `class SyncResult { final bool ok; final int pending; }`

> 이 태스크는 `words`/`sentences`만 다룬다. `study_sessions`/`weekly_goals`는 `StudyTimerRepository` 쪽 배선이 함께 필요해 Task 17에서 같은 구조로 확장한다.

`RemoteStore`를 인터페이스로 둔 이유는 테스트 때문이다. `cloud_firestore`는 위젯 테스트에서 초기화할 수 없으므로 인메모리 대역으로 갈아끼운다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`mobile/test/data/sync/sync_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper/data/models/word.dart';
import 'package:english_helper/data/repository.dart';
import 'package:english_helper/data/sync/sync_service.dart';

class InMemoryRemoteStore implements RemoteStore {
  final Map<String, Map<String, Map<String, Object?>>> docs = {};
  int writeCount = 0;
  Object? throwOnWrite;

  String _key(String uid, String collection) => '$uid/$collection';

  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async =>
      (docs[_key(uid, collection)] ?? {}).values.toList();

  @override
  Future<void> write(String uid, String collection, String docId,
      Map<String, Object?> data) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    writeCount++;
    docs.putIfAbsent(_key(uid, collection), () => {})[docId] = data;
  }

  @override
  Future<void> delete(String uid, String collection, String docId) async {
    docs[_key(uid, collection)]?.remove(docId);
  }
}

Word makeWord(String id, {required String updatedAt, String? syncedAt}) => Word(
      id: id, word: 'w-$id', platform: 'youtube', contentTitle: 'T',
      contentId: 'v1', timestamp: 0, savedAt: updatedAt,
      updatedAt: updatedAt, syncedAt: syncedAt,
    );

void main() {
  const t1 = '2026-08-01T00:00:00.000Z';
  const t2 = '2026-08-02T00:00:00.000Z';

  late LocalSQLiteRepository repo;
  late InMemoryRemoteStore remote;
  late SyncService sync;

  setUp(() async {
    // openTestDb / fakePrefs는 repository_test.dart와 같은 헬퍼를 쓴다.
    repo = LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs);
    remote = InMemoryRemoteStore();
    sync = SyncService(repository: repo, remote: remote, getPrefs: fakePrefs);
  });

  test('미동기 항목을 업로드하고 syncedAt을 채운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));

    final result = await sync.syncNow('u1');

    expect(result.ok, isTrue);
    expect(remote.docs['u1/words']!.containsKey('w1'), isTrue);
    expect((await repo.getWords()).single.syncedAt, isNotNull);
  });

  test('업로드하는 문서에 synced_at을 넣지 않는다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');

    expect(remote.docs['u1/words']!['w1']!.containsKey('synced_at'), isFalse,
        reason: 'synced_at은 기기별 사실이라 서버에 두면 서로 덮어쓴다');
    expect(remote.docs['u1/words']!['w1']!['updated_at'], t1);
  });

  test('서버에만 있는 항목을 내려받는다', () async {
    remote.docs['u1/words'] = {
      'w9': {'id': 'w9', 'word': 'remote', 'platform': 'netflix',
             'content_title': 'T', 'content_id': 'c', 'timestamp': 0.0,
             'saved_at': t1, 'review_count': 0, 'review_level': 0,
             'updated_at': t1},
    };

    await sync.syncNow('u1');

    final words = await repo.getWords();
    expect(words.map((w) => w.id), ['w9']);
    expect(words.single.syncedAt, isNotNull);
  });

  test('서버에서 사라진 동기화 항목은 로컬에서도 지운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');
    remote.docs['u1/words']!.remove('w1');

    await sync.syncNow('u1');

    expect(await repo.getWords(), isEmpty);
  });

  test('미동기 항목은 풀에서 삭제되지 않는다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t2));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.syncNow('u1');

    expect(result.ok, isFalse);
    expect((await repo.getWords()).map((w) => w.id), ['w1']);
    expect(result.pending, 1);
  });

  test('삭제 큐를 서버에 반영하고 큐를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.syncNow('u1');
    await repo.deleteWord('w1');

    await sync.syncNow('u1');

    expect(remote.docs['u1/words']!.containsKey('w1'), isFalse);
    expect(await repo.getSyncQueue(), isEmpty);
  });

  test('다른 계정으로 로그인하면 로컬 캐시를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u2');

    expect(await repo.getWords(), isEmpty,
        reason: 'B 계정이 A 계정의 단어를 보면 안 된다');
  });

  test('같은 계정으로 다시 로그인하면 캐시를 유지한다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u1');

    expect((await repo.getWords()).length, 1);
  });

  test('미동기 항목이 남으면 로그아웃을 거부한다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.signOut('u1');

    expect(result.ok, isFalse);
    expect(result.pending, 1);
    expect((await repo.getWords()).length, 1, reason: '데이터가 남아 있어야 한다');
  });

  test('force면 미동기 항목이 있어도 로그아웃하고 캐시를 비운다', () async {
    await repo.saveWord(makeWord('w1', updatedAt: t1));
    remote.throwOnWrite = Exception('offline');

    final result = await sync.signOut('u1', force: true);

    expect(result.ok, isTrue);
    expect(await repo.getWords(), isEmpty);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/data/sync/sync_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../data/sync/sync_service.dart'`

- [ ] **Step 3: 동기화 서비스를 구현한다**

`mobile/lib/data/sync/sync_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sentence.dart';
import '../models/word.dart';
import '../repository.dart';
import 'merge.dart';

/// Firestore 접근을 인터페이스 뒤에 둔다 — cloud_firestore는 위젯 테스트에서
/// 초기화할 수 없어 인메모리 대역으로 갈아끼워야 한다.
abstract class RemoteStore {
  Future<List<Map<String, Object?>>> list(String uid, String collection);
  Future<void> write(
      String uid, String collection, String docId, Map<String, Object?> data);
  Future<void> delete(String uid, String collection, String docId);
}

class FirestoreRemoteStore implements RemoteStore {
  final FirebaseFirestore _db;
  FirestoreRemoteStore({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid, String collection) =>
      _db.collection('users').doc(uid).collection(collection);

  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async {
    final snap = await _col(uid, collection).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  @override
  Future<void> write(String uid, String collection, String docId,
          Map<String, Object?> data) =>
      _col(uid, collection).doc(docId).set(data);

  @override
  Future<void> delete(String uid, String collection, String docId) =>
      _col(uid, collection).doc(docId).delete();
}

class SyncResult {
  final bool ok;
  final int pending;
  const SyncResult({required this.ok, required this.pending});
}

class SyncService extends ChangeNotifier {
  static const _lastSyncKey = 'sync_last_at';
  static const _lastUidKey = 'sync_last_uid';

  final LearningRepository repository;
  final RemoteStore remote;
  final Future<SharedPreferences> Function() _getPrefs;

  String? _lastSyncAt;
  int _pending = 0;

  SyncService({
    required this.repository,
    required this.remote,
    Future<SharedPreferences> Function()? getPrefs,
  }) : _getPrefs = getPrefs ?? SharedPreferences.getInstance;

  String? get lastSyncAt => _lastSyncAt;
  int get pending => _pending;

  /// 서버에 올릴 형태 — synced_at은 기기별 사실이라 서버에 두지 않는다.
  Map<String, Object?> _forRemote(Map<String, Object?> map) {
    final copy = Map<String, Object?>.from(map);
    copy.remove('synced_at');
    return copy;
  }

  SyncRecord _recordOf(Map<String, Object?> map) => SyncRecord(
        id: map['id'] as String,
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ??
            '',
        syncedAt: map['synced_at'] as String?,
        data: map,
      );

  Future<int> _countPending() async {
    final words = await repository.getWords();
    final sentences = await repository.getSentences();
    final queue = await repository.getSyncQueue();
    return words.where((w) => w.syncedAt == null).length +
        sentences.where((s) => s.syncedAt == null).length +
        queue.length;
  }

  /// 로그인 직후 호출한다. 다른 계정이면 이전 계정의 로컬 캐시를 비운다
  /// — B 계정이 A 계정의 단어를 보는 사고를 막는다 (설계 §4.4).
  Future<void> onSignedIn(String uid) async {
    final prefs = await _getPrefs();
    final lastUid = prefs.getString(_lastUidKey);
    if (lastUid != null && lastUid != uid) {
      await repository.clearAllLocalData();
      await prefs.remove(_lastSyncKey);
      _lastSyncAt = null;
    }
    await prefs.setString(_lastUidKey, uid);
    await syncNow(uid);
  }

  Future<SyncResult> syncNow(String uid) async {
    var ok = true;
    try {
      await _pushDeletes(uid);
      await _syncWords(uid);
      await _syncSentences(uid);

      final prefs = await _getPrefs();
      _lastSyncAt = DateTime.now().toIso8601String();
      await prefs.setString(_lastSyncKey, _lastSyncAt!);
    } catch (err) {
      // 푸시 실패는 사용자에게 알리지 않는다 — 로컬 저장은 이미 성공했다.
      // 미동기 개수로만 드러낸다 (설계 §10.2).
      debugPrint('[Sync] failed: $err');
      ok = false;
    }
    _pending = await _countPending();
    notifyListeners();
    return SyncResult(ok: ok, pending: _pending);
  }

  Future<void> _pushDeletes(String uid) async {
    for (final entry in await repository.getSyncQueue()) {
      await remote.delete(uid, entry.entity, entry.docId);
      await repository.clearSyncQueueEntry(entry.entity, entry.docId);
    }
  }

  Future<void> _syncWords(String uid) async {
    final local = (await repository.getWords()).map((w) => w.toMap()).toList();
    final remoteDocs = await remote.list(uid, 'words');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'words', rec.id, _forRemote(rec.data));
      await repository.saveWord(
        Word.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final rec in plan.toWriteLocal) {
      await repository.saveWord(
        Word.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final id in plan.toDeleteLocal) {
      await repository.deleteWord(id);
      // 다른 기기의 삭제를 따라간 것이지 우리가 삭제한 게 아니다.
      await repository.clearSyncQueueEntry('words', id);
    }
  }

  Future<void> _syncSentences(String uid) async {
    final local =
        (await repository.getSentences()).map((s) => s.toMap()).toList();
    final remoteDocs = await remote.list(uid, 'sentences');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'sentences', rec.id, _forRemote(rec.data));
      await repository.saveSentence(
        Sentence.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final rec in plan.toWriteLocal) {
      await repository.saveSentence(
        Sentence.fromMap({...rec.data, 'synced_at': now}),
      );
    }
    for (final id in plan.toDeleteLocal) {
      await repository.deleteSentence(id);
      await repository.clearSyncQueueEntry('sentences', id);
    }
  }

  /// 로그아웃 전에 밀린 것을 먼저 밀어낸다. 남으면 거부한다 — 로그아웃은
  /// 로컬 캐시를 비우므로 미동기 항목이 유실된다 (설계 §4.4).
  Future<SyncResult> signOut(String uid, {bool force = false}) async {
    final result = await syncNow(uid);
    if (result.pending > 0 && !force) {
      return SyncResult(ok: false, pending: result.pending);
    }
    await repository.clearAllLocalData();
    final prefs = await _getPrefs();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_lastUidKey);
    _lastSyncAt = null;
    _pending = 0;
    notifyListeners();
    return const SyncResult(ok: true, pending: 0);
  }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test test/data/sync/sync_service_test.dart`
Expected: PASS — 10개

`saveWord`가 `updated_at`을 다시 밀어버려 "업로드 직후 다시 미동기"가 되는 문제가 나면, `repository.saveWord`는 전달받은 맵을 그대로 쓰고 시각을 덮지 않아야 한다(Task 12는 `copyWith` 경로에서만 시각을 갱신하도록 되어 있다). `saveWord` 구현이 `updatedAt`을 건드리고 있는지 확인한다.

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/data/sync/sync_service.dart mobile/test/data/sync/sync_service_test.dart
git commit -m "feat: add app sync service with push, pull, and account switching"
```

---

## Task 16: 앱 설정 화면 — 계정 섹션과 동기화 배선

**Files:**
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/app.dart`
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Test: `mobile/test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SyncService` (Task 15), `AuthService` (Task 13)
- Produces: 없음 (UI 종단)

- [ ] **Step 1: SyncService를 프로바이더로 올린다**

`mobile/lib/main.dart`의 `providers` 목록을 교체한다. `SyncService`는 `LearningRepository`에 의존하므로 `ChangeNotifierProxyProvider`가 아니라 `ChangeNotifierProvider`에 `context.read`로 주입한다:

```dart
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(),
        ),
        Provider<AuthService>(create: (_) => FirebaseAuthService()),
        ChangeNotifierProvider<SyncService>(
          create: (context) => SyncService(
            repository: context.read<LearningRepository>(),
            remote: FirestoreRemoteStore(),
          ),
        ),
      ],
```

import를 추가한다:

```dart
import 'data/sync/sync_service.dart';
```

- [ ] **Step 2: 앱 진입·포그라운드 복귀 시 동기화한다**

`mobile/lib/app.dart`의 `_RootShellState`를 교체한다:

```dart
class _RootShellState extends State<_RootShell> with WidgetsBindingObserver {
  int _index = 0;

  // Order matches the design mockup's AppNav.dc.html exactly:
  // 홈 / 플래시카드 / 타이머 / 가져오기 / 설정.
  static const _screens = [
    HomeScreen(),
    FlashcardScreen(),
    TimerScreen(),
    ImportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _sync() {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;
    context.read<SyncService>().syncNow(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
```

`app.dart`에 import를 추가한다:

```dart
import 'data/sync/sync_service.dart';
```

- [ ] **Step 3: 로그인 직후 계정 전환 검사를 태운다**

`mobile/lib/features/auth/auth_gate.dart`의 `builder`에서, 로그인 상태로 넘어갈 때 `onSignedIn`을 부른다. `StreamBuilder`의 `snapshot.data != null` 분기를 교체한다:

```dart
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: authService);
        }
        // 계정 전환이면 이전 계정의 로컬 캐시를 비운다. 빌드 중에
        // 저장소를 건드리지 않도록 프레임 뒤로 미룬다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<SyncService>().onSignedIn(user.uid);
        });
        return child;
```

import를 추가한다:

```dart
import 'package:provider/provider.dart';

import '../../data/sync/sync_service.dart';
```

- [ ] **Step 4: 실패하는 테스트를 쓴다**

`mobile/test/features/settings/settings_screen_test.dart`에 추가한다. 기존 파일의 프로바이더 래핑 헬퍼에 `AuthService`와 `SyncService`를 더해야 컴파일된다.

```dart
  testWidgets('계정 섹션에 로그인한 이메일을 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c');
    expect(find.text('a@b.c'), findsOneWidget);
  });

  testWidgets('마지막 동기화 시각이 없으면 안내를 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c', lastSyncAt: null);
    expect(find.text('아직 동기화 안 됨'), findsOneWidget);
  });

  testWidgets('미동기 항목 개수를 보여준다', (tester) async {
    await pumpSettings(tester, email: 'a@b.c', pending: 3);
    expect(find.text('3개 대기 중'), findsOneWidget);
  });

  testWidgets('지금 동기화를 누르면 syncNow를 호출한다', (tester) async {
    final sync = await pumpSettings(tester, email: 'a@b.c');
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    expect(sync.syncNowCalls, 1);
  });
```

`pumpSettings`와 두 가짜는 같은 파일의 `main()` 위에 둔다:

```dart
class _FakeAuthService implements AuthService {
  @override
  AuthUser? currentUser;
  _FakeAuthService(String email)
      : currentUser = AuthUser(uid: 'u1', email: email);

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> signOut() async { currentUser = null; }
}

/// SyncService는 ChangeNotifier라 상속해서 동작만 갈아끼우는 편이 짧다.
class _FakeSyncService extends SyncService {
  int syncNowCalls = 0;
  final String? _lastSync;
  final int _pending;

  _FakeSyncService({String? lastSyncAt, int pending = 0})
      : _lastSync = lastSyncAt,
        _pending = pending,
        super(
          repository: LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs),
          remote: _NullRemoteStore(),
          getPrefs: fakePrefs,
        );

  @override
  String? get lastSyncAt => _lastSync;
  @override
  int get pending => _pending;

  @override
  Future<SyncResult> syncNow(String uid) async {
    syncNowCalls++;
    return SyncResult(ok: true, pending: _pending);
  }
}

class _NullRemoteStore implements RemoteStore {
  @override
  Future<List<Map<String, Object?>>> list(String uid, String collection) async => [];
  @override
  Future<void> write(String uid, String c, String id, Map<String, Object?> d) async {}
  @override
  Future<void> delete(String uid, String c, String id) async {}
}

Future<_FakeSyncService> pumpSettings(
  WidgetTester tester, {
  required String email,
  String? lastSyncAt,
  int pending = 0,
}) async {
  final sync = _FakeSyncService(lastSyncAt: lastSyncAt, pending: pending);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(openDb: openTestDb, getPrefs: fakePrefs),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(openDb: openTestDb, getPrefs: fakePrefs),
        ),
        Provider<AuthService>.value(value: _FakeAuthService(email)),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return sync;
}
```

`openTestDb`/`fakePrefs`는 이 파일이 기존에 쓰던 헬퍼다. 없으면 `repository_test.dart`에서 가져온다.

- [ ] **Step 5: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — `find.text('a@b.c')`가 아무것도 못 찾는다

- [ ] **Step 6: 계정 섹션을 구현한다**

`mobile/lib/features/settings/settings_screen.dart`의 설정 항목 목록 맨 위(모국어 항목 앞)에 계정 카드를 추가한다. 기존 카드/행 위젯(`_SettingsRow` 등)의 실제 이름을 확인해 맞춘다.

```dart
  Widget _accountSection(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sync = context.watch<SyncService>();
    final email = auth.currentUser?.email ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('계정',
            style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 16)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(email, style: const TextStyle(fontSize: 14))),
          Text(
            sync.pending > 0
                ? '${sync.pending}개 대기 중'
                : _formatSyncTime(sync.lastSyncAt),
            style: TextStyle(
              fontSize: 13,
              color: sync.pending > 0
                  ? AppColors.accent
                  : AppColors.inkTertiary,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          TextButton(
            onPressed: () {
              final uid = auth.currentUser?.uid;
              if (uid != null) sync.syncNow(uid);
            },
            child: const Text('지금 동기화'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _confirmSignOut(context, auth, sync),
            child: const Text('로그아웃'),
          ),
        ]),
      ],
    );
  }

  static String _formatSyncTime(String? iso) {
    if (iso == null) return '아직 동기화 안 됨';
    final d = DateTime.parse(iso);
    return '${d.hour}:${d.minute.toString().padLeft(2, '0')} 동기화됨';
  }

  Future<void> _confirmSignOut(
      BuildContext context, AuthService auth, SyncService sync) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    var result = await sync.signOut(uid);
    if (!result.ok) {
      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            '${result.pending}개 항목이 아직 저장되지 않았어요. '
            '로그아웃하면 사라집니다. 계속할까요?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('로그아웃')),
          ],
        ),
      );
      if (proceed != true) return;
      result = await sync.signOut(uid, force: true);
    }
    await auth.signOut();
  }
```

`build`의 항목 목록 맨 위에 `_accountSection(context)`와 간격을 넣고, 파일 상단에 import를 추가한다:

```dart
import '../../data/sync/auth_service.dart';
import '../../data/sync/sync_service.dart';
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test`
Expected: PASS — 전부

- [ ] **Step 8: 확장 → 앱 왕복을 실기기에서 확인한다**

Run: `cd mobile && flutter run`

같은 계정으로 확장과 앱 양쪽에 로그인한 상태에서:

1. **확장 → 앱**: YouTube에서 단어를 하나 저장한다. 앱을 백그라운드로 보냈다 다시 연다. 홈 화면에 그 단어가 보인다
2. **앱 → 확장**: 앱에서 단어를 하나 삭제한다. YouTube 탭에서 라이브러리 패널을 닫았다 다시 연다. 그 단어가 사라져 있다
3. **오프라인 저장**: 기기를 비행기 모드로 두고 앱에서 카드를 하나 복습한다. 설정 화면에 "1개 대기 중"이 보인다. 비행기 모드를 풀고 "지금 동기화"를 누르면 시각 표시로 바뀐다
4. **로그아웃 가드**: 비행기 모드에서 복습한 뒤 로그아웃을 누르면 "1개 항목이 아직 저장되지 않았어요" 다이얼로그가 뜬다
5. **계정 전환**: 로그아웃하고 다른 이메일로 새로 가입한다. 홈 화면이 비어 있다 (이전 계정 데이터가 보이면 안 된다)

- [ ] **Step 9: 커밋**

```bash
git add mobile/lib/main.dart mobile/lib/app.dart mobile/lib/features/auth/auth_gate.dart mobile/lib/features/settings/settings_screen.dart mobile/test/features/settings/settings_screen_test.dart
git commit -m "feat: add account section and sync wiring to app settings"
```

---

## Task 17: 타이머 데이터 동기화

**Files:**
- Modify: `mobile/lib/data/models/study_session.dart`
- Modify: `mobile/lib/data/models/weekly_goal.dart`
- Modify: `mobile/lib/data/study_timer_repository.dart`
- Modify: `mobile/lib/data/sync/sync_service.dart`
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/data/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: Task 15의 `SyncService`, `RemoteStore`, `planMerge`
- Produces:
  - `StudySession`/`WeeklyGoal`에 `updatedAt`/`syncedAt` 필드
  - `StudyTimerRepository`에 `Future<List<StudySession>> getAllSessions()`, `Future<List<WeeklyGoal>> getAllGoals()`, `Future<void> upsertSession(StudySession)`, `Future<void> upsertGoal(WeeklyGoal)`, `Future<void> clearAllLocalData()`
  - `SyncService`가 `timerRepository`를 받아 `study_sessions`/`weekly_goals`도 동기화

`study_sessions`와 `weekly_goals`는 앱 전용 데이터라 확장에는 대응 코드가 없다. 여기서 동기화하는 대상은 **기기 간**(폰 ↔ 태블릿)이다. 삭제 경로가 없는 append-only 데이터라 `sync_queue`는 쓰지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`mobile/test/data/sync/sync_service_test.dart`의 `main()` 안에 추가한다. `setUp`에서 `SyncService` 생성에 `timerRepository`를 넘기도록 함께 고친다:

```dart
  test('타이머 세션을 업로드하고 syncedAt을 채운다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));

    await sync.syncNow('u1');

    expect(remote.docs['u1/study_sessions']!.containsKey('ss1'), isTrue);
    expect((await timerRepo.getAllSessions()).single.syncedAt, isNotNull);
  });

  test('서버에만 있는 주간 목표를 내려받는다', () async {
    remote.docs['u1/weekly_goals'] = {
      'g1': {'id': 'g1', 'target_minutes': 300,
             'effective_from': t1, 'created_at': t1, 'updated_at': t1},
    };

    await sync.syncNow('u1');

    expect((await timerRepo.getAllGoals()).map((g) => g.id), ['g1']);
  });

  test('타이머 문서에도 synced_at을 올리지 않는다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));

    await sync.syncNow('u1');

    expect(remote.docs['u1/study_sessions']!['ss1']!.containsKey('synced_at'),
        isFalse);
  });

  test('계정 전환 시 타이머 데이터도 비운다', () async {
    await timerRepo.upsertSession(StudySession(
      id: 'ss1',
      startedAt: DateTime.parse(t1),
      endedAt: DateTime.parse(t1).add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      savedAt: t1,
      updatedAt: t1,
    ));
    await sync.onSignedIn('u1');

    await sync.onSignedIn('u2');

    expect(await timerRepo.getAllSessions(), isEmpty);
  });
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `cd mobile && flutter test test/data/sync/sync_service_test.dart`
Expected: FAIL — `The named parameter 'updatedAt' isn't defined` (StudySession)

- [ ] **Step 3: 타이머 모델에 필드를 추가한다**

`mobile/lib/data/models/study_session.dart`와 `mobile/lib/data/models/weekly_goal.dart` 양쪽에 Task 12 Step 3과 같은 다섯 군데 변경을 한다 — 필드 선언, 생성자(`required this.updatedAt,` / `this.syncedAt,`), `toMap`(`'updated_at'`, `'synced_at'`), `fromMap`(폴백은 `study_session`이 `saved_at`, `weekly_goal`이 `created_at`), `copyWith`.

`StudySession.fromMap`의 폴백:

```dart
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
```

`WeeklyGoal.fromMap`의 폴백:

```dart
        updatedAt: (map['updated_at'] as String?) ??
            (map['created_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
```

- [ ] **Step 4: 타이머 저장소에 동기화용 메서드를 추가한다**

`mobile/lib/data/study_timer_repository.dart`의 `abstract class StudyTimerRepository`에 추가:

```dart
  Future<List<StudySession>> getAllSessions();
  Future<List<WeeklyGoal>> getAllGoals();
  Future<void> upsertSession(StudySession session);
  Future<void> upsertGoal(WeeklyGoal goal);
  Future<void> clearAllLocalData();
```

`LocalStudyTimerRepository`에 구현:

```dart
  @override
  Future<List<StudySession>> getAllSessions() async {
    final db = await _database;
    final rows = await db.query('study_sessions', orderBy: 'started_at DESC');
    return rows.map(StudySession.fromMap).toList();
  }

  @override
  Future<List<WeeklyGoal>> getAllGoals() async {
    final db = await _database;
    final rows = await db.query('weekly_goals', orderBy: 'effective_from DESC');
    return rows.map(WeeklyGoal.fromMap).toList();
  }

  @override
  Future<void> upsertSession(StudySession session) async {
    final db = await _database;
    await db.insert('study_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> upsertGoal(WeeklyGoal goal) async {
    final db = await _database;
    await db.insert('weekly_goals', goal.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> clearAllLocalData() async {
    final db = await _database;
    await db.delete('study_sessions');
    await db.delete('weekly_goals');
    notifyListeners();
  }
```

기존 `endSession`과 `setWeeklyGoal`이 행을 만들 때 `updatedAt`을 현재 시각으로, `syncedAt`을 `null`로 채우게 고친다 — 그래야 새 기록이 업로드 대상이 된다.

- [ ] **Step 5: SyncService를 확장한다**

`mobile/lib/data/sync/sync_service.dart`에 `timerRepository`를 받는다. 생성자와 필드:

```dart
  final StudyTimerRepository timerRepository;
```

```dart
  SyncService({
    required this.repository,
    required this.timerRepository,
    required this.remote,
    Future<SharedPreferences> Function()? getPrefs,
  }) : _getPrefs = getPrefs ?? SharedPreferences.getInstance;
```

import를 추가한다:

```dart
import '../models/study_session.dart';
import '../models/weekly_goal.dart';
import '../study_timer_repository.dart';
```

`_syncSentences` 아래에 타이머용 메서드를 추가한다. 삭제 경로가 없어 `toDeleteLocal`은 다루지 않는다:

```dart
  Future<void> _syncSessions(String uid) async {
    final local = (await timerRepository.getAllSessions())
        .map((s) => s.toMap())
        .toList();
    final remoteDocs = await remote.list(uid, 'study_sessions');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'study_sessions', rec.id, _forRemote(rec.data));
      await timerRepository
          .upsertSession(StudySession.fromMap({...rec.data, 'synced_at': now}));
    }
    for (final rec in plan.toWriteLocal) {
      await timerRepository
          .upsertSession(StudySession.fromMap({...rec.data, 'synced_at': now}));
    }
    // 세션은 append-only다 — 삭제 경로가 없으므로 toDeleteLocal은 비어 있다.
  }

  Future<void> _syncGoals(String uid) async {
    final local =
        (await timerRepository.getAllGoals()).map((g) => g.toMap()).toList();
    final remoteDocs = await remote.list(uid, 'weekly_goals');
    final plan = planMerge(
      local: local.map(_recordOf).toList(),
      remote: remoteDocs.map(_recordOf).toList(),
    );

    final now = DateTime.now().toIso8601String();
    for (final rec in plan.toPush) {
      await remote.write(uid, 'weekly_goals', rec.id, _forRemote(rec.data));
      await timerRepository
          .upsertGoal(WeeklyGoal.fromMap({...rec.data, 'synced_at': now}));
    }
    for (final rec in plan.toWriteLocal) {
      await timerRepository
          .upsertGoal(WeeklyGoal.fromMap({...rec.data, 'synced_at': now}));
    }
  }
```

`syncNow`의 `try` 블록에 두 호출을 더한다:

```dart
      await _pushDeletes(uid);
      await _syncWords(uid);
      await _syncSentences(uid);
      await _syncSessions(uid);
      await _syncGoals(uid);
```

`_countPending`에 타이머 항목을 더한다:

```dart
  Future<int> _countPending() async {
    final words = await repository.getWords();
    final sentences = await repository.getSentences();
    final sessions = await timerRepository.getAllSessions();
    final goals = await timerRepository.getAllGoals();
    final queue = await repository.getSyncQueue();
    return words.where((w) => w.syncedAt == null).length +
        sentences.where((s) => s.syncedAt == null).length +
        sessions.where((s) => s.syncedAt == null).length +
        goals.where((g) => g.syncedAt == null).length +
        queue.length;
  }
```

`onSignedIn`의 계정 전환 분기와 `signOut`의 캐시 비우기에 타이머 저장소를 더한다 — 두 곳 모두 `await repository.clearAllLocalData();` 다음 줄에:

```dart
      await timerRepository.clearAllLocalData();
```

- [ ] **Step 6: main.dart의 프로바이더를 갱신한다**

Task 16 Step 1의 `SyncService` 생성에 `timerRepository`를 넘긴다:

```dart
        ChangeNotifierProvider<SyncService>(
          create: (context) => SyncService(
            repository: context.read<LearningRepository>(),
            timerRepository: context.read<StudyTimerRepository>(),
            remote: FirestoreRemoteStore(),
          ),
        ),
```

`settings_screen_test.dart`의 `_FakeSyncService` `super(...)` 호출에도 `timerRepository`를 더한다:

```dart
          timerRepository: LocalStudyTimerRepository(
              openDb: openTestDb, getPrefs: fakePrefs),
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `cd mobile && flutter test`
Expected: PASS — 전부

- [ ] **Step 8: 커밋**

```bash
git add mobile/lib/data/models/study_session.dart mobile/lib/data/models/weekly_goal.dart mobile/lib/data/study_timer_repository.dart mobile/lib/data/sync/sync_service.dart mobile/lib/main.dart mobile/test/
git commit -m "feat: sync study sessions and weekly goals across devices"
```

---

## 완료 확인

이 계획이 끝나면 다음이 성립한다:

- [ ] `npm test` — 확장 순수 모듈 40개 테스트 통과
- [ ] `cd mobile && flutter test` — 앱 테스트 전부 통과
- [ ] 확장에서 저장한 단어가 앱에 나타난다
- [ ] 앱에서 지운 단어가 확장에서 사라진다
- [ ] 오프라인에서 저장한 항목이 유실되지 않고 복구 시 올라간다
- [ ] 미동기 항목이 있으면 로그아웃이 확인을 요구한다
- [ ] 계정을 바꾸면 이전 계정 데이터가 보이지 않는다
- [ ] 미로그인 상태에서 자막 오버레이와 스크립트 패널이 정상 동작한다
- [ ] 한 기기에서 기록한 타이머 세션과 주간 목표가 다른 기기에 나타난다

**다음 계획:** 설계 문서 §13의 5단계 — `.sqlite` 내보내기/가져오기 제거, 앱 하단 네비 4탭화, 설정 화면 JSON 내보내기. 위 항목이 전부 확인된 뒤에 착수한다.
