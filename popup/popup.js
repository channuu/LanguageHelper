'use strict';

(function () {

const $ = id => document.getElementById(id);

// ── 탭 전환 ──────────────────────────────────────────────────────
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    $(btn.dataset.tab).classList.add('active');
  });
});

// ── 유틸 ─────────────────────────────────────────────────────────
function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatTime(sec) {
  if (!sec && sec !== 0) return '';
  return Math.floor(sec / 60) + ':' + String(Math.floor(sec % 60)).padStart(2, '0');
}

// ── 설정 ─────────────────────────────────────────────────────────
const DEFAULT = { enSize: 22, nativeSize: 18, mode: 'both', nativeLang: 'ko' };

async function loadSettings() {
  const res = await chrome.storage.local.get('eh-settings');
  return { ...DEFAULT, ...(res['eh-settings'] || {}) };
}

async function saveSettings(patch) {
  const cur = await loadSettings();
  const next = { ...cur, ...patch };
  await chrome.storage.local.set({ 'eh-settings': next });
  return next;
}

async function sendSettingsToTab(settings) {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tabs[0]) {
    chrome.tabs.sendMessage(tabs[0].id, { type: 'APPLY_SETTINGS', settings }).catch(() => {});
  }
}

function applySettingsUI(s) {
  $('en-size').value = s.enSize;
  $('native-size').value = s.nativeSize;
  $('en-size-val').textContent = s.enSize + 'px';
  $('native-size-val').textContent = s.nativeSize + 'px';
  $('preview-en').style.fontSize = s.enSize + 'px';
  $('preview-ko').style.fontSize = s.nativeSize + 'px';
  $('preview-ko').style.display = s.mode === 'en' ? 'none' : 'block';
  $('native-lang').value = s.nativeLang || 'ko';
  document.querySelectorAll('.mode-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.mode === s.mode);
  });
}

// 설정 이벤트 — debounce helper
function debounce(fn, ms) {
  let timer = null;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), ms);
  };
}

$('en-size').addEventListener('input', debounce(async (e) => {
  const v = parseInt(e.target.value);
  $('en-size-val').textContent = v + 'px';
  $('preview-en').style.fontSize = v + 'px';
  sendSettingsToTab(await saveSettings({ enSize: v }));
}, 300));

$('native-size').addEventListener('input', debounce(async (e) => {
  const v = parseInt(e.target.value);
  $('native-size-val').textContent = v + 'px';
  $('preview-ko').style.fontSize = v + 'px';
  sendSettingsToTab(await saveSettings({ nativeSize: v }));
}, 300));

$('native-lang').addEventListener('change', async (e) => {
  sendSettingsToTab(await saveSettings({ nativeLang: e.target.value }));
});

document.querySelectorAll('.mode-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    const s = await saveSettings({ mode: btn.dataset.mode });
    applySettingsUI(s);
    sendSettingsToTab(s);
  });
});

// ── 오버레이 / 패널 토글 ─────────────────────────────────────────
function sendToTab(msg) {
  chrome.tabs.query({ active: true, currentWindow: true }, tabs => {
    if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, msg);
  });
}

$('toggle-overlay').addEventListener('change', () => {
  sendToTab({ type: 'TOGGLE_OVERLAY' });
});

$('toggle-panel').addEventListener('change', (e) => {
  sendToTab({ type: 'TOGGLE_PANEL', visible: e.target.checked });
});

