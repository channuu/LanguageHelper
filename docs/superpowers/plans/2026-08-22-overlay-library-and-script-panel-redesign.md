# 영상 오버레이 — 저장 목록 패널 & 스크립트 패널 재설계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the toolbar popup entirely, add a new video-overlay "저장 목록"(library) panel that replaces the popup's word/sentence browsing + SQLite export, and redesign the script panel (search count, filter chips, copy button, NOW badge, real auto-scroll switch, expand-to-fixed-size) to match the latest `English Helper UI.dc.html` §1h/1i mockup.

**Architecture:** Same established pattern as the prior video-overlay-redesign branch — each new UI piece is a self-contained IIFE registered on `window.EH.*`, initialized from `core/adapter-interface.js`'s `init(adapter)`, styled via `ui/tokens.css` variables in `ui/overlay.css`, wired into all 4 platform `content_scripts` arrays in `manifest.json`. Cross-module coordination (mutual-exclusion between panels, save-count refresh) uses lightweight `document`-level `CustomEvent`s, never new `chrome.runtime` message types.

**Tech Stack:** Vanilla JS (ES2020, IIFE modules), `chrome.storage.local`/`chrome.runtime` messaging, `sql.js` (vendored, via the existing `core/sqlite-export.js`), `navigator.clipboard` (new, for the script panel's copy button).

## Global Constraints

- No new package dependencies.
- No new `chrome.runtime` message types — reuse `GET_ALL`/`SAVE_WORD`/`SAVE_SENTENCE`/`APPLY_SETTINGS`/`TOGGLE_OVERLAY`/`TOGGLE_PANEL`. Cross-panel coordination is DOM `CustomEvent`s only.
- Existing subtitle drag/resize (`core/subtitle-engine.js`) and script export (HTML-only, `ScriptPanel.exportScript`) stay untouched — no `.srt`/`.txt` export formats added.
- Saved-state matching stays **text-based** (existing `savedTextSet`/`matchesQuery` pattern), not the mockup's time-based `scSavedIds` — this is a deliberate, documented deviation (spec §8).
- Follow the existing `window.EH.*` IIFE-module convention and `#eh-*`/`.eh-*` CSS naming convention.
- This repo has no automated JS test framework for `core/`. Pure/isolatable logic (filter-chip + search combination, etc.) gets a throwaway Node verification script (not committed); DOM/`chrome.*`-dependent behavior is manual-verification-only, consistent with every prior task in this project area.
- Panel mutual exclusion (설정 ↔ 저장 목록) and topbar button active-state both use a 4-event contract: `eh-settings-opened`, `eh-settings-closed`, `eh-library-opened`, `eh-library-closed`, dispatched from each panel's own `show()`/`hide()`.
- Script panel's ⤢ expand button: on YouTube, clicking it force-switches the panel from `#secondary`-embedded mode to `fixed-mode` at a larger width (reusing the existing `fixed-mode` CSS/JS path, not inventing a new layout mode); on non-YouTube platforms (already always `fixed-mode`), it just widens/heightens the existing fixed panel. Clicking again reverts.

---

### Task 1: Remove toolbar popup and icon

**Files:**
- Delete: `popup/popup.html`, `popup/popup.js`
- Modify: `manifest.json` (remove `action` block, add `icons/*.png` to `web_accessible_resources`)
- Modify: `background/service_worker.js` (remove dead `TOGGLE_EXTENSION` case)

**Interfaces:**
- Produces: `chrome.runtime.getURL('icons/icon48.png')` becomes resolvable from content-script context (needed by Task 2's topbar icon).
- No consumers yet in this task — Task 2 is the first to rely on the new `web_accessible_resources` entry.

- [ ] **Step 1: Delete the popup directory's files**

```bash
git rm popup/popup.html popup/popup.js
```

(`popup/` directory itself will be empty after this — leave it, git doesn't track empty directories, no further action needed.)

- [ ] **Step 2: Remove the `action` block from `manifest.json`**

In `manifest.json`, find:

```json
  "action": {
    "default_popup": "popup/popup.html",
    "default_icon": {
      "16": "icons/icon16.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png"
    }
  },

  "icons": {
```

Replace with:

```json
  "icons": {
```

(The top-level `"icons"` block stays — it's used for the `chrome://extensions` management page entry, unrelated to the toolbar action.)

- [ ] **Step 3: Add `icons/*.png` to `web_accessible_resources`**

In `manifest.json`, find the `web_accessible_resources` array's last entry (`ui/fonts/*.woff2`):

```json
    {
      "resources": ["ui/fonts/*.woff2"],
      "matches": [
        "https://www.youtube.com/*",
        "https://www.netflix.com/*",
        "https://www.disneyplus.com/*",
        "https://*.coupangplay.com/*"
      ]
    }
  ]
```

Replace with (adds a new entry after it):

```json
    {
      "resources": ["ui/fonts/*.woff2"],
      "matches": [
        "https://www.youtube.com/*",
        "https://www.netflix.com/*",
        "https://www.disneyplus.com/*",
        "https://*.coupangplay.com/*"
      ]
    },
    {
      "resources": ["icons/*.png"],
      "matches": [
        "https://www.youtube.com/*",
        "https://www.netflix.com/*",
        "https://www.disneyplus.com/*",
        "https://*.coupangplay.com/*"
      ]
    }
  ]
```

- [ ] **Step 4: Remove the dead `TOGGLE_EXTENSION` case**

In `background/service_worker.js`, find:

```js
    case 'TOGGLE_EXTENSION': {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, { type: 'TOGGLE_OVERLAY' }).catch(() => {});
      return { success: true };
    }

    default:
```

Replace with:

```js
    default:
```

- [ ] **Step 5: Verify `manifest.json` is still valid JSON**

Run: `python3 -c "import json; json.load(open('manifest.json')); print('OK')"`
Expected: `OK`

- [ ] **Step 6: Manual verification**

1. Load the unpacked extension (`chrome://extensions` → reload).
2. Confirm no toolbar icon for English Helper appears next to the address bar.
3. Confirm the extension still loads without errors on a supported video page (top bar, overlay still work — unaffected by this task, but a quick sanity check here catches a manifest typo early).

- [ ] **Step 7: Commit**

```bash
git add -A -- popup/ manifest.json background/service_worker.js
git commit -m "feat: remove toolbar popup and icon, all UI now lives in the video overlay"
```

---

### Task 2: Top bar — icon, "저장 목록" button, panel active-state highlighting

**Files:**
- Modify: `core/topbar.js`
- Modify: `ui/overlay.css`

**Interfaces:**
- Consumes: `chrome.runtime.getURL('icons/icon48.png')` (Task 1). Existing `eh-overlay-toggled`/`eh-panel-toggled`/`eh-item-saved` events (unchanged).
- Produces: dispatches `eh-library-toggle` CustomEvent (no detail) when the new button is clicked — Task 3's library panel listens for this to toggle itself, mirroring the existing `eh-settings-toggle` pattern. Also listens for and reacts to `eh-settings-opened`/`eh-settings-closed`/`eh-library-opened`/`eh-library-closed` (Task 3 dispatches the `eh-library-*` pair; `core/settings-panel.js` needs the `eh-settings-*` pair added in this same task, since topbar needs both sides working together — see Step 3).

- [ ] **Step 1: Add the icon image to the brand area**

In `core/topbar.js`, find:

```js
    const brand = document.createElement('div');
    brand.className = 'eh-topbar-brand';
    const meta = adapter.getPlatformMeta?.() || { platform: '' };
    brand.innerHTML =
      '<span class="eh-topbar-name">English Helper</span>' +
      `<span class="eh-topbar-badge">${esc((meta.platform || '').toUpperCase())}</span>`;
    bar.appendChild(brand);
```

Replace with:

```js
    const brand = document.createElement('div');
    brand.className = 'eh-topbar-brand';
    const meta = adapter.getPlatformMeta?.() || { platform: '' };
    brand.innerHTML =
      `<img class="eh-topbar-icon" src="${chrome.runtime.getURL('icons/icon48.png')}" alt="">` +
      '<span class="eh-topbar-name">English Helper</span>' +
      `<span class="eh-topbar-badge">${esc((meta.platform || '').toUpperCase())}</span>`;
    bar.appendChild(brand);
```

- [ ] **Step 2: Replace the static count with a clickable "저장 목록" button**

In `core/topbar.js`, find:

```js
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

    // 팝업 등 다른 UI에서 SubtitleEngine/ScriptPanel을 직접 토글한 경우에도
    // 스위치 표시가 어긋나지 않도록 동기화 (여기서는 다시 toggle()을 호출하지 않는다).
    document.addEventListener('eh-overlay-toggled', (e) => {
      if (!overlayToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      overlayOn = e.detail.visible;
      updateToggleState(overlayToggleRef, overlayOn);
    });
    document.addEventListener('eh-panel-toggled', (e) => {
      if (!panelToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      panelOn = e.detail.visible;
      updateToggleState(panelToggleRef, panelOn);
    });
    // 단어/문장 저장 시마다 카운트 재조회 (팝업/패널에서 dispatch)
    document.addEventListener('eh-item-saved', () => {
      refreshCount(count);
    });
  }
```

Replace with:

```js
    const spacer = document.createElement('div');
    spacer.style.flex = '1';
    bar.appendChild(spacer);

    const libBtn = document.createElement('div');
    libBtn.id = 'eh-topbar-library';
    libBtn.className = 'eh-topbar-lib-btn';
    libBtn.innerHTML =
      '<svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round">' +
      '<path d="M3.2 1.9h6.6a1 1 0 0 1 1 1v8.2l-4.3-2.4-4.3 2.4V2.9a1 1 0 0 1 1-1z"></path></svg>' +
      '<span>저장 목록</span>' +
      '<span class="eh-topbar-lib-count" id="eh-topbar-lib-count"></span>';
    libBtn.addEventListener('click', () => {
      document.dispatchEvent(new CustomEvent('eh-library-toggle'));
    });
    bar.appendChild(libBtn);
    refreshCount(libBtn.querySelector('#eh-topbar-lib-count'));

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

    // 팝업 등 다른 UI에서 SubtitleEngine/ScriptPanel을 직접 토글한 경우에도
    // 스위치 표시가 어긋나지 않도록 동기화 (여기서는 다시 toggle()을 호출하지 않는다).
    document.addEventListener('eh-overlay-toggled', (e) => {
      if (!overlayToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      overlayOn = e.detail.visible;
      updateToggleState(overlayToggleRef, overlayOn);
    });
    document.addEventListener('eh-panel-toggled', (e) => {
      if (!panelToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      panelOn = e.detail.visible;
      updateToggleState(panelToggleRef, panelOn);
    });
    // 단어/문장 저장 시마다 라이브러리 버튼의 개수 배지 재조회
    document.addEventListener('eh-item-saved', () => {
      refreshCount(libBtn.querySelector('#eh-topbar-lib-count'));
    });

    // 설정/라이브러리 패널의 열림·닫힘에 맞춰 해당 버튼에 active 스타일 적용
    document.addEventListener('eh-settings-opened', () => settingsBtn.classList.add('active'));
    document.addEventListener('eh-settings-closed', () => settingsBtn.classList.remove('active'));
    document.addEventListener('eh-library-opened', () => libBtn.classList.add('active'));
    document.addEventListener('eh-library-closed', () => libBtn.classList.remove('active'));
  }
```

- [ ] **Step 3: Add the `eh-settings-*`/`eh-library-*` open/close event dispatch to `core/settings-panel.js`**

This step belongs to this task because the topbar's active-state listeners added in Step 2 need a dispatcher on both sides to be useful — without this, `eh-settings-opened`/`eh-settings-closed` never fire and the settings button never highlights.

In `core/settings-panel.js`, find:

```js
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
```

Replace with:

```js
  function show() {
    open = true;
    render();
    panelEl.classList.remove('hidden');
    document.dispatchEvent(new CustomEvent('eh-settings-opened'));
  }

  function hide() {
    open = false;
    panelEl.classList.add('hidden');
    document.dispatchEvent(new CustomEvent('eh-settings-closed'));
  }

  function toggle() {
    if (open) hide(); else show();
  }

  function setup() {
    createDOM();
    document.addEventListener('eh-settings-toggle', toggle);
    // 라이브러리 패널이 열리면 설정 패널은 닫혀 상호 배타적으로 유지한다.
    document.addEventListener('eh-library-opened', () => { if (open) hide(); });
  }
```

- [ ] **Step 4: Add top-bar CSS for the icon and the new library button**

In `ui/overlay.css`, find:

```css
.eh-topbar-brand { display: flex; align-items: baseline; gap: 7px; }
```

Replace with:

```css
.eh-topbar-brand { display: flex; align-items: baseline; gap: 7px; }
.eh-topbar-icon { width: 20px; height: 20px; display: block; align-self: center; }
```

Then find:

```css
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

Replace with:

```css
.eh-topbar-lib-btn,
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
.eh-topbar-lib-btn:hover,
.eh-topbar-settings-btn:hover { border-color: rgba(var(--eh-gold-rgb), 0.4); color: var(--eh-gold); }
.eh-topbar-lib-btn.active,
.eh-topbar-settings-btn.active {
  background: rgba(var(--eh-gold-rgb), 0.16);
  border-color: rgba(var(--eh-gold-rgb), 0.4);
  color: var(--eh-gold);
}
.eh-topbar-lib-count { font: 10.5px var(--eh-font-mono); opacity: 0.7; }
```

(The old `.eh-topbar-count` rule is removed since nothing references `#eh-topbar-count` anymore after Step 2.)

- [ ] **Step 5: Manual verification**

1. Reload the unpacked extension, open a supported video page.
2. Confirm the English Helper icon image renders next to the "English Helper" text in the top bar.
3. Confirm "저장 목록" button shows with a bookmark icon and a count badge matching the total saved words+sentences.
4. Save a word or sentence — confirm the badge updates without reloading.
5. Click "저장 목록" — confirm it visually highlights (background/border change) even though the library panel doesn't exist yet (Task 3) — check DevTools console for a clean `CustomEvent` dispatch with no errors.
6. Click "설정" — confirm it opens as before, and now visually highlights while open; click ✕ inside the settings panel — confirm the settings button un-highlights.

- [ ] **Step 6: Commit**

```bash
git add core/topbar.js core/settings-panel.js ui/overlay.css
git commit -m "feat: add top bar icon and clickable 저장 목록 button, panel active-state highlighting"
```

---

### Task 3: New library panel — `core/library-panel.js`

**Files:**
- Create: `core/library-panel.js`
- Modify: `ui/overlay.css`
- Modify: `core/adapter-interface.js`
- Modify: `manifest.json` (all 4 `content_scripts` entries)

**Interfaces:**
- Consumes: `chrome.runtime.sendMessage({type:'GET_ALL'})` (existing pattern), `window.EH.SqliteExport.exportAll` (existing, Task 1 of the prior branch), `window.EH.adapter.getPlatformMeta().contentId` / `adapter.seekTo(seconds)` (existing `SubtitleAdapter` contract), the `eh-library-toggle` event (Task 2).
- Produces: `window.EH.LibraryPanel = { setup(adapter) }`. Dispatches `eh-library-opened`/`eh-library-closed` (consumed by Task 2's topbar and by `core/settings-panel.js`'s mutual-exclusion listener added in Task 2 Step 3).

- [ ] **Step 1: Create the library panel module**

Create `core/library-panel.js`:

```js
(function () {
  'use strict';

  let panelEl = null;
  let open = false;
  let tab = 'w'; // 'w' | 's'
  let words = [];
  let sentences = [];

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  async function loadData() {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      words = (res && res.words) || [];
      sentences = (res && res.sentences) || [];
    } catch (_) {
      words = [];
      sentences = [];
    }
  }

  function currentVideoCount() {
    const contentId = window.EH.adapter?.getPlatformMeta?.()?.contentId;
    if (!contentId) return 0;
    return words.filter(w => w.contentId === contentId).length +
           sentences.filter(s => s.contentId === contentId).length;
  }

  function render() {
    const items = tab === 'w' ? words : sentences;
    panelEl.innerHTML = `
      <div class="eh-library-header">
        <span class="eh-library-title">SAVED LIBRARY</span>
        <span class="eh-library-close" id="eh-library-close">✕</span>
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

  function wordCard(w) {
    return `
      <div class="eh-library-card">
        <div class="eh-library-card-head">
          <span class="eh-library-card-word">${esc(w.word)}</span>
          <span class="eh-library-card-plat">${esc(w.platform || '')}</span>
        </div>
        <div class="eh-library-card-ko">${esc(w.translation || '')}</div>
        <div class="eh-library-jump" data-timestamp="${w.timestamp || 0}">▸ ${formatTime(w.timestamp || 0)}</div>
      </div>`;
  }

  function sentenceCard(s) {
    return `
      <div class="eh-library-card">
        <div class="eh-library-card-en">${esc(s.original)}</div>
        <div class="eh-library-card-ko">${esc(s.translation || '')}</div>
        <div class="eh-library-jump" data-timestamp="${s.timestamp || 0}">▸ ${formatTime(s.timestamp || 0)}</div>
      </div>`;
  }

  function createDOM() {
    if (document.getElementById('eh-library-panel')) {
      panelEl = document.getElementById('eh-library-panel');
      return;
    }
    panelEl = document.createElement('div');
    panelEl.id = 'eh-library-panel';
    panelEl.classList.add('hidden');
    document.body.appendChild(panelEl);
  }

  async function show() {
    open = true;
    await loadData();
    render();
    panelEl.classList.remove('hidden');
    document.dispatchEvent(new CustomEvent('eh-library-opened'));
  }

  function hide() {
    open = false;
    panelEl.classList.add('hidden');
    document.dispatchEvent(new CustomEvent('eh-library-closed'));
  }

  function toggle() {
    if (open) hide(); else show();
  }

  function setup() {
    createDOM();
    document.addEventListener('eh-library-toggle', toggle);
    // 설정 패널이 열리면 라이브러리 패널은 닫혀 상호 배타적으로 유지한다.
    document.addEventListener('eh-settings-opened', () => { if (open) hide(); });
  }

  window.EH = window.EH || {};
  window.EH.LibraryPanel = { setup };
})();
```

- [ ] **Step 2: Add library panel CSS**

Append to `ui/overlay.css`:

```css
#eh-library-panel {
  position: fixed;
  top: 52px; right: 132px; bottom: 16px;
  z-index: 2147483001;
  width: 330px;
  display: flex;
  flex-direction: column;
  background: rgba(21, 24, 29, 0.97);
  border: 1px solid rgba(var(--eh-gold-rgb), 0.2);
  border-radius: 14px;
  box-shadow: 0 24px 50px rgba(var(--eh-black-rgb), 0.55);
  overflow: hidden;
  font-family: var(--eh-font-body);
}
#eh-library-panel.hidden { display: none !important; }

.eh-library-header {
  flex: none; display: flex; align-items: center;
  padding: 13px 15px 0;
}
.eh-library-title { font: 600 10.5px var(--eh-font-mono); letter-spacing: 0.12em; color: var(--eh-gold-strong); flex: 1; }
.eh-library-close { color: rgba(var(--eh-text-rgb), 0.4); font-size: 13px; cursor: pointer; }
.eh-library-close:hover { color: var(--eh-text); }

.eh-library-tabs {
  flex: none; display: flex; align-items: baseline; gap: 16px;
  padding: 12px 15px 0;
  margin-top: 12px;
  border-bottom: 1px solid rgba(var(--eh-text-rgb), 0.08);
}
.eh-library-tab {
  padding-bottom: 9px; cursor: pointer;
  font: 600 12.5px var(--eh-font-body);
  color: rgba(var(--eh-text-rgb), 0.42);
}
.eh-library-tab.active { color: var(--eh-text); box-shadow: inset 0 -2px 0 var(--eh-gold-strong); }
.eh-library-video-count { font: 10.5px var(--eh-font-mono); color: rgba(var(--eh-text-rgb), 0.3); padding-bottom: 9px; }

.eh-library-list { flex: 1; min-height: 0; overflow: auto; padding: 12px 15px; display: flex; flex-direction: column; gap: 7px; }
.eh-library-empty { padding: 24px 0; text-align: center; color: rgba(var(--eh-text-rgb), 0.3); font-size: 12px; }

.eh-library-card {
  background: rgba(var(--eh-text-rgb), 0.04);
  border: 1px solid rgba(var(--eh-text-rgb), 0.08);
  border-radius: 10px;
  padding: 10px 12px;
}
.eh-library-card-head { display: flex; align-items: baseline; gap: 7px; }
.eh-library-card-word { font-weight: 600; font-size: 14.5px; color: var(--eh-text); }
.eh-library-card-plat {
  font: 600 9px var(--eh-font-mono); letter-spacing: 0.06em;
  padding: 2px 6px; border-radius: 3px;
  background: rgba(var(--eh-text-rgb), 0.07); color: rgba(var(--eh-text-rgb), 0.5);
  margin-left: auto;
}
.eh-library-card-en { font-size: 13.5px; line-height: 1.5; color: var(--eh-text); }
.eh-library-card-ko { font-size: 12px; color: rgba(var(--eh-text-rgb), 0.6); margin-top: 4px; }
.eh-library-jump {
  font: 10.5px var(--eh-font-mono); color: var(--eh-gold-strong);
  margin-top: 8px; cursor: pointer;
}

.eh-library-footer { flex: none; padding: 12px 15px; border-top: 1px solid rgba(var(--eh-text-rgb), 0.08); }
.eh-library-export-btn {
  height: 42px; border-radius: 10px;
  background: var(--eh-accent); color: #14161f;
  display: flex; align-items: center; gap: 8px; padding: 0 13px;
  font: 600 12.5px var(--eh-font-body); cursor: pointer;
}
.eh-library-export-ext { margin-left: auto; font: 10.5px var(--eh-font-mono); opacity: 0.62; }
.eh-library-hint { font-size: 11px; line-height: 1.55; color: rgba(var(--eh-text-rgb), 0.32); margin-top: 9px; }
```

- [ ] **Step 3: Register in `adapter-interface.js`**

In `core/adapter-interface.js`, find:

```js
    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.TopBar)         window.EH.TopBar.setup(adapter);
    if (window.EH.SettingsPanel)  window.EH.SettingsPanel.setup(adapter);
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
```

Replace with:

```js
    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.TopBar)         window.EH.TopBar.setup(adapter);
    if (window.EH.SettingsPanel)  window.EH.SettingsPanel.setup(adapter);
    if (window.EH.LibraryPanel)   window.EH.LibraryPanel.setup(adapter);
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
```

- [ ] **Step 4: Add to `manifest.json`**

Add `"core/library-panel.js"` immediately after `"core/settings-panel.js"` in each of the 4 platform `content_scripts` entries. The YouTube entry's `js` array becomes:

```json
      "js": [
        "core/adapter-interface.js",
        "core/topbar.js",
        "core/settings-panel.js",
        "core/library-panel.js",
        "core/storage.js",
        "vendor/sql-wasm.js",
        "core/sqlite-export.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
```

Apply the same one-line insertion to the netflix, disneyplus, and coupangplay entries.

- [ ] **Step 5: Manual verification**

1. Reload the unpacked extension, open a supported video page with some words/sentences already saved.
2. Click "저장 목록" — confirm the library panel opens with 단어/문장 tabs showing correct counts, and "이 영상 N" showing the current video's count.
3. Switch tabs — confirm cards render correctly for both words and sentences.
4. Click a card's "▸ 시간" — confirm the video seeks to that timestamp.
5. Click "SQLite 내보내기" — confirm a `.sqlite` file downloads.
6. With the library panel open, click "설정" — confirm the library panel closes and the settings panel opens (mutual exclusion). Reverse: open settings, then click "저장 목록" — confirm settings closes.
7. Save a new word/sentence, reopen the library panel — confirm the new item and count appear (panel re-fetches on every open).

- [ ] **Step 6: Commit**

```bash
git add core/library-panel.js core/adapter-interface.js ui/overlay.css manifest.json
git commit -m "feat: add saved-library panel (word/sentence tabs, seek-to-time, SQLite export)"
```

---

### Task 4: Script panel — search count badge, filter chips, copy button, NOW badge, real auto-scroll switch

**Files:**
- Modify: `core/script-panel.js`
- Modify: `ui/overlay.css`

**Interfaces:**
- Consumes: existing `matchesQuery`/`savedTextSet`/`loadSavedSet` (Task 4 of the prior branch, unchanged logic, extended with a filter-chip dimension in this task).
- Produces: no new `window.EH.*` surface — `window.EH.ScriptPanel`'s 5-method shape (`setup, highlight, toggle, applySettings, exportScript`) is unchanged.

- [ ] **Step 1: Add filter-chip pure logic and verify it standalone**

Add this pure function near `matchesQuery` in `core/script-panel.js` (after it):

```js
  /**
   * Combines the search-query match with the saved/unsaved filter chip.
   * Pure — no DOM access.
   * @param {'all'|'saved'|'unsaved'} filter
   * @param {boolean} isSaved
   * @returns {boolean}
   */
  function matchesFilter(filter, isSaved) {
    if (filter === 'saved') return isSaved;
    if (filter === 'unsaved') return !isSaved;
    return true;
  }
```

Verify with a throwaway Node script (not committed) `/tmp/verify-script-panel-filter.js`:

```js
function matchesFilter(filter, isSaved) {
  if (filter === 'saved') return isSaved;
  if (filter === 'unsaved') return !isSaved;
  return true;
}

console.assert(matchesFilter('all', true) === true, 'all matches saved');
console.assert(matchesFilter('all', false) === true, 'all matches unsaved');
console.assert(matchesFilter('saved', true) === true, 'saved matches saved item');
console.assert(matchesFilter('saved', false) === false, 'saved rejects unsaved item');
console.assert(matchesFilter('unsaved', false) === true, 'unsaved matches unsaved item');
console.assert(matchesFilter('unsaved', true) === false, 'unsaved rejects saved item');

console.log('OK — all assertions passed');
```

Run: `node /tmp/verify-script-panel-filter.js` (if `node` isn't available in the environment, hand-trace each assertion line by line and record the trace in the report instead — same fallback used throughout this project's prior tasks). Expected: `OK — all assertions passed`. Delete the temp file after.

- [ ] **Step 2: Add module-level filter state**

In `core/script-panel.js`, find:

```js
  let searchQuery = '';
  let autoScrollEnabled = true;
  let savedSet = new Set();
```

Replace with:

```js
  let searchQuery = '';
  let autoScrollEnabled = true;
  let savedSet = new Set();
  let saveFilter = 'all'; // 'all' | 'saved' | 'unsaved'
```

- [ ] **Step 3: Add the video-title row, search count badge, and filter chips to `createDOM`**

In `core/script-panel.js`, find:

```js
    const searchRow = document.createElement('div');
    searchRow.className = 'eh-panel-search-row';
    searchRow.innerHTML = '<input type="text" id="eh-panel-search" class="eh-panel-search-input" placeholder="검색">';
    panel.appendChild(searchRow);
```

Replace with:

```js
    const titleRow = document.createElement('div');
    titleRow.className = 'eh-panel-title-row';
    titleRow.id = 'eh-panel-title-row';
    panel.appendChild(titleRow);

    const searchRow = document.createElement('div');
    searchRow.className = 'eh-panel-search-row';
    searchRow.innerHTML =
      '<input type="text" id="eh-panel-search" class="eh-panel-search-input" placeholder="스크립트 검색">' +
      '<span class="eh-panel-search-count" id="eh-panel-search-count"></span>';
    panel.appendChild(searchRow);

    const filterRow = document.createElement('div');
    filterRow.className = 'eh-panel-filter-row';
    filterRow.innerHTML = `
      <div class="eh-panel-filter-chip active" data-filter="all">전체</div>
      <div class="eh-panel-filter-chip" data-filter="saved">저장한 줄</div>
      <div class="eh-panel-filter-chip" data-filter="unsaved">미저장</div>
    `;
    panel.appendChild(filterRow);
    filterRow.querySelectorAll('.eh-panel-filter-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        saveFilter = chip.dataset.filter;
        filterRow.querySelectorAll('.eh-panel-filter-chip').forEach(c => c.classList.toggle('active', c === chip));
        renderList();
      });
    });
