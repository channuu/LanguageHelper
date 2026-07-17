# English Helper Phase A — Popup & SQLite Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extension 팝업 UI 업데이트 — 단어/문장 탭, SQLite Export(sql.js), 모국어 설정, 패널 토글

**Architecture:** 팝업(popup.html + popup.js)은 service worker와 메시지로 통신. SQLite export는 sql.js를 팝업 페이지에서 로드해 in-memory DB 생성 후 Blob으로 다운로드. chrome.storage.local 키는 `eh-words`, `eh-sentences`, `eh-settings`.

**Tech Stack:** Chrome Extension Popup Page, sql.js v1.12.0 (vendor/sql-wasm.js)

## Global Constraints

- popup.html은 인라인 스크립트 불가 (CSP) — 모든 JS는 popup.js 에서
- sql.js WASM 파일: `vendor/sql-wasm.wasm` (Plan A Task 1에서 다운로드됨)
- `locateFile`로 WASM 경로를 `chrome.runtime.getURL('vendor/sql-wasm.wasm')` 로 지정
- 저장 아이템 최대 500개 (service worker 제한, Plan A Task 3에서 설정)
- XSS 방지: 사용자 데이터 삽입 시 반드시 `esc()` 함수 사용

---

## File Map

| 파일 | 역할 | 신규/수정 |
|------|------|---------|
| `popup/popup.html` | 단어/문장 탭, Export 버튼, 모국어 설정 추가 | 수정 |
| `popup/popup.js` | 새 스키마 로드, SQLite export, 모국어 설정 | 수정 |

---

### Task 11: popup/popup.html 업데이트

**Files:**
- Modify: `popup/popup.html`

**Interfaces:**
- Produces: 탭 구조 (저장단어 / 저장문장 / 설정), Export 버튼, 모국어 선택 드롭다운

- [ ] **Step 1: popup/popup.html 전체 교체**

