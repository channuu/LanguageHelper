# English Helper Phase A — Core Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 어댑터 패턴 기반 Chrome Extension 코어 인프라 구축 — 플랫폼 어댑터가 공유하는 SubtitleEngine, ScriptPanel, WordPopup, StorageAdapter 구현

**Architecture:** `core/` 파일들이 `window.EH` 네임스페이스에 API를 노출하고, 각 플랫폼 어댑터가 마지막에 로드되어 `window.EH.init(adapter)` 를 호출해 전체를 활성화한다. MV3 content script는 ES 모듈 미지원이므로 파일을 순서대로 주입해 공유 스코프를 활용한다.

**Tech Stack:** Chrome Extension MV3, Vanilla JS (ES2020), Free Dictionary API (api.dictionaryapi.dev), sql.js (SQLite export)

## Global Constraints

- manifest_version: 3
- ES 모듈 import/export 사용 불가 (content script 제약) — window.EH 네임스페이스 사용
- 모든 core 파일은 IIFE로 감싸 전역 오염 방지, window.EH에만 노출
- chrome.storage.local 키: `eh-words`, `eh-sentences`, `eh-settings`
- 데이터 ID: crypto.randomUUID() 사용
- 기존 `content/youtube.js`, `content/netflix.js` 는 Task 1에서 삭제 (어댑터로 교체됨)
- `inject/page_script.js`, `content/youtube_inject.js` 는 유지 (YouTube 캡션 인터셉트 전용)

---

## File Map

| 파일 | 역할 | 신규/수정 |
|------|------|---------|
| `manifest.json` | Disney+/쿠팡 추가, content script 경로 변경 | 수정 |
| `core/adapter-interface.js` | SubtitleAdapter 베이스 클래스, window.EH 네임스페이스 초기화 | 신규 |
| `core/storage.js` | StorageAdapter (chrome.storage CRUD) | 신규 |
| `core/subtitle-engine.js` | 이중자막 오버레이 렌더링, 드래그/리사이즈 | 신규 |
| `core/script-panel.js` | 사이드패널 (타임라인, 하이라이트, seek) | 신규 |
| `core/word-popup.js` | 단어 클릭 팝업, Free Dictionary API | 신규 |
| `background/service_worker.js` | 메시지 핸들러 업데이트 (TRANSLATE_BATCH 제거, 새 스키마) | 수정 |
| `content/youtube.js` | **삭제** (adapters/youtube.js 로 교체) | 삭제 |
| `content/netflix.js` | **삭제** (adapters/netflix.js 로 교체) | 삭제 |

---

### Task 1: Directory scaffold + manifest.json 업데이트

**Files:**
- Create: `core/` (디렉토리)
- Create: `adapters/` (디렉토리)
- Create: `ui/` (디렉토리)
- Create: `vendor/` (디렉토리, sql.js 저장 용도)
- Modify: `manifest.json`
- Delete: `content/youtube.js`, `content/netflix.js`

**Interfaces:**
- Produces: manifest.json이 4개 플랫폼에 올바른 content script 주입 순서를 선언

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p core adapters ui vendor
```

Expected: 4개 디렉토리 생성, 오류 없음

- [ ] **Step 2: 기존 파일 삭제**

```bash
rm content/youtube.js content/netflix.js
```

Expected: 두 파일 삭제 (youtube_inject.js, overlay.css 는 유지)

- [ ] **Step 3: sql.js 다운로드**

```bash
# sql.js v1.12.0 WASM 빌드 다운로드
curl -L https://github.com/sql-js/sql.js/releases/download/v1.12.0/sqljs-wasm.zip -o /tmp/sqljs.zip
unzip /tmp/sqljs.zip sql-wasm.js sql-wasm.wasm -d vendor/
```

Expected: `vendor/sql-wasm.js`, `vendor/sql-wasm.wasm` 생성

- [ ] **Step 4: manifest.json 전체 교체**

```json
{
  "manifest_version": 3,
  "name": "English Helper",
  "version": "2.0.0",
  "description": "YouTube/Netflix/Disney+/쿠팡플레이 이중 자막 학습 + 단어 저장",

  "permissions": ["storage", "activeTab", "tabs"],

  "host_permissions": [
    "https://www.youtube.com/*",
    "https://www.netflix.com/*",
    "https://www.disneyplus.com/*",
    "https://play.coupang.com/*",
    "https://api.dictionaryapi.dev/*"
  ],

  "background": {
    "service_worker": "background/service_worker.js"
  },

  "content_scripts": [
    {
      "matches": ["https://www.youtube.com/*"],
      "js": ["content/youtube_inject.js"],
      "run_at": "document_start"
    },
    {
      "matches": ["https://www.youtube.com/*"],
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/youtube.js"
      ],
      "css": ["ui/overlay.css"],
      "run_at": "document_idle"
    },
    {
      "matches": ["https://www.netflix.com/*"],
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/netflix.js"
      ],
      "css": ["ui/overlay.css"],
      "run_at": "document_idle"
    },
    {
      "matches": ["https://www.disneyplus.com/*"],
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/disney.js"
      ],
      "css": ["ui/overlay.css"],
      "run_at": "document_idle"
    },
    {
      "matches": ["https://play.coupang.com/*"],
      "js": [
        "core/adapter-interface.js",
        "core/storage.js",
        "core/subtitle-engine.js",
        "core/script-panel.js",
        "core/word-popup.js",
        "adapters/coupang.js"
      ],
      "css": ["ui/overlay.css"],
      "run_at": "document_idle"
    }
  ],

  "action": {
    "default_popup": "popup/popup.html",
    "default_icon": {
      "16": "icons/icon16.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png"
    }
  },

  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  },

  "web_accessible_resources": [
    {
      "resources": ["inject/page_script.js"],
      "matches": ["https://www.youtube.com/*"]
    },
    {
      "resources": ["vendor/sql-wasm.wasm"],
      "matches": ["<all_urls>"]
    }
  ]
}
```

- [ ] **Step 5: 수동 검증**

Chrome `chrome://extensions` → 개발자 모드 → "압축해제된 확장 프로그램 로드" → 폴더 선택
Expected: 오류 없이 로드됨 (content script 파일이 아직 없어 경고는 무시)