```

- [ ] **Step 4: Set the video title once tracks/adapter are known**

In `core/script-panel.js`, find the `setup(adapter)` function's opening:

```js
  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
```

Replace with:

```js
  function setup(adapter) {
    createDOM();
    const titleRow = document.getElementById('eh-panel-title-row');
    if (titleRow) titleRow.textContent = adapter.getPlatformMeta?.()?.title || '';
    const tracks = adapter.getSubtitleTracks();
```

- [ ] **Step 5: Rewrite `renderList()` to apply the filter chip, add NOW badge, copy button, and search-count badge**

Find the current `renderList()` function (starting `function renderList() {` through its closing `}` before `highlight`). Replace it entirely with:

```js
  function renderList() {
    const list = document.getElementById('eh-panel-list');
    if (!list) return;
    if (!enCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">자막 없음</div>';
      return;
    }
    const s = window.EH.settings;
    const withMeta = enCues.map((cue, idx) => ({
      cue, idx, native: findNativeText(cue), isSaved: savedSet.has(cue.text)
    }));
    const visibleCues = withMeta.filter(({ cue, native, isSaved }) =>
      matchesQuery(searchQuery, cue, native) && matchesFilter(saveFilter, isSaved));

    const searchCountEl = document.getElementById('eh-panel-search-count');
    if (searchCountEl) {
      searchCountEl.textContent = searchQuery.trim() ? `${visibleCues.length}건` : `${enCues.length}줄`;
    }

    if (!visibleCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">검색 결과가 없습니다</div>';
      return;
    }

    list.innerHTML = '';
    visibleCues.forEach(({ cue, idx, native, isSaved }) => {
      const isActive = idx === lastActiveIdx;

      const item = document.createElement('div');
      item.className = 'eh-panel-item';
      item.dataset.idx = idx;

      const timeCol = document.createElement('div');
      timeCol.className = 'eh-panel-time-col';
      timeCol.innerHTML =
        `<span class="eh-panel-time">${formatTime(cue.start)}</span>` +
        (isActive ? '<span class="eh-panel-now">NOW</span>' : '');
      timeCol.addEventListener('click', (e) => {
        e.stopPropagation();
        window.EH.adapter.seekTo(cue.start + 0.1);
      });

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

      const actions = document.createElement('div');
      actions.className = 'eh-panel-item-actions';

      const copyBtn = document.createElement('button');
      copyBtn.className = 'eh-panel-item-copy';
      copyBtn.textContent = '⧉';
      copyBtn.title = '영어 문장 복사';
      copyBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (navigator.clipboard) navigator.clipboard.writeText(cue.text).catch(() => {});
        copyBtn.classList.add('copied');
        copyBtn.textContent = '✓';
        setTimeout(() => {
          copyBtn.classList.remove('copied');
          copyBtn.textContent = '⧉';
        }, 1400);
      });

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
          document.dispatchEvent(new CustomEvent('eh-item-saved'));
          renderList();
        });
      });

      actions.appendChild(copyBtn);
      actions.appendChild(saveBtn);

      item.appendChild(timeCol);
      item.appendChild(textWrap);
      item.appendChild(actions);
      list.appendChild(item);
    });

    const countEl = document.getElementById('eh-panel-footer-count');
    if (countEl) countEl.textContent = `저장 ${savedSet.size} / ${enCues.length}줄`;
  }
