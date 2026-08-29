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