- [ ] **Step 6: 커밋**

```bash
git add manifest.json vendor/ && git rm content/youtube.js content/netflix.js
git commit -m "feat: scaffold adapter pattern structure, update manifest for 4 platforms"
```

---

### Task 2: core/adapter-interface.js — SubtitleAdapter 인터페이스 + window.EH 네임스페이스

**Files:**
- Create: `core/adapter-interface.js`

**Interfaces:**
- Produces:
  - `window.EH` — 글로벌 네임스페이스 객체
  - `window.EH.SubtitleAdapter` — 베이스 클래스 (모든 어댑터가 extends)
  - `window.EH.init(adapter)` — 어댑터 등록 + 전체 초기화 트리거
  - `window.EH.settings` — 현재 설정 객체 `{ enSize, nativeSize, mode, nativeLang }`

- [ ] **Step 1: core/adapter-interface.js 작성**

```js
(function () {
  'use strict';

  window.EH = window.EH || {};

  /**
   * 모든 플랫폼 어댑터가 구현해야 하는 계약.
   * 신규 플랫폼 추가 = 이 클래스를 extends한 파일 하나만 adapters/ 에 추가.
   */
  class SubtitleAdapter {
    /** @returns {{ lang: string, cues: {start: number, end: number, text: string}[] }[]} */
    getSubtitleTracks() { throw new Error('getSubtitleTracks() not implemented'); }

    /** @returns {number} 현재 재생 위치 (초) */
    getCurrentTime() { throw new Error('getCurrentTime() not implemented'); }

    /** @param {number} seconds */
    seekTo(seconds) { throw new Error('seekTo() not implemented'); }

    /** @param {function({lang: string, text: string}[]): void} callback */
    onSubtitleChange(callback) { throw new Error('onSubtitleChange() not implemented'); }

    /** @param {function(number): void} callback */
    onTimeUpdate(callback) { throw new Error('onTimeUpdate() not implemented'); }

    /** @returns {{ platform: string, title: string, contentId: string }} */
    getPlatformMeta() { throw new Error('getPlatformMeta() not implemented'); }

    /** 이벤트 리스너 정리 */
    destroy() {}
  }

  const DEFAULT_SETTINGS = { enSize: 22, nativeSize: 18, mode: 'both', nativeLang: 'ko' };

  /**
   * 어댑터가 준비되면 호출. 코어 모듈들을 순서대로 초기화한다.
   * @param {SubtitleAdapter} adapter
   */
  async function init(adapter) {
    if (!(adapter instanceof SubtitleAdapter)) {
      console.error('[EH] adapter must extend SubtitleAdapter');
      return;
    }
    window.EH.adapter = adapter;

    const stored = await chrome.storage.local.get('eh-settings');
    window.EH.settings = { ...DEFAULT_SETTINGS, ...(stored['eh-settings'] || {}) };

    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
  }

  function applySettings(patch) {
    window.EH.settings = { ...window.EH.settings, ...patch };
    chrome.storage.local.set({ 'eh-settings': window.EH.settings });
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.applySettings(window.EH.settings);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.applySettings(window.EH.settings);
  }

  window.EH.SubtitleAdapter = SubtitleAdapter;
  window.EH.init = init;
  window.EH.applySettings = applySettings;
  window.EH.settings = { ...DEFAULT_SETTINGS };

  // 팝업 / service worker 메시지 수신
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'TOGGLE_OVERLAY') {
      window.EH.SubtitleEngine?.toggle();
    }
    if (msg.type === 'TOGGLE_PANEL') {
      window.EH.ScriptPanel?.toggle(msg.visible);
    }
    if (msg.type === 'APPLY_SETTINGS') {
      applySettings(msg.settings);
    }
  });
})();
```