```

(Note: the line's own click-to-seek handler moved from the whole `item` to just `timeCol`, per the mockup's "타임코드를 눌러 이동" behavior principle — clicking the text body no longer seeks, only the time column does.)

- [ ] **Step 6: Replace the auto-scroll text badge with a real toggle switch**

In `core/script-panel.js`, find:

```js
    const footer = document.createElement('div');
    footer.className = 'eh-panel-footer';
    footer.innerHTML =
      '<span class="eh-panel-footer-count" id="eh-panel-footer-count"></span>' +
      `<span class="eh-panel-autoscroll${autoScrollEnabled ? ' on' : ''}" id="eh-panel-autoscroll">자동 스크롤</span>`;
    panel.appendChild(footer);
```

Replace with:

```js
    const footer = document.createElement('div');
    footer.className = 'eh-panel-footer';
    footer.innerHTML =
      '<span class="eh-panel-footer-count" id="eh-panel-footer-count"></span>' +
      `<div class="eh-panel-autoscroll-toggle" id="eh-panel-autoscroll">` +
      `<span class="eh-panel-autoscroll-switch${autoScrollEnabled ? ' on' : ''}"><span class="eh-panel-autoscroll-knob"></span></span>` +
      `<span class="eh-panel-autoscroll-label${autoScrollEnabled ? '' : ' dim'}">자동 스크롤</span>` +
      `</div>`;
    panel.appendChild(footer);
