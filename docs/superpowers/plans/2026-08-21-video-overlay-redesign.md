# 영상 위 UI 재설계 (1h/1i) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top settings bar + settings panel to the video-overlay UI (superseding what the popup used to control), extend the script panel with search/saved-state/auto-scroll, and share the SQLite export logic between the popup and the new settings panel — matching `English Helper UI.dc.html` §1h/§1i.

**Architecture:** Follow the existing content-script module convention exactly: each new piece is a self-contained IIFE registered on `window.EH.*`, initialized from `core/adapter-interface.js`'s `init(adapter)`, styled via `ui/tokens.css` variables in `ui/overlay.css`. No build step, no bundler — files are added directly to `manifest.json`'s `content_scripts` arrays (all 4 platform entries) in dependency order, same as every existing `core/*.js` file.

**Tech Stack:** Vanilla JS (ES2020, IIFE modules), `chrome.storage.local`/`chrome.runtime` messaging, `sql.js` (already vendored, used by the existing SQLite export).

## Global Constraints

- No new package dependencies. `sql.js` is already vendored (`vendor/sql-wasm.js`); reuse it.
- Existing subtitle drag/resize behavior (`core/subtitle-engine.js`'s `attachDrag`/`attachResize`) is **kept, not removed** — the mockup's fixed bottom-center position is a *default* only, applied when no saved position exists (existing `restorePosition` behavior already works this way).
- `enSize`/`nativeSize` in the new settings panel's two sliders are **independent** — do not derive one from the other.
- No new `chrome.runtime` message types where an existing one already covers the need — reuse `APPLY_SETTINGS`/`window.EH.applySettings` for all settings-panel changes (already fans out to `SubtitleEngine.applySettings`/`ScriptPanel.applySettings`).
- Script export stays HTML format (`ScriptPanel.exportScript`, already built and reviewed) — do not add `.srt`/`.txt` formats.
- This project has no JS test runner for `core/`/`popup/` (`mobile/` has `flutter test`, unrelated). Where a step's logic is pure (no DOM/`chrome.*` dependency), write it as an exported pure function and verify with a throwaway `node` script (same "headless simulation harness" pattern already used elsewhere in this project for Netflix/Coupang adapter work) — do not add a new test framework. Where a step is DOM/`chrome.*` wiring, verification is a manual checklist step (same established pattern as every prior overlay-UI task in this project — loading an unpacked extension isn't automatable in this environment).
- Follow the existing naming convention: singleton elements get `#eh-*` ids, repeated/component classes get `.eh-*` classes (see `ui/overlay.css`'s existing `#eh-panel`/`.eh-panel-item` etc.).

---

### Task 1: Extract shared SQLite export module

**Files:**
- Create: `core/sqlite-export.js`
- Modify: `popup/popup.js:191-289` (replace the inline export handler body)
- Modify: `popup/popup.html:206` (add the new script tag before `popup.js`)
- Modify: `manifest.json` (add `core/sqlite-export.js` to all 4 `content_scripts` `js` arrays, positioned after `core/storage.js`)

**Interfaces:**
- Produces: `window.EH.SqliteExport.exportAll(words, sentences)` — pure-ish function taking already-fetched word/sentence arrays, returns nothing (triggers a browser download of `english_helper_{date}.sqlite`), throws on failure (caller catches). `window.EH.SqliteExport.buildDatabase(words, sentences)` — the pure part, returns a `Uint8Array` (the exported `.sqlite` bytes) without touching the DOM, so it's independently testable.
- Consumes: `sql.js`'s `initSqlJs` (already loaded via `<script src="../vendor/sql-wasm.js">` in `popup.html`; the settings panel — Task 3 — will need the same script tag added to its own load path via `web_accessible_resources`, handled in that task).

- [ ] **Step 1: Create the shared module**

Create `core/sqlite-export.js`:

```js
(function () {
  'use strict';

  /**
   * Builds the .sqlite export bytes from already-fetched words/sentences.
   * Pure — no DOM access, no chrome.* calls — so it's testable with plain Node.
   * @param {object} SQL - the object returned by `await initSqlJs(...)`
   * @param {Array} words
   * @param {Array} sentences
   * @returns {Uint8Array}
   */
  function buildDatabase(SQL, words, sentences) {
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
      w.id, w.word, w.definition || '', w.sentence || '', w.translation || '',
      w.platform || '', w.contentTitle || '', w.contentId || '',
      w.timestamp || 0, w.savedAt || '', w.reviewCount || 0, w.nextReviewAt || null
    ]));
    wordStmt.free();

    const sentStmt = db.prepare('INSERT INTO sentences VALUES (?,?,?,?,?,?,?,?,?,?)');
    sentences.forEach(s => sentStmt.run([
      s.id, s.original, s.translation || '', s.platform || '',
      s.contentTitle || '', s.contentId || '', s.timestamp || 0,
      s.savedAt || '', s.reviewCount || 0, s.nextReviewAt || null
    ]));
    sentStmt.free();

    const bytes = db.export();
    db.close();
    return bytes;
  }

  /**
   * Full export flow: init sql.js, build the database, trigger a download.
   * @param {Array} words
   * @param {Array} sentences
   * @param {{locateFile?: (f: string) => string}} [opts]
   */
  async function exportAll(words, sentences, opts = {}) {
    const SQL = await initSqlJs({
      locateFile: opts.locateFile || (f => '../vendor/' + f)
    });
    const data = buildDatabase(SQL, words, sentences);

    const blob = new Blob([data], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    const today = new Date().toISOString().slice(0, 10);
    a.download = `english_helper_${today}.sqlite`;
    a.click();
    URL.revokeObjectURL(url);
  }

  window.EH = window.EH || {};
  window.EH.SqliteExport = { buildDatabase, exportAll };
})();
```

- [ ] **Step 2: Verify `buildDatabase` with a throwaway Node script**

`sql.js`'s `initSqlJs` needs a real WASM binary, which isn't trivial to load outside a browser/extension context — so this verification uses a **fake** `SQL.Database` matching the same interface (`run`, `prepare().run()/.free()`, `export`, `close`), to confirm `buildDatabase`'s row-mapping logic (field order, defaults for missing fields) is correct without needing real sql.js.

Create a temp file (not committed) `/tmp/verify-sqlite-export.js`:

```js
global.window = global; // core/sqlite-export.js does `window.EH = ...`

const calls = { words: [], sentences: [] };
const fakeSQL = {
  Database: class {
    run(sql) { this._lastCreate = sql; }
    prepare(sql) {
      const table = sql.includes('INTO words') ? 'words' : 'sentences';
      return {
        run: (vals) => calls[table].push(vals),
        free: () => {}
      };
    }
    export() { return new Uint8Array([1, 2, 3]); }
    close() {}
  }
};

require('/Users/park/Project2/english-helper-extension/core/sqlite-export.js');

const words = [{ id: 'w1', word: 'ephemeral', platform: 'youtube', timestamp: 12.5, savedAt: '2026-08-21' }];
const sentences = [{ id: 's1', original: 'Nothing is ephemeral.', platform: 'youtube', timestamp: 12.5, savedAt: '2026-08-21' }];

const bytes = window.EH.SqliteExport.buildDatabase(fakeSQL, words, sentences);

console.assert(bytes.length === 3, 'export() bytes returned');
console.assert(calls.words.length === 1, 'one word row inserted');
console.assert(calls.words[0][0] === 'w1', 'word id in position 0');
console.assert(calls.words[0][1] === 'ephemeral', 'word text in position 1');
console.assert(calls.words[0][2] === '', 'missing definition defaults to empty string');
console.assert(calls.sentences.length === 1, 'one sentence row inserted');
console.assert(calls.sentences[0][1] === 'Nothing is ephemeral.', 'sentence original in position 1');
console.assert(calls.sentences[0][7] === 0, 'missing reviewCount defaults to 0');

console.log('OK — all assertions passed');
```

Run: `node /tmp/verify-sqlite-export.js`
Expected: `OK — all assertions passed` (no `Assertion failed` lines above it). Delete the temp file after (`rm /tmp/verify-sqlite-export.js`) — it's a verification script, not part of the codebase.

- [ ] **Step 3: Wire the module into `popup.html`**

In `popup/popup.html`, find this line near the bottom:

```html
  <script src="../vendor/sql-wasm.js"></script>
  <script src="popup.js"></script>
```

Replace with:

```html
  <script src="../vendor/sql-wasm.js"></script>
  <script src="../core/sqlite-export.js"></script>
  <script src="popup.js"></script>
```

- [ ] **Step 4: Replace `popup.js`'s inline export logic with a call to the shared module**

In `popup/popup.js`, find the `$('btn-export').addEventListener('click', async () => { ... })` block (currently lines 192-289). Replace its entire body with:

```js
$('btn-export').addEventListener('click', async () => {
  const btn = $('btn-export');
  btn.disabled = true;
  btn.textContent = '내보내는 중...';

  try {
    const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
    const words = (res && res.words) ? res.words : [];
    const sentences = (res && res.sentences) ? res.sentences : [];

    await window.EH.SqliteExport.exportAll(words, sentences);

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
```

- [ ] **Step 5: Add the new file to `manifest.json`**

In `manifest.json`, there are 4 `content_scripts` entries with a `js` array containing `"core/storage.js"` (for youtube, netflix, disneyplus, coupangplay). In **each** of the 4, add `"core/sqlite-export.js"` immediately after `"core/storage.js"`. For example, the YouTube entry changes from:

```json
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

to:

```json
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/sqlite-export.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

Apply the same one-line insertion to the netflix, disneyplus, and coupangplay entries (they currently have the identical `js` array shape).

- [ ] **Step 6: Manual verification**

1. Load the unpacked extension (`chrome://extensions` → Developer mode → Load unpacked → repo root).
2. Open the popup on any tab, go to 단어 tab, click "SQLite 내보내기 (.sqlite)".
3. Confirm a `.sqlite` file downloads and the button text returns to normal afterward (regression check — this must behave identically to before the refactor).

- [ ] **Step 7: Commit**

```bash
git add core/sqlite-export.js popup/popup.js popup/popup.html manifest.json
git commit -m "refactor: extract SQLite export into a shared core/sqlite-export.js module"
```

---

### Task 2: Top settings bar

**Files:**
- Create: `core/topbar.js`
- Modify: `ui/overlay.css` (append new styles)
- Modify: `core/adapter-interface.js:52-55` (register the new module's `setup` call)
- Modify: `manifest.json` (add `core/topbar.js` to all 4 `content_scripts` `js` arrays)

**Interfaces:**
- Consumes: `window.EH.settings` (existing, from `adapter-interface.js`), `window.EH.SubtitleEngine.toggle()`/`window.EH.ScriptPanel.toggle()` (existing), `adapter.getPlatformMeta()` (existing `SubtitleAdapter` contract method).
- Produces: `window.EH.TopBar = { setup(adapter) }`. Fires a custom DOM event `'eh-settings-toggle'` on `document` when the 설정 button is clicked — Task 3's settings panel listens for this event to show/hide itself (kept as a DOM event rather than a new `window.EH.*` coupling, since the settings panel doesn't exist yet when this task ships and the bar shouldn't hard-depend on it).

- [ ] **Step 1: Create the top bar module**

Create `core/topbar.js`:

```js
(function () {
  'use strict';

  let overlayOn = true;
  let panelOn = true;

  function createDOM(adapter) {
    if (document.getElementById('eh-topbar')) return;

    const bar = document.createElement('div');
    bar.id = 'eh-topbar';

    const brand = document.createElement('div');
    brand.className = 'eh-topbar-brand';
    const meta = adapter.getPlatformMeta?.() || { platform: '' };
    brand.innerHTML =
      '<span class="eh-topbar-name">English Helper</span>' +
      `<span class="eh-topbar-badge">${esc((meta.platform || '').toUpperCase())}</span>`;
    bar.appendChild(brand);

    const divider = document.createElement('div');
    divider.className = 'eh-topbar-divider';
    bar.appendChild(divider);

    const overlayToggle = buildToggle('자막 오버레이', overlayOn, () => {
      overlayOn = !overlayOn;
      window.EH.SubtitleEngine?.toggle();
      updateToggleState(overlayToggle, overlayOn);
    });
    bar.appendChild(overlayToggle.el);

    const panelToggle = buildToggle('스크립트 패널', panelOn, () => {
      panelOn = !panelOn;
      window.EH.ScriptPanel?.toggle(panelOn);
      updateToggleState(panelToggle, panelOn);
    });
    bar.appendChild(panelToggle.el);

    const spacer = document.createElement('div');
    spacer.style.flex = '1';
    bar.appendChild(spacer);

    const count = document.createElement('span');
    count.id = 'eh-topbar-count';
    count.className = 'eh-topbar-count';
    bar.appendChild(count);
    refreshCount(count);

    const settingsBtn = document.createElement('div');
    settingsBtn.id = 'eh-topbar-settings';
    settingsBtn.className = 'eh-topbar-settings-btn';
    settingsBtn.innerHTML =
      '<svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round">' +
      '<path d="M1.6 3.6h9.8M1.6 9.4h9.8"></path>' +
      '<circle cx="4.6" cy="3.6" r="1.7"></circle><circle cx="8.4" cy="9.4" r="1.7"></circle></svg>' +
      '<span>설정</span>';
    settingsBtn.addEventListener('click', () => {
      document.dispatchEvent(new CustomEvent('eh-settings-toggle'));
    });
    bar.appendChild(settingsBtn);

    document.body.appendChild(bar);
  }

  function buildToggle(label, initialOn, onClick) {
    const el = document.createElement('div');
    el.className = 'eh-topbar-toggle';
    el.innerHTML =
      '<span class="eh-topbar-switch"><span class="eh-topbar-knob"></span></span>' +
      `<span class="eh-topbar-toggle-label">${esc(label)}</span>`;
    el.addEventListener('click', onClick);
    const wrapper = { el };
    updateToggleState(wrapper, initialOn);
    return wrapper;
  }

  function updateToggleState(toggle, on) {
    toggle.el.querySelector('.eh-topbar-switch').classList.toggle('on', on);
    toggle.el.querySelector('.eh-topbar-toggle-label').classList.toggle('dim', !on);
  }

  async function refreshCount(countEl) {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      const total = ((res && res.words) || []).length + ((res && res.sentences) || []).length;
      countEl.textContent = '저장 ' + total;
    } catch (_) {
      countEl.textContent = '';
    }
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function setup(adapter) {
    createDOM(adapter);
  }

  window.EH = window.EH || {};
  window.EH.TopBar = { setup };
})();
```

- [ ] **Step 2: Add top-bar styles**

Append to `ui/overlay.css`:

```css
#eh-topbar {
  position: fixed;
  top: 0; left: 0; right: 0;
  z-index: 2147483000;
  height: 46px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 0 16px;
  background: var(--eh-surface);
  border-bottom: 1px solid rgba(var(--eh-gold-rgb), 0.16);
  font-family: var(--eh-font-body);
}

.eh-topbar-brand { display: flex; align-items: baseline; gap: 7px; }
.eh-topbar-name { font-weight: 600; font-size: 14px; color: var(--eh-text); letter-spacing: -0.01em; }
.eh-topbar-badge {
  font: 600 9px var(--eh-font-mono);
  letter-spacing: 0.08em;
  color: var(--eh-gold-strong);
  border: 1px solid rgba(var(--eh-gold-rgb), 0.3);
  padding: 2px 5px;
  border-radius: 4px;
}

.eh-topbar-divider { width: 1px; height: 18px; background: rgba(var(--eh-text-rgb), 0.1); }

.eh-topbar-toggle { display: flex; align-items: center; gap: 7px; cursor: pointer; }
.eh-topbar-switch {
  display: inline-block;
  width: 32px; height: 18px;
  border-radius: 9px;
  background: rgba(var(--eh-text-rgb), 0.18);
  position: relative;
  transition: background 0.15s;
}
.eh-topbar-switch.on { background: var(--eh-accent); }
.eh-topbar-knob {
  position: absolute;
  top: 2px; left: 2px;
  width: 14px; height: 14px;
  border-radius: 7px;
  background: var(--eh-text);
  transition: left 0.15s;
}
.eh-topbar-switch.on .eh-topbar-knob { left: 16px; }
.eh-topbar-toggle-label { font-size: 12px; color: var(--eh-text); }
.eh-topbar-toggle-label.dim { color: rgba(var(--eh-text-rgb), 0.4); }

.eh-topbar-count { font: 11px var(--eh-font-mono); color: rgba(var(--eh-text-rgb), 0.34); }

.eh-topbar-settings-btn {
  display: flex; align-items: center; gap: 6px;
  height: 28px; padding: 0 11px;
  border-radius: 8px;
  cursor: pointer;
  background: transparent;
  border: 1px solid rgba(var(--eh-text-rgb), 0.14);
  color: rgba(var(--eh-text-rgb), 0.75);
  font: 600 12px var(--eh-font-body);
}
.eh-topbar-settings-btn:hover { border-color: rgba(var(--eh-gold-rgb), 0.4); color: var(--eh-gold); }
```

- [ ] **Step 3: Register in `adapter-interface.js`**

In `core/adapter-interface.js`, find:

```js
    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
```

Replace with:

```js
    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.TopBar)         window.EH.TopBar.setup(adapter);
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
```

- [ ] **Step 4: Add to `manifest.json`**

In each of the 4 `content_scripts` entries (youtube, netflix, disneyplus, coupangplay), add `"core/topbar.js"` immediately after `"core/adapter-interface.js"`. The YouTube entry's `js` array becomes:

```json
      "js": [
        "core/adapter-interface.js",
        "core/topbar.js",
        "core/storage.js",
        "core/sqlite-export.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

Apply the same insertion (right after `core/adapter-interface.js`) to the other 3 entries.

- [ ] **Step 5: Manual verification**

1. Load the unpacked extension, open a supported video page (e.g. a YouTube video with captions).
2. Confirm the top bar appears with "English Helper" + platform badge, both toggles, a save count, and a "설정" button.
3. Click each toggle — confirm the subtitle overlay and script panel actually show/hide, and the toggle's visual state (accent color, knob position) updates.
4. Click "설정" — confirm nothing visibly breaks (the panel itself doesn't exist yet until Task 3; this just confirms the click handler fires without a console error — check DevTools console for a clean `CustomEvent` dispatch, no errors).

- [ ] **Step 6: Commit**

```bash
git add core/topbar.js ui/overlay.css core/adapter-interface.js manifest.json
git commit -m "feat: add top settings bar to video overlay (toggles, save count, settings button)"
```

---

### Task 3: Settings panel

**Files:**
- Create: `core/settings-panel.js`
- Modify: `ui/overlay.css` (append new styles)
- Modify: `core/adapter-interface.js` (register the new module's `setup` call, add `web_accessible_resources` note in Step 4 below)
- Modify: `manifest.json` (add `core/settings-panel.js` to all 4 `content_scripts` `js` arrays; add `vendor/sql-wasm.js` availability for content scripts)

**Interfaces:**
- Consumes: `window.EH.settings`/`window.EH.applySettings(patch)` (existing, from `adapter-interface.js`). `window.EH.SqliteExport.exportAll` (Task 1). `window.EH.ScriptPanel.exportScript` — **not directly exposed yet**; this task exposes it (see Step 1 sub-note). Listens for the `'eh-settings-toggle'` DOM event (Task 2).
- Produces: `window.EH.SettingsPanel = { setup(adapter) }`.

- [ ] **Step 1: Expose `exportScript` from the script panel module**

`core/script-panel.js`'s `window.EH.ScriptPanel = { setup, highlight, toggle, applySettings };` doesn't currently expose `exportScript` (it's only wired to the panel's own export button internally). Add it to the export line:

In `core/script-panel.js`, find:

```js
  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings };
```

Replace with:

```js
  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings, exportScript };