```html
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <title>English Helper</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=DM+Sans:wght@400;500&display=swap');
    * { margin: 0; padding: 0; box-sizing: border-box; }
    :root {
      --bg: #0e0e10; --surface: #1a1a1e; --border: #2a2a30;
      --gold: #ffd97a; --gold-dim: rgba(255,217,122,0.12);
      --text: #f0ede6; --muted: #7a7870; --danger: #e05a5a;
    }
    body { width: 340px; background: var(--bg); color: var(--text); font-family: 'DM Sans', sans-serif; font-size: 14px; }

    /* 헤더 */
    .header { padding: 16px 20px 0; border-bottom: 1px solid var(--border); }
    .logo { font-family: 'DM Serif Display', serif; font-size: 18px; color: var(--gold); padding-bottom: 12px; }
    .logo-sub { color: var(--muted); font-size: 11px; font-family: 'DM Sans', sans-serif; margin-left: 6px; }
    .tabs { display: flex; }
    .tab-btn {
      flex: 1; padding: 8px 0; background: none; border: none;
      border-bottom: 2px solid transparent;
      color: var(--muted); font-family: 'DM Sans', sans-serif;
      font-size: 12px; cursor: pointer; letter-spacing: 0.04em;
      transition: color 0.15s, border-color 0.15s;
    }
    .tab-btn.active { color: var(--gold); border-bottom-color: var(--gold); }
    .tab-panel { display: none; }
    .tab-panel.active { display: block; }

    /* 공통 섹션 */
    .section-title {
      padding: 12px 20px 6px; font-size: 11px;
      text-transform: uppercase; letter-spacing: .1em;
      color: var(--muted); display: flex; align-items: center; justify-content: space-between;
    }
    .count-badge { font-size: 11px; color: var(--gold); background: var(--gold-dim); border-radius: 10px; padding: 1px 7px; }

    /* 아이템 목록 */
    .item-list { max-height: 240px; overflow-y: auto; padding: 0 12px 8px; }
    .item-list::-webkit-scrollbar { width: 3px; }
    .item-list::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

    .item-card { padding: 9px 12px; margin-bottom: 5px; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; position: relative; transition: border-color .15s; }
    .item-card:hover { border-color: rgba(255,217,122,.3); }
    .item-main { font-size: 13px; color: var(--text); line-height: 1.5; padding-right: 20px; }
    .item-sub  { font-size: 11px; color: var(--muted); margin-top: 3px; }
    .item-def  { font-size: 11px; color: rgba(255,255,255,0.45); margin-top: 2px; line-height: 1.4; }
    .src-badge { font-size: 10px; padding: 1px 5px; border-radius: 3px; background: rgba(255,217,122,.1); color: var(--gold); border: 1px solid rgba(255,217,122,.2); }
    .btn-del { position: absolute; top: 7px; right: 8px; background: none; border: none; color: var(--muted); cursor: pointer; font-size: 13px; opacity: 0; transition: opacity .15s, color .15s; }
    .item-card:hover .btn-del { opacity: 1; }
    .btn-del:hover { color: var(--danger); }
    .empty { padding: 28px 20px; text-align: center; color: var(--muted); font-size: 13px; line-height: 1.8; }

    /* Export 버튼 */
    .export-row { padding: 10px 12px 12px; }
    .btn-export {
      width: 100%; padding: 9px 0;
      background: var(--gold-dim); border: 1px solid rgba(255,217,122,0.3);
      border-radius: 8px; color: var(--gold);
      font-family: 'DM Sans', sans-serif; font-size: 13px;
      cursor: pointer; transition: background 0.15s;
    }
    .btn-export:hover { background: rgba(255,217,122,0.2); }
    .btn-export:disabled { opacity: 0.5; cursor: not-allowed; }

    /* 토글 행 */
    .toggle-row { display: flex; align-items: center; justify-content: space-between; padding: 12px 20px; border-bottom: 1px solid var(--border); }
    .toggle-label { color: var(--muted); font-size: 13px; }
    .switch { position: relative; width: 40px; height: 22px; cursor: pointer; }
    .switch input { opacity: 0; width: 0; height: 0; }
    .slider { position: absolute; inset: 0; background: var(--border); border-radius: 11px; transition: background .2s; }
    .slider:before { content: ""; position: absolute; width: 16px; height: 16px; left: 3px; top: 3px; background: var(--muted); border-radius: 50%; transition: transform .2s, background .2s; }
    .switch input:checked + .slider { background: rgba(255,217,122,.2); }
    .switch input:checked + .slider:before { transform: translateX(18px); background: var(--gold); }

    /* 설정 탭 */
    .setting-group { padding: 14px 20px; border-bottom: 1px solid var(--border); }
    .setting-label { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin-bottom: 10px; }

    /* 모국어 선택 */
    .lang-select {
      width: 100%; padding: 8px 12px;
      background: var(--surface); border: 1px solid var(--border);
      border-radius: 8px; color: var(--text);
      font-family: 'DM Sans', sans-serif; font-size: 13px;
      cursor: pointer; outline: none;
    }
    .lang-select:focus { border-color: rgba(255,217,122,0.4); }

    /* 표시 모드 */
    .mode-options { display: flex; gap: 8px; }
    .mode-btn { flex: 1; padding: 8px 6px; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; color: var(--muted); font-family: 'DM Sans', sans-serif; font-size: 12px; cursor: pointer; text-align: center; transition: all 0.15s; line-height: 1.5; }
    .mode-btn.active { border-color: var(--gold); color: var(--gold); background: var(--gold-dim); }
    .mode-btn span { display: block; font-size: 16px; margin-bottom: 3px; }

    /* 폰트 크기 */
    .font-size-row { display: flex; align-items: center; gap: 10px; margin-top: 4px; }
    .font-size-row label { font-size: 12px; color: var(--muted); min-width: 28px; }
    .slider-input { flex: 1; -webkit-appearance: none; height: 3px; background: var(--border); border-radius: 2px; outline: none; }
    .slider-input::-webkit-slider-thumb { -webkit-appearance: none; width: 14px; height: 14px; background: var(--gold); border-radius: 50%; cursor: pointer; }
    .font-val { font-size: 11px; color: var(--muted); min-width: 32px; text-align: right; }

    /* 미리보기 */
    .font-preview { margin-top: 12px; padding: 10px 12px; background: #000; border-radius: 8px; text-align: center; min-height: 56px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; }
    .preview-en { font-family: 'Georgia', serif; font-weight: 600; color: #fff; text-shadow: 0 0 8px rgba(0,0,0,0.9); }
    .preview-ko { font-family: 'Apple SD Gothic Neo', sans-serif; color: #ffd97a; text-shadow: 0 0 8px rgba(0,0,0,0.9); }
  </style>
</head>
<body>
  <div class="header">
    <div class="logo">EnglishHelper<span class="logo-sub">Beta</span></div>
    <div class="tabs">
      <button class="tab-btn active" data-tab="tab-words">단어</button>
      <button class="tab-btn" data-tab="tab-sentences">문장</button>
      <button class="tab-btn" data-tab="tab-display">표시</button>
      <button class="tab-btn" data-tab="tab-settings">설정</button>
    </div>
  </div>

  <!-- 단어 탭 -->
  <div class="tab-panel active" id="tab-words">
    <div class="section-title">
      저장한 단어
      <span id="word-count" class="count-badge" style="display:none"></span>
    </div>
    <div id="word-list" class="item-list"><div class="empty">불러오는 중...</div></div>
    <div class="export-row">
      <button class="btn-export" id="btn-export">SQLite 내보내기 (.sqlite)</button>
    </div>
  </div>

  <!-- 문장 탭 -->
  <div class="tab-panel" id="tab-sentences">
    <div class="section-title">
      저장한 문장
      <span id="sent-count" class="count-badge" style="display:none"></span>
    </div>
    <div id="sent-list" class="item-list"><div class="empty">불러오는 중...</div></div>
  </div>

  <!-- 표시 탭 -->
  <div class="tab-panel" id="tab-display">
    <div class="toggle-row">
      <span class="toggle-label">자막 오버레이</span>
      <label class="switch"><input type="checkbox" id="toggle-overlay" checked><span class="slider"></span></label>
    </div>
    <div class="toggle-row">
      <span class="toggle-label">스크립트 패널</span>
      <label class="switch"><input type="checkbox" id="toggle-panel" checked><span class="slider"></span></label>
    </div>
  </div>

  <!-- 설정 탭 -->
  <div class="tab-panel" id="tab-settings">
    <div class="setting-group">
      <div class="setting-label">모국어 (Native Language)</div>
      <select class="lang-select" id="native-lang">
        <option value="ko">한국어</option>
        <option value="ja">日本語</option>
        <option value="zh">中文</option>
        <option value="es">Español</option>
        <option value="fr">Français</option>
        <option value="de">Deutsch</option>
      </select>
    </div>
    <div class="setting-group">
      <div class="setting-label">자막 표시 모드</div>
      <div class="mode-options">
        <button class="mode-btn" data-mode="en"><span>🇺🇸</span>영어만</button>
        <button class="mode-btn active" data-mode="both"><span>🌐</span>영어 + 모국어</button>
      </div>
    </div>
    <div class="setting-group">
      <div class="setting-label">영어 자막 크기</div>
      <div class="font-size-row">
        <label>A</label>
        <input type="range" class="slider-input" id="en-size" min="12" max="52" value="22">
        <label style="font-size:18px">A</label>
        <span class="font-val" id="en-size-val">22px</span>
      </div>
    </div>
    <div class="setting-group">
      <div class="setting-label">모국어 자막 크기</div>
      <div class="font-size-row">
        <label>가</label>
        <input type="range" class="slider-input" id="native-size" min="10" max="48" value="18">
        <label style="font-size:18px">가</label>
        <span class="font-val" id="native-size-val">18px</span>
      </div>
    </div>
    <div class="setting-group" style="border-bottom:none">
      <div class="setting-label">미리보기</div>
      <div class="font-preview">
        <div class="preview-en" id="preview-en">I don't even care anymore.</div>
        <div class="preview-ko" id="preview-ko">나는 이제 신경도 안 써.</div>
      </div>
    </div>
  </div>

  <script src="../vendor/sql-wasm.js"></script>
  <script src="popup.js"></script>
</body>
</html>
```