```

And find:

```js
    footer.querySelector('#eh-panel-autoscroll').addEventListener('click', (e) => {
      autoScrollEnabled = !autoScrollEnabled;
      e.currentTarget.classList.toggle('on', autoScrollEnabled);
    });
```

Replace with:

```js
    footer.querySelector('#eh-panel-autoscroll').addEventListener('click', () => {
      autoScrollEnabled = !autoScrollEnabled;
      const el = footer.querySelector('#eh-panel-autoscroll');
      el.querySelector('.eh-panel-autoscroll-switch').classList.toggle('on', autoScrollEnabled);
      el.querySelector('.eh-panel-autoscroll-label').classList.toggle('dim', !autoScrollEnabled);
    });
```

- [ ] **Step 7: Update `highlight()` to trigger a full re-render (needed for the NOW badge)**

In `core/script-panel.js`, find:

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
      // NOW 배지는 렌더링 시점에 결정되므로, 활성 줄이 바뀔 때마다 다시 그린다.
      renderList();
      const reActive = document.querySelector(`.eh-panel-item[data-idx="${idx}"]`);
      if (autoScrollEnabled && reActive) reActive.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }
```

- [ ] **Step 8: Add CSS for the title row, search count, filter chips, copy button, NOW badge, and toggle switch**