- [ ] **Step 2: Chrome에서 youtube.com 열고 콘솔 확인**

콘솔에서 `window.EH` 입력
Expected: `{ SubtitleAdapter: [class], init: [function], ... }` 객체 확인

- [ ] **Step 3: 커밋**

```bash
git add core/adapter-interface.js
git commit -m "feat: add SubtitleAdapter interface and window.EH namespace"
```

---

### Task 3: core/storage.js + background/service_worker.js 업데이트

**Files:**
- Create: `core/storage.js`
- Modify: `background/service_worker.js`

**Interfaces:**
- Consumes: `window.EH.adapter.getPlatformMeta()` → `{ platform, title, contentId }`
- Produces:
  - `window.EH.Storage.saveWord(wordData)` → `Promise<{ id: string }>`
  - `window.EH.Storage.saveSentence(sentData)` → `Promise<{ id: string }>`
  - `window.EH.Storage.getAll()` → `Promise<{ words: Word[], sentences: Sentence[] }>`
  - `window.EH.Storage.deleteItem(type, id)` → `Promise<void>` (`type`: `'word'|'sentence'`)

- [ ] **Step 1: core/storage.js 작성**

```js
(function () {
  'use strict';

  function generateId() {
    return crypto.randomUUID
      ? crypto.randomUUID()
      : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
          const r = Math.random() * 16 | 0;
          return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
        });
  }

  const Storage = {
    async saveWord({ word, definition, sentence, translation, timestamp }) {
      const meta = window.EH.adapter?.getPlatformMeta() || { platform: 'unknown', title: '', contentId: '' };
      const item = {
        id: generateId(),
        word, definition: definition || '', sentence: sentence || '',
        translation: translation || '',
        platform: meta.platform, contentTitle: meta.title, contentId: meta.contentId,
        timestamp: timestamp || 0,
        savedAt: new Date().toISOString(),
        reviewCount: 0, nextReviewAt: null
      };
      return chrome.runtime.sendMessage({ type: 'SAVE_WORD', payload: item });
    },

    async saveSentence({ original, translation, timestamp }) {
      const meta = window.EH.adapter?.getPlatformMeta() || { platform: 'unknown', title: '', contentId: '' };
      const item = {
        id: generateId(),
        original, translation: translation || '',
        platform: meta.platform, contentTitle: meta.title, contentId: meta.contentId,
        timestamp: timestamp || 0,
        savedAt: new Date().toISOString(),
        reviewCount: 0, nextReviewAt: null
      };
      return chrome.runtime.sendMessage({ type: 'SAVE_SENTENCE', payload: item });
    },

    async getAll() {
      return chrome.runtime.sendMessage({ type: 'GET_ALL' });
    },

    async deleteItem(type, id) {
      return chrome.runtime.sendMessage({ type: 'DELETE_ITEM', payload: { type, id } });
    }
  };

  window.EH = window.EH || {};
  window.EH.Storage = Storage;
})();
```

- [ ] **Step 2: background/service_worker.js 전체 교체**

```js
// background/service_worker.js
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message).then(sendResponse).catch(err => {
    sendResponse({ success: false, error: err.message });
  });
  return true;
});

async function handleMessage(message) {
  switch (message.type) {

    case 'FETCH_CAPTIONS': {
      const base = message.payload.url.replace(/&fmt=[^&]*/g, '');
      for (const fmt of ['srv3', 'srv1', '']) {
        try {
          const url = fmt ? base + '&fmt=' + fmt : base;
          const res  = await fetch(url);
          const text = await res.text();
          if (text && text.length > 10) return { success: true, text, fmt };
        } catch (e) {
          console.warn('[EH BG] fetch captions fmt=' + fmt, e.message);
        }
      }
      return { success: false, error: 'all formats failed' };
    }

    case 'SAVE_WORD': {
      const result = await chrome.storage.local.get('eh-words');
      const words = result['eh-words'] || [];
      words.unshift(message.payload);
      if (words.length > 500) words.splice(500);
      await chrome.storage.local.set({ 'eh-words': words });
      return { success: true, id: message.payload.id };
    }

    case 'SAVE_SENTENCE': {
      const result = await chrome.storage.local.get('eh-sentences');
      const sentences = result['eh-sentences'] || [];
      sentences.unshift(message.payload);
      if (sentences.length > 500) sentences.splice(500);
      await chrome.storage.local.set({ 'eh-sentences': sentences });
      return { success: true, id: message.payload.id };
    }

    case 'GET_ALL': {
      const result = await chrome.storage.local.get(['eh-words', 'eh-sentences']);
      return {
        success: true,
        words: result['eh-words'] || [],
        sentences: result['eh-sentences'] || []
      };
    }

    case 'DELETE_ITEM': {
      const { type, id } = message.payload;
      const key = type === 'word' ? 'eh-words' : 'eh-sentences';
      const result = await chrome.storage.local.get(key);
      const items = (result[key] || []).filter(i => i.id !== id);
      await chrome.storage.local.set({ [key]: items });
      return { success: true };
    }

    case 'TOGGLE_EXTENSION': {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, { type: 'TOGGLE_OVERLAY' }).catch(() => {});
      return { success: true };
    }

    default:
      return { success: false, error: 'Unknown message type: ' + message.type };
  }
}
```

