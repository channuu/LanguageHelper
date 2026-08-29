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

test('getValidToken clears auth on refresh failure but preserves saved data', async () => {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'OLD',
    refreshToken: 'R', expiresAt: Date.now() - 1000
  };
  store['eh-words'] = ['word1', 'word2'];
  store['eh-sentences'] = ['sentence1', 'sentence2'];

  globalThis.fetch = async () => jsonResponse({ error: { message: 'TOKEN_EXPIRED' } }, 400);

  assert.equal(await getValidToken(), null);
  assert.equal(store['eh-auth'], undefined);
  assert.deepEqual(store['eh-words'], ['word1', 'word2']);
  assert.deepEqual(store['eh-sentences'], ['sentence1', 'sentence2']);
});

test('getValidToken refreshes a token expiring within 60s margin', async () => {
  store['eh-auth'] = {
    uid: 'u1', email: 'a@b.c', idToken: 'OLD',
    refreshToken: 'R', expiresAt: Date.now() + 30000
  };

  globalThis.fetch = async () => jsonResponse({
    id_token: 'NEW', refresh_token: 'R2', expires_in: '3600', user_id: 'u1'
  });

  assert.equal(await getValidToken(), 'NEW');
  assert.equal(store['eh-auth'].idToken, 'NEW');
  assert.equal(store['eh-auth'].refreshToken, 'R2');
});