```

- [ ] **Step 2: Create the settings panel module**

Create `core/settings-panel.js`:

```js
(function () {
  'use strict';

  const LANGS = { ko: '한국어', ja: '日本語', zh: '中文', es: 'Español', fr: 'Français', de: 'Deutsch' };
  // 9 ticks spanning the existing 12–52px enSize range and 10–48px nativeSize range.
  const EN_TICKS = [12, 17, 22, 27, 32, 37, 42, 47, 52];
  const KO_TICKS = [10, 14, 18, 22, 26, 30, 34, 41, 48];

  let panelEl = null;
  let open = false;

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function nearestTick(ticks, value) {
    return ticks.reduce((best, t) => Math.abs(t - value) < Math.abs(best - value) ? t : best, ticks[0]);
  }

  function render() {
    const s = window.EH.settings;
    panelEl.innerHTML = `
      <div class="eh-settings-header">
        <span class="eh-settings-title">SETTINGS</span>
        <span class="eh-settings-close" id="eh-settings-close">✕</span>
      </div>
      <div class="eh-settings-body">
        <div class="eh-settings-label">모국어 (NATIVE LANGUAGE)</div>
        <div class="eh-settings-langs" id="eh-settings-langs">
          ${Object.entries(LANGS).map(([code, label]) => `
            <div class="eh-settings-chip${s.nativeLang === code ? ' active' : ''}" data-lang="${code}">${esc(label)}</div>
          `).join('')}
        </div>

        <div class="eh-settings-label" style="margin-top:18px">자막 표시 모드</div>
        <div class="eh-settings-mode-row">
          <div class="eh-settings-mode-btn${s.mode === 'en' ? ' active' : ''}" data-mode="en">영어만</div>
          <div class="eh-settings-mode-btn${s.mode === 'both' ? ' active' : ''}" data-mode="both">영어 + 모국어</div>
        </div>

        ${sliderBlock('영어 자막 크기', 'en', s.enSize, EN_TICKS)}
        ${sliderBlock('모국어 자막 크기', 'ko', s.nativeSize, KO_TICKS)}

        <div class="eh-settings-label" style="margin-top:18px">미리보기</div>
        <div class="eh-settings-preview">
          <div style="font-size:${s.enSize}px">I don't even care anymore.</div>
          ${s.mode !== 'en' ? `<div class="eh-settings-preview-ko" style="font-size:${s.nativeSize}px">나는 이제 신경도 안 써.</div>` : ''}
        </div>

        <div class="eh-settings-divider"></div>
        <div class="eh-settings-label">내보내기</div>
        <div class="eh-settings-export-row">
          <div class="eh-settings-export-btn primary" id="eh-export-script">스크립트 내보내기</div>
          <div class="eh-settings-export-btn" id="eh-export-sqlite">저장 항목 내보내기<span class="eh-settings-export-ext">.sqlite</span></div>
        </div>
      </div>
    `;

    panelEl.querySelector('#eh-settings-close').addEventListener('click', hide);

    panelEl.querySelectorAll('.eh-settings-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        window.EH.applySettings({ nativeLang: chip.dataset.lang });
        render();
      });
    });

    panelEl.querySelectorAll('.eh-settings-mode-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        window.EH.applySettings({ mode: btn.dataset.mode });
        render();
      });
    });

    attachSlider('en', EN_TICKS);
    attachSlider('ko', KO_TICKS);

    panelEl.querySelector('#eh-export-script').addEventListener('click', () => {
      window.EH.ScriptPanel?.exportScript();
    });

    panelEl.querySelector('#eh-export-sqlite').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      const original = btn.innerHTML;
      btn.textContent = '내보내는 중...';
      try {
        const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
        await window.EH.SqliteExport.exportAll((res && res.words) || [], (res && res.sentences) || []);
        btn.innerHTML = original;
      } catch (err) {
        console.error('[EH SettingsPanel] sqlite export failed', err);
        btn.textContent = '내보내기 실패';
        setTimeout(() => { btn.innerHTML = original; }, 2000);
      }
    });
  }

  function sliderBlock(label, key, value, ticks) {
    const sizeKey = key === 'en' ? 'enSize' : 'nativeSize';
    return `
      <div class="eh-settings-slider-header" style="margin-top:18px">
        <span class="eh-settings-label" style="margin:0">${esc(label)}</span>
        <span class="eh-settings-slider-value" data-size-label="${key}">${value}px</span>
      </div>
      <div class="eh-settings-slider-row" data-slider="${key}" data-size-key="${sizeKey}">
        ${ticks.map(t => `<div class="eh-settings-tick${t <= value ? ' active' : ''}" data-tick="${t}"></div>`).join('')}
      </div>
    `;
  }

  function attachSlider(key, ticks) {
    const row = panelEl.querySelector(`.eh-settings-slider-row[data-slider="${key}"]`);
    if (!row) return;
    row.querySelectorAll('.eh-settings-tick').forEach(tickEl => {
      tickEl.addEventListener('click', () => {
        const value = Number(tickEl.dataset.tick);
        const sizeKey = row.dataset.sizeKey;
        window.EH.applySettings({ [sizeKey]: value });
        render();
      });
    });
  }

  function createDOM() {
    if (document.getElementById('eh-settings-panel')) {
      panelEl = document.getElementById('eh-settings-panel');
      return;
    }
    panelEl = document.createElement('div');
    panelEl.id = 'eh-settings-panel';
    panelEl.classList.add('hidden');
    document.body.appendChild(panelEl);
  }

  function show() {
    open = true;
    render();
    panelEl.classList.remove('hidden');
  }

  function hide() {
    open = false;
    panelEl.classList.add('hidden');
  }

  function toggle() {
    if (open) hide(); else show();
  }

  function setup() {
    createDOM();
    document.addEventListener('eh-settings-toggle', toggle);
  }

  window.EH = window.EH || {};
  window.EH.SettingsPanel = { setup };
})();
```

Note: `nearestTick` is defined but not called in this version — the panel always renders ticks as exactly `<= value` colored, which works even if a stored `enSize`/`nativeSize` value doesn't land exactly on a tick (e.g. a legacy value of 22 still correctly colors ticks `12,17,22` as active even though 22 isn't snapped to a "clean" step). Leave `nearestTick` unused-but-defined only if a later step needs it — otherwise remove it in Step 3's review pass to avoid dead code.

- [ ] **Step 3: Remove the dead `nearestTick` helper**

Since `render()`'s tick-coloring logic (`t <= value`) doesn't need snapping, delete the unused `nearestTick` function from `core/settings-panel.js` (it was scaffolded during design but isn't called anywhere — leaving it would be dead code).

- [ ] **Step 4: Add settings-panel styles**

Append to `ui/overlay.css`:

```css
#eh-settings-panel {
  position: fixed;
  top: 52px; right: 16px; bottom: 16px;
  z-index: 2147483001;
  width: 308px;
  display: flex;
  flex-direction: column;
  background: rgba(21, 24, 29, 0.97);
  border: 1px solid rgba(var(--eh-gold-rgb), 0.2);
  border-radius: 14px;
  box-shadow: 0 24px 50px rgba(0, 0, 0, 0.55);
  overflow: hidden;
  font-family: var(--eh-font-body);
}
#eh-settings-panel.hidden { display: none !important; }