- [ ] **Step 3: 수동 검증 — 저장 테스트**

YouTube 열고 콘솔에서 실행:
```js
window.EH.Storage.saveWord({ word: 'test', definition: 'a test', sentence: 'This is a test.', translation: '이것은 테스트입니다.', timestamp: 10 })
  .then(console.log)
```
Expected: `{ success: true, id: "uuid-string" }`

```js
window.EH.Storage.getAll().then(r => console.log(r.words.length, r.sentences.length))
```
Expected: `1 0`

- [ ] **Step 4: 커밋**

```bash
git add core/storage.js background/service_worker.js
git commit -m "feat: add StorageAdapter with Word/Sentence schema, update service worker"
```

---

### Task 4: core/subtitle-engine.js — 이중 자막 오버레이

**Files:**
- Create: `core/subtitle-engine.js`
- Create: `ui/overlay.css` (content/overlay.css 기반, 단어팝업 스타일 추가)

**Interfaces:**
- Consumes:
  - `window.EH.adapter.onSubtitleChange(cb)` — `cb([{lang, text}])` 형태로 호출
  - `window.EH.adapter.getCurrentTime()` → number
  - `window.EH.settings` → `{ enSize, nativeSize, mode }`
- Produces:
  - `window.EH.SubtitleEngine.setup(adapter)` — 초기화
  - `window.EH.SubtitleEngine.toggle()` — 표시/숨김 토글
  - `window.EH.SubtitleEngine.applySettings(settings)` — 설정 적용
  - DOM event: 단어 span 클릭 시 `window.EH.WordPopup.show(word, sentence, translation, timestamp)` 호출

- [ ] **Step 1: ui/overlay.css 작성** (기존 content/overlay.css 내용 이동 + 단어팝업 스타일 추가)