- [ ] **Step 2: 커밋**

```bash
git add popup/popup.html
git commit -m "feat: update popup HTML with word/sentence tabs, export button, native language setting"
```

---

### Task 12: popup/popup.js 업데이트 — SQLite Export + 새 스키마

**Files:**
- Modify: `popup/popup.js`

**Interfaces:**
- Consumes:
  - `chrome.runtime.sendMessage({ type: 'GET_ALL' })` → `{ words: Word[], sentences: Sentence[] }`
  - `chrome.runtime.sendMessage({ type: 'DELETE_ITEM', payload: { type, id } })`
  - `initSqlJs({ locateFile })` — vendor/sql-wasm.js 에서 전역으로 노출됨
- Produces: 팝업 UI 전체 동작, SQLite 파일 다운로드

- [ ] **Step 1: popup/popup.js 전체 교체**

```js
'use strict';

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
  if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, { type: 'APPLY_SETTINGS', settings }).catch(() => {});
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

$('en-size').addEventListener('input', async (e) => {
  const v = parseInt(e.target.value);
  $('en-size-val').textContent = v + 'px';
  $('preview-en').style.fontSize = v + 'px';
  sendSettingsToTab(await saveSettings({ enSize: v }));
});

$('native-size').addEventListener('input', async (e) => {
  const v = parseInt(e.target.value);
  $('native-size-val').textContent = v + 'px';
  $('preview-ko').style.fontSize = v + 'px';
  sendSettingsToTab(await saveSettings({ nativeSize: v }));
});

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
$('toggle-overlay').addEventListener('change', () => {
  chrome.runtime.sendMessage({ type: 'TOGGLE_EXTENSION' });
});

$('toggle-panel').addEventListener('change', async (e) => {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, { type: 'TOGGLE_PANEL', visible: e.target.checked }).catch(() => {});
});

// ── 데이터 로드 ──────────────────────────────────────────────────
function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function platformBadge(platform) {
  const labels = { youtube: '▶ YouTube', netflix: 'N Netflix', disney: '+ Disney+', coupang: '▶ 쿠팡플레이' };
  return labels[platform] || platform;
}

async function loadData() {
  const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
  const { words = [], sentences = [] } = res;

  // 단어 목록
  const wordBadge = $('word-count');
  wordBadge.textContent = words.length + '개';
  wordBadge.style.display = words.length ? 'inline' : 'none';

  const wordList = $('word-list');
  if (!words.length) {
    wordList.innerHTML = '<div class="empty">저장된 단어가 없어요.<br>자막의 단어를 클릭해보세요.</div>';
  } else {
    wordList.innerHTML = words.slice(0, 100).map(w => `
      <div class="item-card">
        <div class="item-main">${esc(w.word)}</div>
        <div class="item-def">${esc(w.definition || '')}</div>
        <div class="item-sub">
          <span class="src-badge">${esc(platformBadge(w.platform))}</span>
          ${esc(w.contentTitle || '')}
        </div>
        <button class="btn-del" data-type="word" data-id="${esc(w.id)}">✕</button>
      </div>`).join('');
  }

  // 문장 목록
  const sentBadge = $('sent-count');
  sentBadge.textContent = sentences.length + '개';
  sentBadge.style.display = sentences.length ? 'inline' : 'none';

  const sentList = $('sent-list');
  if (!sentences.length) {
    sentList.innerHTML = '<div class="empty">저장된 문장이 없어요.<br>스크립트 패널의 + 버튼을 눌러보세요.</div>';
  } else {
    sentList.innerHTML = sentences.slice(0, 100).map(s => `
      <div class="item-card">
        <div class="item-main">${esc(s.original)}</div>
        ${s.translation ? `<div class="item-def">${esc(s.translation)}</div>` : ''}
        <div class="item-sub">
          <span class="src-badge">${esc(platformBadge(s.platform))}</span>
          ${esc(s.contentTitle || '')}
        </div>
        <button class="btn-del" data-type="sentence" data-id="${esc(s.id)}">✕</button>
      </div>`).join('');
  }
}

// 삭제 이벤트 위임
document.addEventListener('click', async (e) => {
  const btn = e.target.closest('.btn-del');
  if (!btn) return;
  btn.closest('.item-card').style.opacity = '0.3';
  await chrome.runtime.sendMessage({ type: 'DELETE_ITEM', payload: { type: btn.dataset.type, id: btn.dataset.id } });
  loadData();
});

// ── SQLite Export ─────────────────────────────────────────────────
$('btn-export').addEventListener('click', async () => {
  const btn = $('btn-export');
  btn.disabled = true;
  btn.textContent = '내보내는 중...';

  try {
    const { words = [], sentences = [] } = await chrome.runtime.sendMessage({ type: 'GET_ALL' });

    const SQL = await initSqlJs({
      locateFile: file => chrome.runtime.getURL('vendor/' + file)
    });
    const db = new SQL.Database();

    db.run(`CREATE TABLE words (
      id TEXT PRIMARY KEY, word TEXT NOT NULL, definition TEXT,
      sentence TEXT, translation TEXT, platform TEXT,
      content_title TEXT, content_id TEXT, timestamp REAL,
      saved_at TEXT, review_count INTEGER DEFAULT 0, next_review_at TEXT
    )`);

    db.run(`CREATE TABLE sentences (
      id TEXT PRIMARY KEY, original TEXT NOT NULL, translation TEXT,
      platform TEXT, content_title TEXT, content_id TEXT,
      timestamp REAL, saved_at TEXT,
      review_count INTEGER DEFAULT 0, next_review_at TEXT
    )`);

    const wordStmt = db.prepare(
      'INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)'
    );
    words.forEach(w => wordStmt.run([
      w.id, w.word, w.definition || '', w.sentence || '',
      w.translation || '', w.platform || '', w.contentTitle || '',
      w.contentId || '', w.timestamp || 0, w.savedAt || '',
      w.reviewCount || 0, w.nextReviewAt || null
    ]));
    wordStmt.free();

    const sentStmt = db.prepare(
      'INSERT INTO sentences VALUES (?,?,?,?,?,?,?,?,?,?)'
    );
    sentences.forEach(s => sentStmt.run([
      s.id, s.original, s.translation || '', s.platform || '',
      s.contentTitle || '', s.contentId || '', s.timestamp || 0,
      s.savedAt || '', s.reviewCount || 0, s.nextReviewAt || null
    ]));
    sentStmt.free();

    const data = db.export();
    db.close();

    const blob = new Blob([data], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'english_helper.sqlite';
    a.click();
    URL.revokeObjectURL(url);

    btn.textContent = '✓ 내보내기 완료!';
    setTimeout(() => {
      btn.textContent = 'SQLite 내보내기 (.sqlite)';
      btn.disabled = false;
    }, 2000);
  } catch (err) {
    console.error('[EH Export]', err);
    btn.textContent = '내보내기 실패 — 다시 시도';
    btn.disabled = false;
  }
});

// ── 초기화 ───────────────────────────────────────────────────────
async function init() {
  const s = await loadSettings();
  applySettingsUI(s);
  loadData();
}

init();
```