Append to `ui/overlay.css`:

```css
.eh-panel-title-row {
  flex: none; padding: 2px 14px 0;
  font-size: 12px; color: rgba(var(--eh-text-rgb), 0.5);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}

.eh-panel-search-row { display: flex; align-items: center; gap: 8px; }
.eh-panel-search-count { font: 10.5px var(--eh-font-mono); color: rgba(var(--eh-text-rgb), 0.32); flex-shrink: 0; }

.eh-panel-filter-row { flex: none; display: flex; gap: 6px; padding: 8px 14px 0; }
.eh-panel-filter-chip {
  padding: 4px 9px; border-radius: 12px; cursor: pointer;
  font: 600 11px var(--eh-font-body);
  background: rgba(var(--eh-text-rgb), 0.04);
  color: rgba(var(--eh-text-rgb), 0.5);
  border: 1px solid rgba(var(--eh-text-rgb), 0.09);
  white-space: nowrap;
}
.eh-panel-filter-chip.active {
  background: rgba(var(--eh-gold-rgb), 0.16);
  color: var(--eh-gold);
  border-color: rgba(var(--eh-gold-rgb), 0.4);
}

.eh-panel-time-col { flex: none; width: 34px; padding-top: 2px; cursor: pointer; }
.eh-panel-now {
  display: block; font: 600 8.5px var(--eh-font-mono); letter-spacing: 0.06em;
  color: var(--eh-gold-strong); margin-top: 4px;
}

.eh-panel-item-actions { display: flex; gap: 4px; flex-shrink: 0; opacity: 0; transition: opacity 0.15s; }
.eh-panel-item:hover .eh-panel-item-actions { opacity: 1; }
.eh-panel-item-copy {
  background: none; border: none;
  color: rgba(var(--eh-gold-rgb), 0.4);
  cursor: pointer; font-size: 13px;
  width: 22px; height: 22px; border-radius: 4px;
  display: flex; align-items: center; justify-content: center;
}
.eh-panel-item-copy:hover { color: var(--eh-gold); background: rgba(var(--eh-gold-rgb), 0.1); }
.eh-panel-item-copy.copied { color: var(--eh-gold); }

.eh-panel-autoscroll-toggle { display: flex; align-items: center; gap: 6px; cursor: pointer; }
.eh-panel-autoscroll-switch {
  display: inline-block; width: 28px; height: 16px; border-radius: 8px;
  background: rgba(var(--eh-text-rgb), 0.18); position: relative; transition: background 0.15s;
}
.eh-panel-autoscroll-switch.on { background: var(--eh-accent); }
.eh-panel-autoscroll-knob {
  position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 6px;
  background: var(--eh-text); transition: left 0.15s;
}
.eh-panel-autoscroll-switch.on .eh-panel-autoscroll-knob { left: 14px; }
.eh-panel-autoscroll-label { font: 600 10.5px var(--eh-font-body); color: var(--eh-gold-strong); }
.eh-panel-autoscroll-label.dim { color: rgba(var(--eh-text-rgb), 0.4); }
```