```css
/* ── 자막 오버레이 ─────────────────────────────── */
#eh-overlay {
  position: fixed;
  bottom: 80px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 9999999;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  pointer-events: all;
  max-width: 80vw;
  text-align: center;
  cursor: grab;
  user-select: none;
}
#eh-overlay.dragging { cursor: grabbing; opacity: 0.85; }
#eh-overlay.hidden   { display: none !important; }

#eh-en-line {
  font-family: 'Georgia', serif;
  font-size: 22px;
  font-weight: 600;
  color: #ffffff;
  text-shadow: 0 0 8px rgba(0,0,0,0.9), 1px 1px 3px rgba(0,0,0,0.8);
  line-height: 1.35;
  user-select: text;
  cursor: text;
}
#eh-native-line {
  font-family: 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif;
  font-size: 18px;
  color: #ffd97a;
  text-shadow: 0 0 8px rgba(0,0,0,0.9);
  line-height: 1.35;
  pointer-events: none;
}
#eh-native-line.hidden { display: none; }

.eh-word {
  cursor: pointer;
  border-radius: 3px;
  padding: 0 2px;
  transition: background 0.12s;
}
.eh-word:hover  { background: rgba(255,217,122,0.45); }
.eh-word:active { background: rgba(255,217,122,0.70); }

#eh-resize-handle {
  position: absolute;
  right: -20px; bottom: -10px;
  width: 22px; height: 22px;
  cursor: ew-resize;
  opacity: 0;
  transition: opacity 0.2s;
}
#eh-resize-handle::after {
  content: "";
  position: absolute;
  right: 2px; bottom: 2px;
  width: 10px; height: 10px;
  border-right: 2.5px solid rgba(255,217,122,0.9);
  border-bottom: 2.5px solid rgba(255,217,122,0.9);
  border-radius: 0 0 3px 0;
}
#eh-overlay:hover #eh-resize-handle { opacity: 1; }

/* ── 토스트 ─────────────────────────────────────── */
#eh-toast {
  position: fixed;
  bottom: 32px; left: 50%;
  transform: translateX(-50%) translateY(10px);
  background: rgba(14,14,16,0.95);
  color: #ffd97a;
  font-family: 'Apple SD Gothic Neo', sans-serif;
  font-size: 14px;
  padding: 10px 20px;
  border-radius: 24px;
  z-index: 10000000;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.25s, transform 0.25s;
  border: 1px solid rgba(255,217,122,0.3);
}
#eh-toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

/* ── 사이드 패널 ─────────────────────────────────── */
#eh-panel {
  position: fixed;
  right: 0; top: 0;
  width: 300px; min-width: 180px; max-width: 520px;
  height: 100vh;
  background: rgba(10,10,14,0.93);
  border-left: 1px solid rgba(255,217,122,0.15);
  z-index: 9999998;
  display: flex;
  flex-direction: column;
  font-family: 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif;
  backdrop-filter: blur(8px);
  transition: transform 0.25s;
  user-select: none;
}
#eh-panel.hidden    { display: none; }
#eh-panel.collapsed { transform: translateX(calc(100% - 32px)); }

.eh-panel-header {
  padding: 12px 12px 12px 14px;
  border-bottom: 1px solid rgba(255,217,122,0.12);
  display: flex; align-items: center; gap: 8px;
  flex-shrink: 0;
}
.eh-panel-title {
  font-size: 12px; font-weight: 500;
  color: #ffd97a; flex: 1;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.eh-panel-btn {
  background: none; border: none;
  color: rgba(255,217,122,0.55);
  cursor: pointer; font-size: 13px;
  width: 24px; height: 24px;
  border-radius: 4px;
  display: flex; align-items: center; justify-content: center;
  transition: color 0.15s, background 0.15s;
}
.eh-panel-btn:hover { color: #ffd97a; background: rgba(255,217,122,0.1); }

.eh-panel-list {
  flex: 1; overflow-y: auto; padding: 4px 0;
}
.eh-panel-list::-webkit-scrollbar { width: 3px; }
.eh-panel-list::-webkit-scrollbar-thumb { background: rgba(255,217,122,0.2); border-radius: 2px; }

.eh-panel-empty {
  padding: 24px 16px;
  text-align: center;
  color: rgba(255,255,255,0.3);
  font-size: 12px;
}

.eh-panel-item {
  display: flex; align-items: flex-start; gap: 8px;
  padding: 8px 12px;
  cursor: pointer;
  border-left: 2px solid transparent;
  transition: background 0.12s, border-color 0.12s;
}
.eh-panel-item:hover  { background: rgba(255,217,122,0.06); }
.eh-panel-item.active {
  background: rgba(255,217,122,0.10);
  border-left-color: #ffd97a;
}
.eh-panel-item-save {
  background: none; border: none;
  color: rgba(255,217,122,0.4);
  cursor: pointer; font-size: 16px;
  padding: 0 4px; flex-shrink: 0;
  opacity: 0; transition: opacity 0.15s, color 0.15s;
}
.eh-panel-item:hover .eh-panel-item-save { opacity: 1; }
.eh-panel-item-save:hover { color: #ffd97a; }

.eh-panel-time {
  font-size: 11px; color: rgba(255,217,122,0.65);
  min-width: 34px; margin-top: 2px;
  font-variant-numeric: tabular-nums; flex-shrink: 0;
}
.eh-panel-item.active .eh-panel-time { color: #ffd97a; }

.eh-panel-textwrap { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
.eh-panel-en { font-size: 12px; color: rgba(255,255,255,0.7); line-height: 1.55; word-break: break-word; }
.eh-panel-item.active .eh-panel-en { color: #fff; }
.eh-panel-native { font-size: 11px; color: rgba(255,217,122,0.65); line-height: 1.4; word-break: break-word; }
.eh-panel-item.active .eh-panel-native { color: rgba(255,217,122,0.9); }

#eh-panel-resize {
  position: absolute; left: -4px; top: 0;
  width: 8px; height: 100%; cursor: ew-resize; z-index: 1;
}

/* ── 단어 팝업 ──────────────────────────────────── */
#eh-word-popup {
  position: fixed;
  background: rgba(14,14,16,0.97);
  border: 1px solid rgba(255,217,122,0.25);
  border-radius: 12px;
  padding: 14px 16px;
  z-index: 10000001;
  min-width: 220px; max-width: 300px;
  font-family: 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif;
  box-shadow: 0 8px 32px rgba(0,0,0,0.6);
  display: none;
}
#eh-word-popup.visible { display: block; }

.eh-popup-word {
  font-family: 'Georgia', serif;
  font-size: 20px; font-weight: 600;
  color: #fff; margin-bottom: 2px;
}
.eh-popup-phonetic {
  font-size: 12px; color: rgba(255,217,122,0.7);
  margin-bottom: 8px;
}
.eh-popup-divider {
  height: 1px; background: rgba(255,217,122,0.12);
  margin: 8px 0;
}
.eh-popup-def {
  font-size: 13px; color: rgba(255,255,255,0.8);
  line-height: 1.55; margin-bottom: 6px;
}
.eh-popup-sentence {
  font-size: 12px; color: rgba(255,255,255,0.45);
  font-style: italic; line-height: 1.5;
}
.eh-popup-actions {
  display: flex; gap: 8px; margin-top: 12px;
}
.eh-popup-btn {
  flex: 1; padding: 7px 0;
  background: rgba(255,217,122,0.08);
  border: 1px solid rgba(255,217,122,0.2);
  border-radius: 8px;
  color: #ffd97a; font-size: 12px;
  cursor: pointer; transition: background 0.15s;
}
.eh-popup-btn:hover { background: rgba(255,217,122,0.18); }
.eh-popup-loading { color: rgba(255,255,255,0.4); font-size: 13px; text-align: center; padding: 12px 0; }
```