.eh-settings-header {
  flex: none;
  display: flex; align-items: center;
  padding: 13px 15px;
  border-bottom: 1px solid rgba(var(--eh-text-rgb), 0.08);
}
.eh-settings-title { font: 600 10.5px var(--eh-font-mono); letter-spacing: 0.12em; color: var(--eh-gold-strong); flex: 1; }
.eh-settings-close { color: rgba(var(--eh-text-rgb), 0.4); font-size: 13px; cursor: pointer; }
.eh-settings-close:hover { color: var(--eh-text); }

.eh-settings-body { flex: 1; min-height: 0; overflow: auto; padding: 15px; }
.eh-settings-label { font: 600 9.5px var(--eh-font-mono); letter-spacing: 0.1em; color: rgba(var(--eh-text-rgb), 0.4); }

.eh-settings-langs { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 9px; }
.eh-settings-chip {
  padding: 6px 11px; border-radius: 8px; cursor: pointer;
  font: 500 12px var(--eh-font-body);
  background: transparent; color: rgba(var(--eh-text-rgb), 0.75);
  border: 1px solid rgba(var(--eh-text-rgb), 0.14);
}
.eh-settings-chip.active { background: rgba(var(--eh-gold-rgb), 0.16); color: var(--eh-gold); border-color: rgba(var(--eh-gold-rgb), 0.4); }