Remove the now-unused old rule (search for and delete it — it's superseded by Step 8's new rules):

```css
.eh-panel-autoscroll {
  font: 600 10px var(--eh-font-mono); letter-spacing: 0.06em;
  color: rgba(var(--eh-text-rgb), 0.4);
  border: 1px solid rgba(var(--eh-text-rgb), 0.14);
  padding: 3px 7px; border-radius: 4px; cursor: pointer;
}
.eh-panel-autoscroll.on { color: var(--eh-gold-strong); border-color: rgba(var(--eh-gold-rgb), 0.3); }
```

- [ ] **Step 9: Manual verification**

1. Reload the unpacked extension, open a supported video with captions.
2. Open the script panel — confirm the video title shows below the header, and the search box has a count badge showing total line count.
3. Type in search — confirm the count badge updates ("N건" while searching).
4. Click each filter chip (전체/저장한 줄/미저장) — confirm the list filters correctly and combines with an active search query.
5. Play the video — confirm the currently active line shows a "NOW" label under its timestamp, and it moves as playback advances.
6. Click the copy icon on a line — confirm it flashes a checkmark for ~1.4s and the English text lands on the clipboard (paste somewhere to confirm), and confirm NO save/checkmark state changes from this action.
7. Click the auto-scroll switch — confirm it's now a real sliding toggle, and toggling off actually stops auto-scroll (as before).
8. Click a line's time column — confirm it seeks; click the line's text body — confirm it does NOT seek.
9. Confirm the footer now reads "저장 N / M줄".

