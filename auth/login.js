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
    // 로그인은 이 시점에 이미 성공하고 저장된 상태다. 이 sendMessage를 받는
    // 서비스워커 핸들러는 아직(다음 태스크) 없어서 거부될 수 있는데, 그
    // 실패가 창을 닫는 것까지 막으면 안 된다 — 그래서 별도로 catch한다.
    try {
      await chrome.runtime.sendMessage({ type: 'EH_AUTH_CHANGED' });
    } catch (_) {
      // 수신자가 아직 없음(Task 6에서 해소). 로그인 자체는 이미 끝났으니 무시.
    }
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