.eh-settings-mode-row { display: flex; gap: 7px; margin-top: 9px; }
.eh-settings-mode-btn {
  flex: 1; height: 36px; box-sizing: border-box;
  border-radius: 9px; display: flex; align-items: center; justify-content: center;
  cursor: pointer; font: 600 12px var(--eh-font-body);
  background: transparent; color: rgba(var(--eh-text-rgb), 0.6);
  border: 1px solid rgba(var(--eh-text-rgb), 0.14);
}
.eh-settings-mode-btn.active { background: rgba(var(--eh-gold-rgb), 0.16); color: var(--eh-gold); border-color: rgba(var(--eh-gold-rgb), 0.4); }

.eh-settings-slider-header { display: flex; align-items: baseline; justify-content: space-between; }
.eh-settings-slider-value { font: 11px var(--eh-font-mono); color: var(--eh-gold-strong); }
.eh-settings-slider-row { display: flex; gap: 3px; align-items: flex-end; height: 22px; margin-top: 11px; }
.eh-settings-tick { flex: 1; height: 100%; border-radius: 2px; background: rgba(var(--eh-text-rgb), 0.14); cursor: pointer; }
.eh-settings-tick.active { background: var(--eh-gold); }

.eh-settings-preview {
  margin-top: 9px; border-radius: 10px; background: #000;
  padding: 14px 12px; text-align: center;
}
.eh-settings-preview div:first-child { color: var(--eh-text); line-height: 1.3; font-weight: 500; }
.eh-settings-preview-ko { color: var(--eh-gold-strong); margin-top: 5px; }