- [ ] **Step 2: SQLite Export 수동 테스트**

1. 단어/문장을 최소 1개 이상 저장
2. Extension 팝업 열기
3. "SQLite 내보내기" 버튼 클릭
4. `english_helper.sqlite` 파일 다운로드 확인
5. DB Browser for SQLite 또는 터미널에서 검증:
```bash
sqlite3 ~/Downloads/english_helper.sqlite ".tables"
# Expected: sentences  words
sqlite3 ~/Downloads/english_helper.sqlite "SELECT word, definition FROM words LIMIT 3;"
# Expected: 저장한 단어 목록 출력
```

- [ ] **Step 3: 모국어 설정 테스트**

1. 설정 탭 → 모국어를 "日本語"로 변경
2. Netflix/YouTube 영상 재생 → 하단 자막 줄이 일본어로 변경 확인
3. 팝업 닫고 다시 열면 선택 유지 확인

- [ ] **Step 4: 커밋**

```bash
git add popup/popup.js popup/popup.html
git commit -m "feat: update popup with word/sentence tabs, SQLite export, native language setting"
```

---

## Plan C 완료 체크리스트

- [ ] Task 11: popup.html — 단어/문장/표시/설정 탭, Export 버튼
- [ ] Task 12: popup.js — GET_ALL 로드, SQLite export, 모국어 설정

---

## Phase A 전체 완료 후 E2E 검증

- [ ] YouTube 영상 재생 → 이중 자막 + 사이드패널 + 단어팝업 동작 확인
- [ ] Netflix 영상 재생 → 이중 자막 동작 확인
- [ ] Disney+ 영상 재생 → 이중 자막 동작 확인
- [ ] 쿠팡플레이 영상 재생 → 이중 자막 동작 확인
- [ ] 단어 저장 → Export → english_helper.sqlite 다운로드 → Flutter 앱에 복사
- [ ] Extension reload 후 설정(모국어, 자막 크기) 유지 확인

**Phase A 완료 후 → Phase B (Flutter 앱) 설계 및 구현으로 이동**