- [ ] **Step 2: core/subtitle-engine.js 작성**

```js
(function () {
  'use strict';

  let visible = true;
  let currentEnText = '';
  let currentNativeText = '';
  let rafId = null;

  function createDOM() {
    if (document.getElementById('eh-overlay')) return;

    const overlay = document.createElement('div');
    overlay.id = 'eh-overlay';

    const enLine = document.createElement('div');
    enLine.id = 'eh-en-line';
    overlay.appendChild(enLine);

    const nativeLine = document.createElement('div');
    nativeLine.id = 'eh-native-line';
    overlay.appendChild(nativeLine);

    const handle = document.createElement('div');
    handle.id = 'eh-resize-handle';
    overlay.appendChild(handle);

    document.body.appendChild(overlay);

    const toast = document.createElement('div');
    toast.id = 'eh-toast';
    document.body.appendChild(toast);

    restorePosition(overlay, enLine, nativeLine);
    attachDrag(overlay, enLine, nativeLine);
    attachResize(overlay, enLine, nativeLine, handle);
  }

  function restorePosition(overlay, enLine, nativeLine) {
    const saved = JSON.parse(localStorage.getItem('eh-overlay-pos') || 'null');
    if (saved?.left && saved?.top) {
      overlay.style.left = saved.left;
      overlay.style.top = saved.top;
      overlay.style.bottom = 'auto';
      overlay.style.transform = 'none';
    }
    if (saved?.enSize) enLine.style.fontSize = saved.enSize;
    if (saved?.nativeSize) nativeLine.style.fontSize = saved.nativeSize;
  }

  function attachDrag(overlay, enLine, nativeLine) {
    let dragging = false, sx, sy, ox, oy;
    overlay.addEventListener('mousedown', (e) => {
      if (e.target.id === 'eh-resize-handle' || e.target.classList.contains('eh-word')) return;
      dragging = true;
      overlay.classList.add('dragging');
      const r = overlay.getBoundingClientRect();
      sx = e.clientX; sy = e.clientY; ox = r.left; oy = r.top;
      e.preventDefault();
    });
    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      overlay.style.left = (ox + e.clientX - sx) + 'px';
      overlay.style.top  = (oy + e.clientY - sy) + 'px';
      overlay.style.bottom = 'auto';
      overlay.style.transform = 'none';
    });
    document.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false;
      overlay.classList.remove('dragging');
      savePosition(overlay, enLine, nativeLine);
    });
  }

  function attachResize(overlay, enLine, nativeLine, handle) {
    let resizing = false, startX, startSize;
    handle.addEventListener('mousedown', (e) => {
      e.stopPropagation(); e.preventDefault();
      resizing = true; startX = e.clientX;
      startSize = parseFloat(getComputedStyle(enLine).fontSize) || 22;
      document.body.style.cursor = 'ew-resize';
    });
    document.addEventListener('mousemove', (e) => {
      if (!resizing) return;
      const size = Math.min(52, Math.max(12, startSize + (e.clientX - startX) * 0.35));
      enLine.style.fontSize = size + 'px';
      nativeLine.style.fontSize = Math.round(size * 0.8) + 'px';
    });
    document.addEventListener('mouseup', () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = '';
      savePosition(overlay, enLine, nativeLine);
    });
  }

  function savePosition(overlay, enLine, nativeLine) {
    localStorage.setItem('eh-overlay-pos', JSON.stringify({
      left: overlay.style.left, top: overlay.style.top,
      enSize: enLine.style.fontSize, nativeSize: nativeLine.style.fontSize
    }));
  }

  function renderSubtitles(enText, nativeText) {
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (!enLine || !visible) return;

    if (enText === currentEnText && nativeText === currentNativeText) return;
    currentEnText = enText;
    currentNativeText = nativeText;

    // 영어 자막: 단어별 span으로 분리 (클릭 가능)
    enLine.innerHTML = '';
    if (enText) {
      const s = window.EH.settings;
      enLine.style.fontSize = s.enSize + 'px';
      enText.split(' ').forEach((word, i, arr) => {
        const span = document.createElement('span');
        span.className = 'eh-word';
        span.textContent = word + (i < arr.length - 1 ? ' ' : '');
        span.addEventListener('click', (e) => {
          e.stopPropagation();
          const clean = word.replace(/[^a-zA-Z']/g, '');
          if (clean && window.EH.WordPopup) {
            window.EH.WordPopup.show(clean, enText, nativeText,
              window.EH.adapter?.getCurrentTime() || 0, e.clientX, e.clientY);
          }
        });
        enLine.appendChild(span);
      });
    }

    // 모국어 자막
    const s = window.EH.settings;
    nativeLine.textContent = nativeText || '';
    nativeLine.style.fontSize = s.nativeSize + 'px';
    nativeLine.classList.toggle('hidden', s.mode === 'en' || !nativeText);

    // 스크립트 패널 하이라이트 업데이트
    if (window.EH.ScriptPanel) window.EH.ScriptPanel.highlight(enText);
  }

  function setup(adapter) {
    createDOM();
    adapter.onSubtitleChange((cues) => {
      const en = cues.find(c => c.lang === 'en')?.text || '';
      const native = cues.find(c => c.lang !== 'en')?.text || '';
      renderSubtitles(en, native);
    });
  }

  function applySettings(s) {
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (enLine) enLine.style.fontSize = s.enSize + 'px';
    if (nativeLine) {
      nativeLine.style.fontSize = s.nativeSize + 'px';
      nativeLine.classList.toggle('hidden', s.mode === 'en');
    }
    currentEnText = ''; // 다음 틱에서 강제 재렌더
  }

  function toggle() {
    visible = !visible;
    document.getElementById('eh-overlay')?.classList.toggle('hidden', !visible);
  }

  window.EH = window.EH || {};
  window.EH.SubtitleEngine = { setup, applySettings, toggle };
  window.EH.showToast = function(msg) {
    const t = document.getElementById('eh-toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2500);
  };
})();
```