.eh-settings-divider { height: 1px; background: rgba(var(--eh-text-rgb), 0.08); margin: 17px 0; }

.eh-settings-export-row { display: flex; flex-direction: column; gap: 7px; margin-top: 9px; }
.eh-settings-export-btn {
  height: 40px; border-radius: 9px; box-sizing: border-box;
  display: flex; align-items: center; gap: 8px; padding: 0 13px;
  font: 600 12.5px var(--eh-font-body); cursor: pointer;
  background: transparent; border: 1px solid rgba(var(--eh-text-rgb), 0.16);
  color: rgba(var(--eh-text-rgb), 0.85);
}
.eh-settings-export-btn.primary { background: var(--eh-accent); color: #14161f; border-color: transparent; }
.eh-settings-export-ext { margin-left: auto; font: 10.5px var(--eh-font-mono); opacity: 0.62; }
```

- [ ] **Step 5: Register in `adapter-interface.js`**

In `core/adapter-interface.js`, extend the same block Task 2 edited:

```js
    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.TopBar)         window.EH.TopBar.setup(adapter);
    if (window.EH.SettingsPanel)  window.EH.SettingsPanel.setup(adapter);
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
```

- [ ] **Step 6: Add to `manifest.json`, and make `sql-wasm.js` loadable by content scripts**

Add `"core/settings-panel.js"` to each of the 4 `content_scripts` `js` arrays, right after `"core/topbar.js"`:

```json
      "js": [
        "core/adapter-interface.js",
        "core/topbar.js",
        "core/settings-panel.js",
        "core/storage.js",
        "core/sqlite-export.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

Apply to the other 3 platform entries too.

The settings panel's SQLite export button calls `window.EH.SqliteExport.exportAll`, which calls the global `initSqlJs` — but content scripts (unlike `popup.html`) don't get `vendor/sql-wasm.js` loaded automatically; only the popup's own HTML page loads it via `<script src="../vendor/sql-wasm.js">`. Add `"vendor/sql-wasm.js"` to each platform's `js` array too, right before `"core/sqlite-export.js"`:

```json
      "js": [
        "core/adapter-interface.js",
        "core/topbar.js",
        "core/settings-panel.js",
        "core/storage.js",
        "vendor/sql-wasm.js",
        "core/sqlite-export.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

`sql-wasm.js`'s companion `.wasm` binary is fetched at runtime relative to the script's own location — since it's now also loaded as a content script (running in the page's origin, not the extension's), the WASM fetch needs to resolve via `chrome.runtime.getURL`. Check `vendor/sql-wasm.js` for how it locates the `.wasm` file (it accepts a `locateFile` callback, already passed in `core/sqlite-export.js`'s `exportAll`: `f => '../vendor/' + f`). This relative path assumes execution from `popup/` (one level below repo root) — **from a content script's perspective this relative path is wrong** (content scripts don't have a meaningful relative-URL base tied to the extension's file structure the way an extension page does). Fix `core/sqlite-export.js`'s default `locateFile` to always use an absolute extension URL instead of a relative one:

In `core/sqlite-export.js`, find:

```js
  async function exportAll(words, sentences, opts = {}) {
    const SQL = await initSqlJs({
      locateFile: opts.locateFile || (f => '../vendor/' + f)
    });
```

Replace with:

```js
  async function exportAll(words, sentences, opts = {}) {
    const SQL = await initSqlJs({
      locateFile: opts.locateFile || (f => chrome.runtime.getURL('vendor/' + f))
    });
```

This works correctly from both the popup (an extension page, where `chrome.runtime.getURL` is also valid) and content scripts, so `popup.js`'s call site (Task 1, unchanged) doesn't need any `opts` override anymore — remove the now-redundant relative-path assumption entirely rather than keeping two code paths.

Finally, the `.wasm` binary itself (`vendor/sql-wasm.wasm`, referenced by `sql-wasm.js` at runtime) must be declared in `web_accessible_resources` so a content-script-context fetch via `chrome.runtime.getURL` is actually allowed to load it. In `manifest.json`'s `web_accessible_resources` array, add a new entry:

```json
    {
      "resources": ["vendor/sql-wasm.wasm"],
      "matches": ["https://www.youtube.com/*", "https://www.netflix.com/*", "https://www.disneyplus.com/*", "https://*.coupangplay.com/*"]
    }
```

- [ ] **Step 7: Manual verification**

1. Reload the unpacked extension, open a supported video page.
2. Click "설정" in the top bar — confirm the settings panel opens with all sections rendered (모국어 chips, 표시 모드, 2 sliders, 미리보기, 내보내기 buttons).
3. Click a different 모국어 chip — confirm it becomes active and the real subtitle's native line (if currently showing) updates language-wise is not expected here (language doesn't change subtitle *source*, just labels elsewhere — confirm no console error).
4. Drag/click each slider's ticks — confirm the number badge updates, the preview text resizes live, and the real overlay subtitle (if visible) also resizes.
5. Click "스크립트 내보내기" — confirm the existing HTML export downloads (regression check, unchanged behavior).
6. Click "저장 항목 내보내기" — confirm a `.sqlite` file downloads successfully (this is the new cross-context path — the one most likely to break if the `web_accessible_resources`/`locateFile` fix in Step 6 is wrong; watch DevTools console for a WASM fetch 404).
7. Click ✕ in the settings panel header — confirm it closes; click "설정" again — confirms it reopens correctly (not stuck).

- [ ] **Step 8: Commit**

```bash
git add core/settings-panel.js core/script-panel.js core/sqlite-export.js core/adapter-interface.js ui/overlay.css manifest.json
git commit -m "feat: add settings panel (language, mode, independent size sliders, export)"
```

---

### Task 4: Script panel — search, saved-state, auto-scroll toggle

**Files:**
- Modify: `core/script-panel.js`
- Modify: `ui/overlay.css` (append new styles)

**Interfaces:**
- Consumes: `window.EH.Storage` (existing — used already by the panel's save button; this task additionally needs a way to check whether a sentence is *already* saved, added as a new pure function in this same file — see Step 1).
- Produces: no new `window.EH.*` surface — `window.EH.ScriptPanel`'s existing 4-method shape is unchanged, this task only adds internal DOM/behavior.

- [ ] **Step 1: Write a pure matcher function and verify it standalone**

The "already saved" check needs to compare a script line's `cue.text` against the `original` field of already-saved sentences. Add this as a small pure function near the top of `core/script-panel.js` (after `_escapeHtml`, before `_buildExportHtml`):

```js
  /**
   * Returns the Set of enCue texts that are already saved as sentences,
   * so renderList() can show a checkmark instead of "+"  for those lines.
   * Pure — takes the already-fetched sentence list, does no I/O itself.
   * @param {{original: string}[]} savedSentences
   * @returns {Set<string>}
   */
  function savedTextSet(savedSentences) {
    return new Set((savedSentences || []).map(s => s.original));
  }

  /**
   * Case/whitespace-insensitive substring match used by the search box.
   * Pure — no DOM access.
   * @param {string} query
   * @param {{text: string}} enCue
   * @param {string} nativeText
   * @returns {boolean}
   */
  function matchesQuery(query, enCue, nativeText) {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return enCue.text.toLowerCase().includes(q) || (nativeText || '').toLowerCase().includes(q);
  }
```

Verify with a throwaway Node script (not committed) `/tmp/verify-script-panel-search.js`:

```js
global.window = { EH: {} };
global.document = { addEventListener: () => {} }; // script-panel.js's module IIFE runs top-level DOM calls only inside functions, not at load time, so a stub is enough
global.location = { hostname: 'example.com' };

require('/Users/park/Project2/english-helper-extension/core/script-panel.js');

// savedTextSet / matchesQuery aren't exported on window.EH.ScriptPanel (internal
// helpers) — this script instead re-implements the same two functions inline
// to sanity-check the *logic* in isolation before it's wired into the file,
// since core/script-panel.js's IIFE doesn't expose internals for import.
function savedTextSet(savedSentences) {
  return new Set((savedSentences || []).map(s => s.original));
}
function matchesQuery(query, enCue, nativeText) {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return enCue.text.toLowerCase().includes(q) || (nativeText || '').toLowerCase().includes(q);
}

const saved = savedTextSet([{ original: 'Nothing is ephemeral.' }]);
console.assert(saved.has('Nothing is ephemeral.'), 'exact match found in saved set');
console.assert(!saved.has('Something else.'), 'non-saved text not in set');

console.assert(matchesQuery('', { text: 'anything' }, '') === true, 'empty query matches everything');
console.assert(matchesQuery('ephemeral', { text: 'Nothing is ephemeral.' }, '') === true, 'substring match (English)');
console.assert(matchesQuery('EPHEMERAL', { text: 'Nothing is ephemeral.' }, '') === true, 'case-insensitive match');
console.assert(matchesQuery('덧없', { text: 'Nothing is ephemeral.' }, '인생에서 덧없지 않은 것은 없다.') === true, 'matches native text too');
console.assert(matchesQuery('xyz', { text: 'Nothing is ephemeral.' }, '') === false, 'no match returns false');

console.log('OK — all assertions passed');
```

Run: `node /tmp/verify-script-panel-search.js`
Expected: `OK — all assertions passed`. Delete the temp file after.

- [ ] **Step 2: Add search box + saved-state + auto-scroll state to `createDOM`**

In `core/script-panel.js`, find the `createDOM` function's header-building section:

```js
    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);
```

Replace with (adds a search row between the header and the list, and an auto-scroll toggle in a new footer row):

```js
    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const searchRow = document.createElement('div');
    searchRow.className = 'eh-panel-search-row';
    searchRow.innerHTML = '<input type="text" id="eh-panel-search" class="eh-panel-search-input" placeholder="검색">';
    panel.appendChild(searchRow);

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    const footer = document.createElement('div');
    footer.className = 'eh-panel-footer';
    footer.innerHTML =
      '<span class="eh-panel-footer-count" id="eh-panel-footer-count"></span>' +
      `<span class="eh-panel-autoscroll${autoScrollEnabled ? ' on' : ''}" id="eh-panel-autoscroll">자동 스크롤</span>`;
    panel.appendChild(footer);

    searchRow.querySelector('#eh-panel-search').addEventListener('input', (e) => {
      searchQuery = e.target.value;
      renderList();
    });

    footer.querySelector('#eh-panel-autoscroll').addEventListener('click', (e) => {
      autoScrollEnabled = !autoScrollEnabled;
      e.currentTarget.classList.toggle('on', autoScrollEnabled);
    });
```

- [ ] **Step 3: Add the new module-level state**

Near the top of `core/script-panel.js`, find:

```js
  let enCues = [];
  let nativeCues = [];
  let lastActiveIdx = -1;
```

Replace with:

```js
  let enCues = [];
  let nativeCues = [];
  let lastActiveIdx = -1;
  let searchQuery = '';
  let autoScrollEnabled = true;
  let savedSet = new Set();
```

- [ ] **Step 4: Filter + saved-state in `renderList`**

Find the current `renderList` function:

```js
  function renderList() {
    const list = document.getElementById('eh-panel-list');
    if (!list) return;
    if (!enCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">자막 없음</div>';
      return;
    }
    const s = window.EH.settings;
    list.innerHTML = '';
    enCues.forEach((cue, idx) => {
      const native = findNativeText(cue);
      const item = document.createElement('div');
      item.className = 'eh-panel-item';
      item.dataset.idx = idx;

      const time = document.createElement('span');
      time.className = 'eh-panel-time';
      time.textContent = formatTime(cue.start);

      const textWrap = document.createElement('div');
      textWrap.className = 'eh-panel-textwrap';

      const enSpan = document.createElement('span');
      enSpan.className = 'eh-panel-en';
      enSpan.textContent = cue.text;
      textWrap.appendChild(enSpan);

      if (native) {
        const nativeSpan = document.createElement('span');
        nativeSpan.className = 'eh-panel-native';
        nativeSpan.textContent = native;
        nativeSpan.style.display = s.mode === 'en' ? 'none' : 'block';
        textWrap.appendChild(nativeSpan);
      }

      const saveBtn = document.createElement('button');
      saveBtn.className = 'eh-panel-item-save';
      saveBtn.textContent = '＋';
      saveBtn.title = '문장 저장';
      saveBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        window.EH.Storage.saveSentence({
          original: cue.text,
          translation: native,
          timestamp: cue.start
        }).then(() => window.EH.showToast?.('✓ 문장 저장됨'));
      });

      item.appendChild(time);
      item.appendChild(textWrap);
      item.appendChild(saveBtn);
      item.addEventListener('click', () => window.EH.adapter.seekTo(cue.start + 0.1));
      list.appendChild(item);
    });
  }