- [ ] **Step 10: Commit**

```bash
git add core/script-panel.js ui/overlay.css
git commit -m "feat: redesign script panel — search count, filter chips, copy button, NOW badge, real auto-scroll switch"
```

---

### Task 5: Script panel — ⤢ expand-to-fixed-size

**Files:**
- Modify: `core/script-panel.js`
- Modify: `ui/overlay.css`

**Interfaces:**
- Consumes: existing `_isYouTube()`, `_setLayoutForPanel()`, the `fixed-mode` CSS class and its existing resize-handle logic (`attachPanelResize`) — all unchanged, reused for the expanded state.
- Produces: no new public interface — purely a header-button behavior addition.

- [ ] **Step 1: Add the ⤢ button to the header**

In `core/script-panel.js`, find:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
```

Replace with:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-expand" title="실제 크기로 확장">⤢</button>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
```

- [ ] **Step 2: Wire the expand button's click handler**

In `core/script-panel.js`, find:

```js
    const collapseBtn = header.querySelector('#eh-panel-collapse');
    const hideBtn     = header.querySelector('#eh-panel-hide');
    const exportBtn   = header.querySelector('#eh-panel-export');

    exportBtn.addEventListener('click', exportScript);
```

Replace with:

```js
    const collapseBtn = header.querySelector('#eh-panel-collapse');
    const hideBtn     = header.querySelector('#eh-panel-hide');
    const exportBtn   = header.querySelector('#eh-panel-export');
    const expandBtn   = header.querySelector('#eh-panel-expand');

    exportBtn.addEventListener('click', exportScript);

    let expanded = false;
    expandBtn.addEventListener('click', () => {
      expanded = !expanded;
      expandBtn.classList.toggle('active', expanded);
      if (_isYouTube()) {
        // YouTube: #secondary 임베드는 폭을 우리가 제어할 수 없으므로,
        // 확장 시엔 고정(fixed) 모드로 강제 전환해 더 넓은 폭을 확보한다.
        const wrapper = document.getElementById('eh-panel-wrapper');
        if (expanded) {
          panel.classList.add('fixed-mode', 'expanded');
          if (wrapper) wrapper.classList.add('hidden');
          if (panel.parentElement !== document.body) document.body.appendChild(panel);
        } else {
          panel.classList.remove('fixed-mode', 'expanded');
          if (wrapper) {
            wrapper.classList.remove('hidden');
            wrapper.appendChild(panel);
          }
        }
      } else {
        panel.classList.toggle('expanded', expanded);
        _setLayoutForPanel(true);
      }
    });
```