- [ ] **Step 3: 커밋**

```bash
git add core/subtitle-engine.js ui/overlay.css
git commit -m "feat: add SubtitleEngine with dual subtitle rendering and drag/resize"
```

---

### Task 5: core/script-panel.js — 사이드 패널

**Files:**
- Create: `core/script-panel.js`

**Interfaces:**
- Consumes:
  - `window.EH.adapter.getSubtitleTracks()` → `[{ lang, cues: [{start, end, text}] }]`
  - `window.EH.adapter.seekTo(seconds)`
  - `window.EH.Storage.saveSentence({ original, translation, timestamp })`
- Produces:
  - `window.EH.ScriptPanel.setup(adapter)` — 초기화 + 어댑터 트랙 로드
  - `window.EH.ScriptPanel.highlight(enText)` — 현재 자막 기준 패널 스크롤
  - `window.EH.ScriptPanel.toggle(visible?)` — 표시/숨김
  - `window.EH.ScriptPanel.applySettings(settings)` — 모국어 줄 표시 여부

- [ ] **Step 1: core/script-panel.js 작성**

```js
(function () {
  'use strict';

  let enCues = [];    // [{ start, end, text }]
  let nativeCues = []; // [{ start, end, text }]
  let lastActiveIdx = -1;

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  function findNativeText(enCue) {
    return nativeCues.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';
  }

  function createDOM() {
    if (document.getElementById('eh-panel')) return;

    const panel = document.createElement('div');
    panel.id = 'eh-panel';

    const resizeHandle = document.createElement('div');
    resizeHandle.id = 'eh-panel-resize';
    panel.appendChild(resizeHandle);

    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    document.body.appendChild(panel);

    // 너비 복원
    const savedW = localStorage.getItem('eh-panel-width');
    if (savedW) panel.style.width = savedW;

    document.getElementById('eh-panel-collapse').addEventListener('click', () => {
      const collapsed = panel.classList.toggle('collapsed');
      document.getElementById('eh-panel-collapse').textContent = collapsed ? '▶' : '✕';
    });

    document.getElementById('eh-panel-hide').addEventListener('click', () => {
      panel.classList.add('hidden');
      window.EH.showToast?.('패널 숨김 — 팝업에서 다시 켤 수 있어요');
    });

    attachPanelResize(panel, resizeHandle);
  }

  function attachPanelResize(panel, handle) {
    let resizing = false, startX, startW;
    handle.addEventListener('mousedown', (e) => {
      e.preventDefault();
      resizing = true; startX = e.clientX;
      startW = panel.getBoundingClientRect().width;
      document.body.style.cursor = 'ew-resize';
    });
    document.addEventListener('mousemove', (e) => {
      if (!resizing) return;
      const w = Math.min(520, Math.max(180, startW - (e.clientX - startX)));
      panel.style.width = w + 'px';
    });
    document.addEventListener('mouseup', () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = '';
      localStorage.setItem('eh-panel-width', panel.style.width);
    });
  }

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

  function applySettings(s) {
    document.querySelectorAll('.eh-panel-native').forEach(el => {
      el.style.display = s.mode === 'en' ? 'none' : 'block';
    });
  }

  function toggle(forceVisible) {
    const panel = document.getElementById('eh-panel');
    if (!panel) return;
    if (forceVisible !== undefined) {
      panel.classList.toggle('hidden', !forceVisible);
    } else {
      panel.classList.toggle('hidden');
    }
  }

  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    // 어댑터가 비동기로 트랙을 로드하는 경우를 위한 이벤트 리스너
    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        renderList();
      });
    }

    renderList();
  }

  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings };
})();
```

- [ ] **Step 2: 커밋**

```bash
git add core/script-panel.js
git commit -m "feat: add ScriptPanel with timeline, highlight, seek, and sentence save"
```

---

### Task 6: core/word-popup.js — 단어 클릭 팝업 + Free Dictionary API

**Files:**
- Create: `core/word-popup.js`