```

Replace with (adds filtering by `searchQuery`, and a saved/unsaved button state driven by `savedSet`):

```js
  function renderList() {
    const list = document.getElementById('eh-panel-list');
    if (!list) return;
    if (!enCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">자막 없음</div>';
      return;
    }
    const s = window.EH.settings;
    const visibleCues = enCues
      .map((cue, idx) => ({ cue, idx, native: findNativeText(cue) }))
      .filter(({ cue, native }) => matchesQuery(searchQuery, cue, native));

    if (!visibleCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">검색 결과가 없습니다</div>';
      return;
    }

    list.innerHTML = '';
    visibleCues.forEach(({ cue, idx, native }) => {
      const item = document.createElement('div');
      item.className = 'eh-panel-item';
      item.dataset.idx = idx;

      const time = document.createElement('span');
      time.className = 'eh-panel-time';
      time.textContent = formatTime(cue.start);

      const textWrap = document.createElement('div');
      textWrap.className = 'eh-panel-textwrap';

      const enSpan = document.createElement('span');
      enSpan.className = 'eh-panel-en';
      enSpan.textContent = cue.text;
      textWrap.appendChild(enSpan);

      if (native) {
        const nativeSpan = document.createElement('span');
        nativeSpan.className = 'eh-panel-native';
        nativeSpan.textContent = native;
        nativeSpan.style.display = s.mode === 'en' ? 'none' : 'block';
        textWrap.appendChild(nativeSpan);
      }

      const isSaved = savedSet.has(cue.text);
      const saveBtn = document.createElement('button');
      saveBtn.className = 'eh-panel-item-save' + (isSaved ? ' saved' : '');
      saveBtn.textContent = isSaved ? '✓' : '＋';
      saveBtn.title = isSaved ? '이미 저장됨' : '문장 저장';
      saveBtn.disabled = isSaved;
      saveBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (isSaved) return;
        window.EH.Storage.saveSentence({
          original: cue.text,
          translation: native,
          timestamp: cue.start
        }).then(() => {
          savedSet.add(cue.text);
          window.EH.showToast?.('✓ 문장 저장됨');
          renderList();
        });
      });

      item.appendChild(time);
      item.appendChild(textWrap);
      item.appendChild(saveBtn);
      item.addEventListener('click', () => window.EH.adapter.seekTo(cue.start + 0.1));
      list.appendChild(item);
    });

    const countEl = document.getElementById('eh-panel-footer-count');
    if (countEl) countEl.textContent = `이 영상에서 저장 ${savedSet.size}`;
  }