- [ ] **Step 3: Add CSS for the expanded state and the active expand-button style**

Append to `ui/overlay.css`:

```css
#eh-panel.fixed-mode.expanded {
  width: 480px;
}
.eh-panel-btn.active { color: var(--eh-gold); background: rgba(var(--eh-gold-rgb), 0.14); }
```

- [ ] **Step 4: Manual verification**

1. Reload the unpacked extension, open a YouTube video wide enough that the script panel embeds in `#secondary`.
2. Click ⤢ — confirm the panel switches to a wider fixed floating panel on the right (leaving the `#secondary` sidebar area empty/collapsed), and the button visually shows as active.
3. Click ⤢ again — confirm it returns to the embedded `#secondary` layout.
4. Open a non-YouTube supported site (or narrow the YouTube window so it's already in fixed-mode fallback) — click ⤢ — confirm the panel just widens in place, click again — confirm it returns to its normal width.
5. Confirm the panel's existing manual resize-drag handle still works in both expanded and non-expanded states.

- [ ] **Step 5: Commit**

```bash
git add core/script-panel.js ui/overlay.css
git commit -m "feat: add script panel expand-to-fixed-size (⤢) button"
```

---

### Task 6: Settings panel slider tick precision fix

**Files:**
- Modify: `core/settings-panel.js`

**Interfaces:**
- Consumes/Produces: none — pure constant-value correction, no interface change.

- [ ] **Step 1: Update `EN_TICKS`/`KO_TICKS` to the latest mockup values**

In `core/settings-panel.js`, find:

```js
  // 9 ticks spanning the existing 12–52px enSize range and 10–48px nativeSize range.
  const EN_TICKS = [12, 17, 22, 27, 32, 37, 42, 47, 52];
  const KO_TICKS = [10, 14, 18, 22, 26, 30, 34, 41, 48];
```

Replace with:

```js
  // 2026-08-22 목업 재확인 값 그대로 사용 (§1h/1i DCLogic enTicks/koTicks).
  const EN_TICKS = [12, 17, 22, 26, 31, 36, 41, 46, 52];
  const KO_TICKS = [10, 14, 18, 22, 26, 32, 38, 44, 48];
```

- [ ] **Step 2: Manual verification**

1. Reload the unpacked extension, open a supported video page, open 설정 패널.
2. Confirm both sliders show 9 ticks and the values displayed when clicking the last tick read 52px (영어) and 48px (모국어), matching before/after — this fix only changes the middle 5 values (26/31/36/41/46 and 26/32/38/44 respectively), not the endpoints, so no visually obvious regression is expected — just closer alignment to the mockup's exact steps.

- [ ] **Step 3: Commit**

```bash
git add core/settings-panel.js
git commit -m "fix: correct settings panel slider tick values to match latest mockup"
```

---

## Self-Review Notes

- **Spec coverage:** §3 (팝업/아이콘 제거) → Task 1. §4 (상단 바 변경: 아이콘, 저장 목록 버튼) → Task 2. §5 (라이브러리 패널) → Task 3. §6 (스크립트 패널 재설계: 검색 배지/필터 칩/복사 버튼/NOW 배지/⤢ 확장/자동스크롤 스위치/푸터 형식) → Tasks 4-5. §7 (슬라이더 눈금) → Task 6. §8 (텍스트 기반 저장 매칭 유지) → confirmed unchanged in Task 4 (no rewrite of `savedTextSet`). §9 (에러 처리: SQLite 실패 롤백, 클립보드 실패 무시, seek 실패 무시) → Task 3 Step 1's export handler, Task 4 Step 5's copy handler, Task 3's `seekTo` calls all use optional chaining / try-catch consistent with existing patterns. §10 (테스트) → each task's manual verification + Task 4's Node/hand-trace step. §11 (범위 밖) → confirmed no task touches subtitle-engine drag/resize, adds new export formats, or adds delete/edit to the library panel.
- **Placeholder scan:** none found — every step has literal code or an exact manual-verification checklist.
- **Type consistency:** `window.EH.LibraryPanel.setup(adapter)` matches between Task 3's definition and Task 3 Step 3's `adapter-interface.js` registration. `eh-library-toggle`/`eh-library-opened`/`eh-library-closed`/`eh-settings-opened`/`eh-settings-closed` event names and payload shapes (`eh-library-toggle`/`eh-settings-toggle` carry no detail; the `-opened`/`-closed` pairs also carry no detail, matching how `updateToggleState`-style consumers only need the event's occurrence, not a value) are used identically across Task 2 (topbar dispatch + listen), Task 3 (library-panel dispatch + listen), and Task 2 Step 3 (settings-panel dispatch + listen) — no naming drift.
- **Cross-task file ownership:** `core/settings-panel.js` is touched by Task 2 (Step 3, open/close event dispatch) and Task 6 (tick values) — dispatch strictly in order 2 → 6 so Task 6's diff context matches. `core/script-panel.js` is touched by Task 4 and Task 5 in sequence (Task 5's header-button insertion assumes Task 4's already-modified `renderList`/footer are in place) — dispatch strictly 4 → 5, no parallelization. `manifest.json` is touched only by Task 1 (action removal, web_accessible_resources) and Task 3 (content_scripts insertion) — no ordering conflict since they touch disjoint parts of the file, but dispatch in plan order (1 → 3) regardless for a clean diff history.