**Interfaces:**
- Consumes:
  - `fetch('https://api.dictionaryapi.dev/api/v2/entries/en/{word}')` — 발음기호 + 뜻
  - `window.EH.Storage.saveWord({ word, definition, sentence, translation, timestamp })`
  - `window.EH.Storage.saveSentence({ original, translation, timestamp })`
- Produces:
  - `window.EH.WordPopup.setup(adapter)` — 초기화
  - `window.EH.WordPopup.show(word, sentence, translation, timestamp, clientX, clientY)` — 팝업 표시

- [ ] **Step 1: core/word-popup.js 작성**

```js
(function () {
  'use strict';

  let popupEl = null;

  function createDOM() {
    if (document.getElementById('eh-word-popup')) {
      popupEl = document.getElementById('eh-word-popup');
      return;
    }
    popupEl = document.createElement('div');
    popupEl.id = 'eh-word-popup';
    document.body.appendChild(popupEl);

    // 팝업 바깥 클릭 시 닫기
    document.addEventListener('click', (e) => {
      if (!popupEl.contains(e.target)) hide();
    });
  }

  function hide() {
    if (popupEl) popupEl.classList.remove('visible');
  }

  function positionPopup(clientX, clientY) {
    const margin = 12;
    const pw = popupEl.offsetWidth || 260;
    const ph = popupEl.offsetHeight || 200;
    let x = clientX + margin;
    let y = clientY - ph / 2;
    if (x + pw > window.innerWidth - margin) x = clientX - pw - margin;
    if (y < margin) y = margin;
    if (y + ph > window.innerHeight - margin) y = window.innerHeight - ph - margin;
    popupEl.style.left = x + 'px';
    popupEl.style.top  = y + 'px';
  }

  async function fetchDefinition(word) {
    try {
      const res = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`);
      if (!res.ok) return null;
      const data = await res.json();
      const entry = data[0];
      return {
        phonetic: entry.phonetic || entry.phonetics?.[0]?.text || '',
        definition: entry.meanings?.[0]?.definitions?.[0]?.definition || ''
      };
    } catch (e) {
      return null;
    }
  }

  async function show(word, sentence, translation, timestamp, clientX, clientY) {
    if (!popupEl) return;

    // 로딩 상태로 즉시 표시
    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(word)}</div>
      <div class="eh-popup-loading">불러오는 중...</div>
    `;
    popupEl.classList.add('visible');
    positionPopup(clientX, clientY);

    // 사전 API 호출
    const dict = await fetchDefinition(word);

    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(word)}</div>
      ${dict?.phonetic ? `<div class="eh-popup-phonetic">${esc(dict.phonetic)}</div>` : ''}
      <div class="eh-popup-divider"></div>
      <div class="eh-popup-def">${esc(dict?.definition || '정의를 찾을 수 없습니다.')}</div>
      ${sentence ? `<div class="eh-popup-sentence">"${esc(sentence)}"</div>` : ''}
      <div class="eh-popup-actions">
        <button class="eh-popup-btn" id="eh-save-word">단어 저장</button>
        <button class="eh-popup-btn" id="eh-save-sent">문장 저장</button>
      </div>
    `;

    // 팝업 높이가 바뀌었으므로 재위치
    positionPopup(clientX, clientY);

    document.getElementById('eh-save-word').addEventListener('click', () => {
      window.EH.Storage.saveWord({
        word, definition: dict?.definition || '',
        sentence, translation, timestamp
      }).then(() => {
        window.EH.showToast?.(`✓ "${word}" 저장됨`);
        hide();
      });
    });

    document.getElementById('eh-save-sent').addEventListener('click', () => {
      window.EH.Storage.saveSentence({ original: sentence, translation, timestamp })
        .then(() => {
          window.EH.showToast?.('✓ 문장 저장됨');
          hide();
        });
    });
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function setup() {
    createDOM();
  }

  window.EH = window.EH || {};
  window.EH.WordPopup = { setup, show, hide };
})();
```

- [ ] **Step 2: 수동 검증**

YouTube 콘솔에서:
```js
window.EH.WordPopup.show('ephemeral', 'Nothing is ephemeral.', '아무것도 덧없지 않다.', 10, 500, 300)
```
Expected: 팝업이 (500, 300) 근처에 표시되고 사전 API 로딩 후 정의가 채워짐

- [ ] **Step 3: 커밋**

```bash
git add core/word-popup.js
git commit -m "feat: add WordPopup with Free Dictionary API, save word/sentence"
```

---

## Plan A 완료 체크리스트

- [ ] Task 1: manifest.json 4개 플랫폼, sql.js 다운로드
- [ ] Task 2: core/adapter-interface.js, window.EH 네임스페이스
- [ ] Task 3: core/storage.js, service_worker.js 새 스키마
- [ ] Task 4: core/subtitle-engine.js, ui/overlay.css
- [ ] Task 5: core/script-panel.js
- [ ] Task 6: core/word-popup.js

**Plan A 완료 후 → Plan B (platform-adapters) 로 이동**