```

- [ ] **Step 5: Load `savedSet` when the panel is set up**

Find the `setup` function:

```js
  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        console.log('[EH:panel] onTracksReady — enCues:', enCues.length, 'nativeCues:', nativeCues.length, 'listEl:', !!document.getElementById('eh-panel-list'));
        renderList();
      });
    }

    renderList();
  }
```

Replace with (fetches the current sentence list once via the existing `chrome.runtime.sendMessage({type:'GET_ALL'})` pattern, same as `topbar.js`/`popup.js` already use):

```js
  async function loadSavedSet() {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      savedSet = savedTextSet((res && res.sentences) || []);
    } catch (_) {
      savedSet = new Set();
    }
  }

  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    loadSavedSet().then(renderList);

    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        console.log('[EH:panel] onTracksReady — enCues:', enCues.length, 'nativeCues:', nativeCues.length, 'listEl:', !!document.getElementById('eh-panel-list'));
        renderList();
      });
    }

    renderList();
  }
```

- [ ] **Step 6: Gate auto-scroll in `highlight`**

Find:

```js
  function highlight(enText) {
    if (!enText) return;
    const idx = enCues.findIndex(c => c.text === enText);
    if (idx === -1 || idx === lastActiveIdx) return;
    lastActiveIdx = idx;
    document.querySelectorAll('.eh-panel-item').forEach(el => el.classList.remove('active'));
    const active = document.querySelector(`.eh-panel-item[data-idx="${idx}"]`);
    if (active) {
      active.classList.add('active');
      active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }
```

Replace with:

```js
  function highlight(enText) {
    if (!enText) return;
    const idx = enCues.findIndex(c => c.text === enText);
    if (idx === -1 || idx === lastActiveIdx) return;
    lastActiveIdx = idx;
    document.querySelectorAll('.eh-panel-item').forEach(el => el.classList.remove('active'));
    const active = document.querySelector(`.eh-panel-item[data-idx="${idx}"]`);
    if (active) {
      active.classList.add('active');
      if (autoScrollEnabled) active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }
```

- [ ] **Step 7: Add search/footer/saved-button styles**

Append to `ui/overlay.css`:

```css
.eh-panel-search-row { flex: none; padding: 8px 14px; border-bottom: 1px solid rgba(var(--eh-text-rgb), 0.07); }
.eh-panel-search-input {
  width: 100%; height: 32px; box-sizing: border-box;
  padding: 0 11px; border-radius: 8px;
  background: rgba(var(--eh-text-rgb), 0.05);
  border: 1px solid rgba(var(--eh-text-rgb), 0.1);
  color: var(--eh-text); font-family: var(--eh-font-body); font-size: 12.5px;
  outline: none;
}
.eh-panel-search-input:focus { border-color: rgba(var(--eh-gold-rgb), 0.4); }

.eh-panel-item-save.saved { color: var(--eh-gold); opacity: 1; cursor: default; }

.eh-panel-footer {
  flex: none; display: flex; align-items: center; gap: 8px;
  padding: 11px 14px; border-top: 1px solid rgba(var(--eh-text-rgb), 0.07);
}
.eh-panel-footer-count { font: 10.5px var(--eh-font-mono); color: rgba(var(--eh-text-rgb), 0.3); flex: 1; }
.eh-panel-autoscroll {
  font: 600 10px var(--eh-font-mono); letter-spacing: 0.06em;
  color: rgba(var(--eh-text-rgb), 0.4);
  border: 1px solid rgba(var(--eh-text-rgb), 0.14);
  padding: 3px 7px; border-radius: 4px; cursor: pointer;
}
.eh-panel-autoscroll.on { color: var(--eh-gold-strong); border-color: rgba(var(--eh-gold-rgb), 0.3); }
```

- [ ] **Step 8: Manual verification**

1. Reload the unpacked extension, open a supported video with a long-ish caption track.
2. Open the script panel — confirm a search box appears above the list and a footer with a per-video save count + "자동 스크롤" toggle appears below.
3. Type a word known to be in the captions — confirm the list filters to matching lines only; clear the search — confirm the full list returns.
4. Type something not in the captions — confirm "검색 결과가 없습니다" shows.
5. Click "＋" on a line to save it — confirm it turns into a disabled "✓" and the footer count increments; reload the panel (or replay `setup`) — confirm the checkmark persists (matches actual storage, not just in-memory).
6. Click "자동 스크롤" to turn it off — confirm playing the video no longer auto-scrolls the list to the active line, but `.active` highlighting itself still updates. Turn it back on — confirm scrolling resumes.

- [ ] **Step 9: Commit**

```bash
git add core/script-panel.js ui/overlay.css
git commit -m "feat: add search, saved-state indicator, and auto-scroll toggle to script panel"
```

---

### Task 5: Style token cleanup + `ui/tokens.css` correction + full regression pass

**Files:**
- Modify: `ui/tokens.css` (fix the stale header comment)
- Modify: `core/word-popup.js` — no code change expected, verify only (see Step 2)
- Modify: `ui/overlay.css` — sweep for any remaining raw hex literals that duplicate an existing `--eh-*` token

**Interfaces:**
- Consumes: nothing new — this task is a cleanup + verification pass over everything Tasks 1-4 built.
- Produces: nothing consumed by later tasks (last task in the plan).

- [ ] **Step 1: Fix the stale `ui/tokens.css` comment**

In `ui/tokens.css`, find:

```css
/* ── English Helper 디자인 토큰 ──────────────────────────
 * 영상 위 UI(오버레이/패널/팝업)에서 쓰는 "어둡게" 표면의 색상·폰트 값.
```

Replace with:

```css
/* ── English Helper 디자인 토큰 ──────────────────────────
 * 영상 위 UI(오버레이/패널/상단 설정 바/설정 패널)에서 쓰는 "어둡게" 표면의
 * 색상·폰트 값. 확장 프로그램 툴바 팝업(popup/)은 더 이상 이 다크 토큰을
 * 쓰지 않는다 — 저장한 표현을 다시 읽는 화면이라 밝은 앱 테마를 쓴다
 * (§1a "자막은 어둡게, 학습은 밝게").
```

- [ ] **Step 2: Sweep `ui/overlay.css` for un-tokenized colors**

Read through `ui/overlay.css` in full (it now includes everything from Tasks 2-4 appended). For any `rgba(255, ...)`/`#fff`/raw hex color literal that is NOT already one of the intentional new non-token colors documented in this plan (e.g. `#000` preview background, `rgba(21, 24, 29, 0.97)` settings panel background — both deliberate one-off values from the mockup, not generic text/surface colors), replace it with the matching `var(--eh-*)` token from `ui/tokens.css`. This is a manual read-and-fix pass, not a mechanical find/replace — the goal is catching anything that should have used `--eh-text-rgb`/`--eh-gold-rgb`/etc. but was typed as a literal by mistake while writing Tasks 2-4.

- [ ] **Step 3: Full manual regression checklist**

Run through the complete flow on a real supported video page (per spec §9):

1. Top bar renders with correct platform badge; both toggles work; save count is accurate and updates after saving a word/sentence.
2. Settings panel opens/closes correctly from the top bar's 설정 button; all controls (언어/모드/2개 슬라이더) apply live to the real subtitle overlay.
3. Word click still opens the word popup and both save buttons still work (regression check for Task 2-3's DOM additions not interfering with `core/subtitle-engine.js`'s existing click handler).
4. Script panel search/saved-state/auto-scroll all work as verified in Task 4, and the panel's own export button (⬇, unchanged from before) still works.
5. Both settings-panel export buttons (스크립트/저장 항목) work.
6. Existing drag-to-reposition and resize-handle behavior on the subtitle overlay still works exactly as before (§3 of the spec — this must not regress).
7. Popup (`popup/popup.html`) — 단어 tab's SQLite export still works (Task 1 regression check).

- [ ] **Step 4: Commit**

```bash
git add ui/tokens.css ui/overlay.css
git commit -m "docs: correct ui/tokens.css's stale popup reference, sweep overlay.css for un-tokenized colors"
```

---

## Self-Review Notes

- **Spec coverage:** §3 (드래그/리사이즈 유지 결정) → explicitly called out as a Global Constraint, verified in Task 5 Step 3 item 6. §4 (상단 바) → Task 2. §5 (설정 패널: 항목 전부, 데이터 흐름) → Task 3. §6 (스크립트 패널 확장: 검색/저장상태/자동스크롤) → Task 4. §7 (스타일 정합) → Task 5. §8 (에러 처리: 검색 무결과, export 실패 폴백) → covered in Task 3 Step 2's export button and Task 4 Step 4's empty-search state. §9 (테스트: 수동 체크리스트) → each task's "Manual verification" step + Task 5's full regression pass. §10 (범위 밖) → confirmed no task adds `.srt`/`.txt` export or touches 1g/onboarding/adapters.
- **Placeholder scan:** none found — every step has literal code or an exact manual-verification checklist.
- **Type consistency:** `window.EH.SqliteExport.exportAll(words, sentences)` signature matches between Task 1's definition and Task 3's settings-panel call site. `window.EH.ScriptPanel.exportScript` matches between Task 3 Step 1's export addition and Task 3 Step 2's call site. `savedTextSet`/`matchesQuery` names and shapes match between Task 4's definition (Step 1) and usage (Steps 4-5).
- **Cross-task file ownership:** `core/adapter-interface.js`'s module-registration block is edited by both Task 2 and Task 3 (each appends one line) — dispatch order must be 2 before 3 so Task 3's diff context matches. `manifest.json`'s 4 `content_scripts.js` arrays are touched by Tasks 1, 2, and 3 in sequence (each inserting its own new file at a specific position) — dispatch strictly in order 1 → 2 → 3 → 4 → 5, no parallelization, since each task's manifest edit assumes the previous task's insertion already landed.
- **DB/isolation discipline:** not applicable to this plan — no `chrome.storage`/`sqflite` test-isolation concerns exist here since there's no automated test suite for this codebase area; the closest analogue (Node verification scripts in Tasks 1 and 4) are explicitly throwaway/uncommitted, avoiding any risk of polluting the real repo with test-only files.