// ── 데이터 로드 & 렌더 ───────────────────────────────────────────
async function loadData() {
  const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
  const words = (res && res.words) ? res.words : [];
  const sentences = (res && res.sentences) ? res.sentences : [];

  // 단어 목록
  const wordBadge = $('word-count');
  if (words.length) {
    wordBadge.textContent = words.length;
    wordBadge.style.display = 'inline';
  } else {
    wordBadge.style.display = 'none';
  }

  const wordList = $('word-list');
  if (!words.length) {
    wordList.innerHTML = '<div class="empty">저장된 단어가 없습니다.<br>영어 자막의 단어를 클릭해 저장해보세요.</div>';
  } else {
    wordList.innerHTML = words.map(w => `
      <div class="item-card" data-id="${esc(w.id)}" data-type="word">
        <div class="item-main">${esc(w.word)}</div>
        <div class="item-def">${esc(w.definition || '')}</div>
        <div class="item-sub">${esc(w.sentence || '')} <span class="src-badge">${esc(w.platform || '')} ${formatTime(w.timestamp)}</span></div>
        <button class="btn-del" data-id="${esc(w.id)}" data-type="word">×</button>
      </div>`).join('');
  }

  // 문장 목록
  const sentBadge = $('sent-count');
  if (sentences.length) {
    sentBadge.textContent = sentences.length;
    sentBadge.style.display = 'inline';
  } else {
    sentBadge.style.display = 'none';
  }

  const sentList = $('sent-list');
  if (!sentences.length) {
    sentList.innerHTML = '<div class="empty">저장된 문장이 없습니다.<br>스크립트 패널의 + 버튼을 눌러보세요.</div>';
  } else {
    sentList.innerHTML = sentences.map(s => `
      <div class="item-card" data-id="${esc(s.id)}" data-type="sentence">
        <div class="item-main">${esc(s.original)}</div>
        <div class="item-sub">${esc(s.translation || '')} <span class="src-badge">${esc(s.platform || '')} ${formatTime(s.timestamp)}</span></div>
        <button class="btn-del" data-id="${esc(s.id)}" data-type="sentence">×</button>
      </div>`).join('');
  }
}

// 삭제 이벤트 위임
document.addEventListener('click', async (e) => {
  const btn = e.target.closest('.btn-del');
  if (!btn) return;
  const card = btn.closest('.item-card');
  if (card) card.style.opacity = '0.3';
  await chrome.runtime.sendMessage({
    type: 'DELETE_ITEM',
    payload: { type: btn.dataset.type, id: btn.dataset.id }
  });
  loadData();
});

// ── SQLite Export ─────────────────────────────────────────────────
$('btn-export').addEventListener('click', async () => {
  const btn = $('btn-export');
  btn.disabled = true;
  btn.textContent = '내보내는 중...';

  try {
    const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
    const words = (res && res.words) ? res.words : [];
    const sentences = (res && res.sentences) ? res.sentences : [];

    const SQL = await initSqlJs({
      locateFile: f => '../vendor/' + f
    });
    const db = new SQL.Database();

    db.run(`CREATE TABLE words (
      id TEXT PRIMARY KEY,
      word TEXT,
      definition TEXT,
      sentence TEXT,
      translation TEXT,
      platform TEXT,
      content_title TEXT,
      content_id TEXT,
      timestamp REAL,
      saved_at TEXT,
      review_count INTEGER DEFAULT 0,
      next_review_at TEXT
    )`);

    db.run(`CREATE TABLE sentences (
      id TEXT PRIMARY KEY,
      original TEXT,
      translation TEXT,
      platform TEXT,
      content_title TEXT,
      content_id TEXT,
      timestamp REAL,
      saved_at TEXT,
      review_count INTEGER DEFAULT 0,
      next_review_at TEXT
    )`);

    const wordStmt = db.prepare('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)');
    words.forEach(w => wordStmt.run([
      w.id,
      w.word,
      w.definition || '',
      w.sentence || '',
      w.translation || '',
      w.platform || '',
      w.contentTitle || '',
      w.contentId || '',
      w.timestamp || 0,
      w.savedAt || '',
      w.reviewCount || 0,
      w.nextReviewAt || null
    ]));
    wordStmt.free();

    const sentStmt = db.prepare('INSERT INTO sentences VALUES (?,?,?,?,?,?,?,?,?,?)');
    sentences.forEach(s => sentStmt.run([
      s.id,
      s.original,
      s.translation || '',
      s.platform || '',
      s.contentTitle || '',
      s.contentId || '',
      s.timestamp || 0,
      s.savedAt || '',
      s.reviewCount || 0,
      s.nextReviewAt || null
    ]));
    sentStmt.free();

    const data = db.export();
    db.close();

    const blob = new Blob([data], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    const today = new Date().toISOString().slice(0, 10);
    a.download = `english_helper_${today}.sqlite`;
    a.click();
    URL.revokeObjectURL(url);

    btn.textContent = 'SQLite 내보내기 (.sqlite)';
    btn.disabled = false;
  } catch (err) {
    console.error('[EH Export]', err);
    btn.textContent = '내보내기 실패';
    btn.disabled = false;
    setTimeout(() => {
      btn.textContent = 'SQLite 내보내기 (.sqlite)';
    }, 2000);
  }
});

// ── 초기화 ───────────────────────────────────────────────────────
async function init() {
  const s = await loadSettings();
  applySettingsUI(s);
  loadData();
}

document.addEventListener('DOMContentLoaded', init);

})();
