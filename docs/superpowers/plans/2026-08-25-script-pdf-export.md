# 스크립트 PDF Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose HTML or PDF when exporting the script panel's dual-subtitle transcript, with PDF produced by the browser's own print engine on an extension-origin page.

**Architecture:** The existing `ScriptPanel.exportScript()` HTML-download path stays as-is and gains print-ready CSS. A new PDF path passes the same generated HTML through the service worker (which stashes it in `chrome.storage.session` and opens a new tab) into a new extension page `export/print.html`, which renders it and calls `window.print()`. Going through an extension-origin page is what makes this work on Netflix/Disney+, whose strict CSP can block a content script from opening a `blob:` URL as a top-level tab.

**Tech Stack:** Vanilla JS (ES2020, IIFE modules), `chrome.runtime` messaging, `chrome.storage.session`, `chrome.tabs.create`, `DOMParser`, `window.print()`. No new dependencies.

## Global Constraints

- **No new package dependencies.** No PDF-generation library (jsPDF etc.), no embedded Korean font — PDF comes from the browser print engine only.
- **No `manifest.json` change.** An extension page the extension itself opens via `chrome.tabs.create` needs no registration. Do NOT add `export/print.html` to `web_accessible_resources` — that would let arbitrary sites open it.
- **No new permissions.** `storage` and `tabs` are already in the manifest.
- **One new `chrome.runtime` message type only:** `EH_EXPORT_PRINT`. Follow the existing `handleMessage` switch-case shape in `background/service_worker.js`, returning `{ success: true, ... }` / `{ success: false, error }`.
- **`chrome.storage.session` is written and read only from trusted contexts** (service worker, extension page). Never call it from a content script, and never call `chrome.storage.session.setAccessLevel()`.
- Follow the existing `window.EH.*` IIFE-module convention and `#eh-*` / `.eh-*` CSS naming convention.
- Style with existing tokens from `ui/tokens.css` (`--eh-gold`, `--eh-gold-rgb`, `--eh-text-rgb`, `--eh-accent`, `--eh-font-body`, `--eh-font-mono`). Do not introduce raw hex colors in `ui/overlay.css`.
- `ScriptPanel.exportScript` must remain on the public API as an alias — `core/settings-panel.js:113` calls it, and Task 4 is what migrates that caller.
- **This repo has no automated JS test framework and no Node runtime installed.** Pure-logic verification uses throwaway scripts run with the system JavaScriptCore binary (`/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc`), written to the scratchpad and never committed. DOM/`chrome.*`-dependent behavior is manual-verification-only, consistent with prior work in this project area.
- The print stylesheet is included in **both** export paths (downloaded `.html` and the print page) — a saved HTML file the user prints by hand must lay out identically. Do not branch the two.

---

### Task 1: Add print stylesheet to the exported HTML

Pure, self-contained change to the HTML generator. No UI change yet, so the existing single export button keeps working exactly as before — it just produces better-printing HTML.

**Files:**
- Modify: `core/script-panel.js:112-139` (the returned template string inside `_buildExportHtml`)
- Verify: throwaway script in scratchpad (not committed)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `_buildExportHtml(cues, nativeCuesArr, meta) -> string` — unchanged signature, unchanged existing markup, now containing an `@media print` block and an `@page` rule. Tasks 3 and 4 both call it.

- [ ] **Step 1: Write the failing verification script**

Create `<scratchpad>/verify-print-css.js` (use the session scratchpad directory, not the repo):

```js
// Loads core/script-panel.js is impossible in isolation (it is an IIFE that
// touches window/document), so this harness extracts the template by regex and
// asserts on the generated markup shape instead.
const src = readFile('core/script-panel.js');

function assert(cond, label) {
  if (!cond) { print('FAIL: ' + label); throw new Error(label); }
  print('ok: ' + label);
}

assert(src.includes('@media print'), 'has an @media print block');
assert(src.includes('@page'), 'has an @page rule with margins');
assert(src.includes('break-inside: avoid'), 'rows avoid breaking across pages');
assert(src.includes('break-after: avoid'), 'header stays with first row');
print('ALL PASS');
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/park/Project2/english-helper-extension
/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
  "$SCRATCHPAD/verify-print-css.js"
```

Expected: `FAIL: has an @media print block` and a non-zero exit.

- [ ] **Step 3: Add the print rules to the template**

In `core/script-panel.js`, find the closing lines of the `<style>` block inside `_buildExportHtml` (currently ending with the `.native` rule):

```
  .en { font-size: 15px; }
  .native { font-size: 13px; color: #666; margin-top: 2px; }
</style>
```

Replace with:

```
  .en { font-size: 15px; }
  .native { font-size: 13px; color: #666; margin-top: 2px; }

  /* 인쇄(= PDF로 저장) 조판. 다운로드한 HTML을 사용자가 직접 인쇄할 때와
     확장의 PDF 내보내기가 같은 결과를 내야 하므로 두 경로 모두에 넣는다. */
  @page { margin: 18mm 14mm; }
  @media print {
    body { max-width: none; margin: 0; padding: 0; }
    /* 한 자막 줄이 페이지 경계에서 반으로 갈리지 않게 한다 */
    .row { break-inside: avoid; }
    /* 제목만 페이지 끝에 홀로 남는 것을 막는다 */
    header { break-after: avoid; }
    .no-print { display: none !important; }
  }
</style>
```

- [ ] **Step 4: Run the verification script to confirm it passes**

```bash
/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
  "$SCRATCHPAD/verify-print-css.js"
```

Expected: four `ok:` lines then `ALL PASS`.

- [ ] **Step 5: Manually confirm the exported HTML still renders**

Load the unpacked extension, open any YouTube video with captions, open the script panel, click `⬇`. Open the downloaded `.html` in Chrome and press `Cmd+P`. Expected: the print preview shows the title header and timestamped rows, with no row split across a page boundary.

- [ ] **Step 6: Commit**

```bash
git add core/script-panel.js
git commit -m "feat: add print stylesheet to exported script HTML"
```

---

### Task 2: Service worker handler + extension print page

Builds the whole PDF pipeline behind the scenes. Nothing in the UI calls it yet — it is driven manually from the service worker console in Step 5, which is what makes this task independently testable.

**Files:**
- Create: `export/print.html`
- Create: `export/print.js`
- Modify: `background/service_worker.js` (add a case to the `handleMessage` switch, before `default:`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: message contract `{ type: 'EH_EXPORT_PRINT', payload: { html: string } }` → resolves to `{ success: true, id: string }` or `{ success: false, error: string }`. Task 3 sends this message.
- Produces: session-storage key format `` `eh_print_${id}` `` holding the HTML string, consumed by `export/print.js` in the same task.

- [ ] **Step 1: Create the print page shell**

Create `export/print.html`:

```html
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>스크립트 인쇄</title>
<style>
  /* 스크립트 본문 스타일은 주입되는 HTML이 자체 <style>로 들고 온다.
     여기 있는 것은 오류 안내 화면 전용이라 인쇄 시 숨긴다. */
  .eh-print-error {
    font-family: -apple-system, 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif;
    max-width: 480px; margin: 80px auto; padding: 0 20px;
    color: #444; font-size: 14px; line-height: 1.6; text-align: center;
  }
  @media print { .eh-print-error { display: none !important; } }
</style>
</head>
<body>
<div id="eh-print-root"></div>
<script src="print.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create the print page script**

Create `export/print.js`:

```js
// 확장 페이지(chrome-extension:// 오리진)에서 실행된다 — 호스트 사이트의 CSP를
// 받지 않으므로 Netflix/Disney+에서도 동작한다. 이 페이지의 존재 이유 자체가
// 그것이다.
(function () {
  'use strict';

  const root = document.getElementById('eh-print-root');

  function showError(msg) {
    const div = document.createElement('div');
    div.className = 'eh-print-error';
    div.textContent = msg;
    root.appendChild(div);
  }

  async function main() {
    const id = new URLSearchParams(location.search).get('id');
    if (!id) {
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    const key = 'eh_print_' + id;
    let html;
    try {
      const stored = await chrome.storage.session.get(key);
      html = stored[key];
    } catch (err) {
      console.error('[EH Print] session read failed', err);
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    // 한 번 쓰고 버리는 값이다 — 읽자마자 지워서 세션 저장소에 스크립트가
    // 쌓이지 않게 한다. 이 탭을 새로고침하면 아래 not-found 분기로 간다.
    chrome.storage.session.remove(key);

    if (!html) {
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    // 문서 전체를 innerHTML로 통째로 넣지 않는다 — DOMParser로 파싱해
    // <style>과 body 자식만 옮긴다. 자막 원문은 이미 이스케이프되지만,
    // 방어적으로 한 겹 더 둔다. (MV3 확장 페이지의 기본 CSP script-src 'self'가
    // 인라인 스크립트/이벤트 핸들러 실행을 막는 것이 그 다음 겹이다.)
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.head.querySelectorAll('style').forEach(s => document.head.appendChild(s));
    while (doc.body.firstChild) root.appendChild(doc.body.firstChild);

    const title = doc.querySelector('title')?.textContent;
    if (title) document.title = title;

    // 폰트가 로드되기 전에 인쇄하면 줄바꿈 위치가 화면과 달라져 조판이 틀어진다.
    await document.fonts.ready;
    window.print();
  }

  main();
})();
```

- [ ] **Step 3: Add the service worker handler**

In `background/service_worker.js`, find the end of the `DELETE_ITEM` case and the `default:` that follows:

```js
      await chrome.storage.local.set({ [key]: items });
      return { success: true };
    }

    default:
```

Replace with:

```js
      await chrome.storage.local.set({ [key]: items });
      return { success: true };
    }

    // 스크립트 PDF 내보내기 — 콘텐츠 스크립트가 만든 HTML을 받아 확장 페이지로
    // 넘긴다. HTML을 URL 쿼리로 넘기기엔 너무 커서(장편 영화 수백 KB)
    // storage.session에 임시로 두고 id만 전달한다. 저장을 콘텐츠 스크립트가
    // 아니라 여기서 하는 이유는 storage.session의 기본 접근 수준이
    // TRUSTED_CONTEXTS라 콘텐츠 스크립트에서는 접근할 수 없기 때문이다.
    case 'EH_EXPORT_PRINT': {
      const html = message.payload && message.payload.html;
      if (!html) return { success: false, error: 'no html' };
      const id = crypto.randomUUID();
      try {
        await chrome.storage.session.set({ ['eh_print_' + id]: html });
      } catch (err) {
        console.error('[EH BG] print session set failed', err);
        return { success: false, error: err.message };
      }
      await chrome.tabs.create({
        url: chrome.runtime.getURL('export/print.html?id=' + id)
      });
      return { success: true, id };
    }

    default:
```

- [ ] **Step 4: Reload the extension**

Go to `chrome://extensions`, click the reload icon on English Helper. Expected: no errors badge on the card.

- [ ] **Step 5: Drive the pipeline manually from the service worker console**

On `chrome://extensions`, click "service worker" under English Helper to open its console. Paste:

```js
await chrome.runtime.sendMessage({
  type: 'EH_EXPORT_PRINT',
  payload: { html: '<!doctype html><html><head><title>테스트</title><style>.row{color:#333}</style></head><body><div class="row">안녕하세요 hello</div></body></html>' }
});
```

Expected: returns `{ success: true, id: "…" }`, a new tab opens showing `안녕하세요 hello`, the tab title is `테스트`, and the Chrome print dialog appears automatically.

- [ ] **Step 6: Verify the not-found branch**

In the print tab that just opened, dismiss the print dialog, then reload the tab (`Cmd+R`).

Expected: the page shows "내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요." and **no** print dialog appears (the key was consumed on first load).

- [ ] **Step 7: Commit**

```bash
git add export/print.html export/print.js background/service_worker.js
git commit -m "feat: add extension print page and EH_EXPORT_PRINT handler"
```

---

### Task 3: Split exportScript into HTML and PDF functions

Wires the content script to Task 2's pipeline. The `⬇` button still triggers HTML only — the dropdown comes in Task 5 — but `exportScriptPdf` becomes callable and is verified from the page console.

**Files:**
- Modify: `core/script-panel.js:141-155` (`exportScript`)
- Modify: `core/script-panel.js:810` (the `window.EH.ScriptPanel` export object)

**Interfaces:**
- Consumes: `{ type: 'EH_EXPORT_PRINT', payload: { html } }` → `{ success, error }` from Task 2.
- Consumes: `_buildExportHtml(cues, nativeCuesArr, meta)` from Task 1.
- Produces: `ScriptPanel.exportScriptHtml() -> void`, `ScriptPanel.exportScriptPdf() -> Promise<void>`, and `ScriptPanel.exportScript` retained as an alias of `exportScriptHtml`. Tasks 4 and 5 call these.

- [ ] **Step 1: Replace `exportScript` with the split functions**

In `core/script-panel.js`, find the whole existing function:

```js
  function exportScript() {
    if (!enCues.length) {
      window.EH.showToast?.('내보낼 자막이 없어요');
      return;
    }
    const meta = window.EH.adapter?.getPlatformMeta?.() || { platform: '', title: '' };
    const html = _buildExportHtml(enCues, nativeCues, meta);
    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${(meta.title || 'script').replace(/[\\/:*?"<>|]/g, '_')}.html`;
    a.click();
    URL.revokeObjectURL(url);
  }
```

Replace with:

```js
  /**
   * HTML/PDF 두 경로가 공유하는 준비 단계 — 빈 자막 가드, 플랫폼 메타 조회,
   * HTML 생성. 내보낼 자막이 없으면 토스트를 띄우고 null을 돌려준다.
   * @returns {{html: string, filename: string}|null}
   */
  function _prepareExport() {
    if (!enCues.length) {
      window.EH.showToast?.('내보낼 자막이 없어요');
      return null;
    }
    const meta = window.EH.adapter?.getPlatformMeta?.() || { platform: '', title: '' };
    const html = _buildExportHtml(enCues, nativeCues, meta);
    const filename = `${(meta.title || 'script').replace(/[\\/:*?"<>|]/g, '_')}`;
    return { html, filename };
  }

  function exportScriptHtml() {
    const prepared = _prepareExport();
    if (!prepared) return;
    const blob = new Blob([prepared.html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${prepared.filename}.html`;
    a.click();
    URL.revokeObjectURL(url);
  }

  /**
   * PDF는 라이브러리로 직접 만들지 않고 브라우저 인쇄 엔진에 맡긴다 —
   * 한글 폰트를 임베드할 필요가 없고 레이아웃 코드를 이중으로 두지 않아도 된다.
   * 인쇄는 확장 페이지에서 해야 한다: 콘텐츠 스크립트가 만든 blob: URL을 새 탭
   * 최상위로 여는 것은 호스트 페이지 CSP의 영향을 받아 Netflix/Disney+에서
   * 막힐 수 있다.
   */
  async function exportScriptPdf() {
    const prepared = _prepareExport();
    if (!prepared) return;
    try {
      const res = await chrome.runtime.sendMessage({
        type: 'EH_EXPORT_PRINT',
        payload: { html: prepared.html }
      });
      if (!res || !res.success) throw new Error(res?.error || 'no response');
    } catch (err) {
      // 확장이 방금 리로드되어 컨텍스트가 무효화된 경우에도 여기로 온다.
      console.error('[EH ScriptPanel] pdf export failed', err);
      window.EH.showToast?.('PDF 내보내기에 실패했어요');
    }
  }
```

- [ ] **Step 2: Update the click listener**

In `core/script-panel.js`, find:

```js
    exportBtn.addEventListener('click', exportScript);
```

Replace with:

```js
    exportBtn.addEventListener('click', exportScriptHtml);
```

(Task 5 replaces this again with the dropdown toggle.)

- [ ] **Step 3: Update the public API**

In `core/script-panel.js`, find:

```js
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings, exportScript };
```

Replace with:

```js
  // exportScript는 core/settings-panel.js가 아직 부르고 있어 별칭으로 남긴다.
  window.EH.ScriptPanel = {
    setup, highlight, toggle, applySettings,
    exportScriptHtml, exportScriptPdf, exportScript: exportScriptHtml
  };
```

- [ ] **Step 4: Reload and verify the HTML path is unchanged**

Reload the extension, open a YouTube video with captions, open the script panel, click `⬇`.

Expected: a `.html` file downloads exactly as before.

- [ ] **Step 5: Verify the PDF path from the page console**

With the same video open, in the page DevTools console (not the service worker console) run:

```js
window.EH.ScriptPanel.exportScriptPdf();
```

Expected: a new tab opens with the full transcript rendered and the print dialog showing. Set Destination to "PDF로 저장" and confirm the preview shows multiple pages with no row split across a boundary.

- [ ] **Step 6: Verify the empty-cues guard**

Open a video with no captions available (or run the call before captions load), then run the same console line.

Expected: the "내보낼 자막이 없어요" toast appears and no tab opens.

- [ ] **Step 7: Commit**

```bash
git add core/script-panel.js
git commit -m "feat: split script export into HTML and PDF functions"
```

---

### Task 4: Settings panel export rows

Independently reviewable: purely the settings-panel surface, using the API Task 3 produced.

**Files:**
- Modify: `core/settings-panel.js:79-82` (the `eh-settings-export-row` markup)
- Modify: `core/settings-panel.js:112-114` (the `#eh-export-script` listener)

**Interfaces:**
- Consumes: `ScriptPanel.exportScriptHtml()`, `ScriptPanel.exportScriptPdf()` from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Split the export row into two**

In `core/settings-panel.js`, find:

```html
        <div class="eh-settings-export-row">
          <div class="eh-settings-export-btn primary" id="eh-export-script">스크립트 내보내기</div>
          <div class="eh-settings-export-btn" id="eh-export-sqlite">저장 항목 내보내기<span class="eh-settings-export-ext">.sqlite</span></div>
        </div>
```

Replace with:

```html
        <div class="eh-settings-export-row">
          <div class="eh-settings-export-btn primary" id="eh-export-script-html">스크립트 내보내기<span class="eh-settings-export-ext">.html</span></div>
          <div class="eh-settings-export-btn" id="eh-export-script-pdf">스크립트 내보내기<span class="eh-settings-export-ext">.pdf</span></div>
          <div class="eh-settings-export-btn" id="eh-export-sqlite">저장 항목 내보내기<span class="eh-settings-export-ext">.sqlite</span></div>
        </div>
```

- [ ] **Step 2: Update the listeners**

In `core/settings-panel.js`, find:

```js
    panelEl.querySelector('#eh-export-script').addEventListener('click', () => {
      window.EH.ScriptPanel?.exportScript();
    });
```

Replace with:

```js
    panelEl.querySelector('#eh-export-script-html').addEventListener('click', () => {
      window.EH.ScriptPanel?.exportScriptHtml();
    });

    panelEl.querySelector('#eh-export-script-pdf').addEventListener('click', () => {
      window.EH.ScriptPanel?.exportScriptPdf();
    });
```

- [ ] **Step 3: Reload and verify both rows**

Reload the extension, open a captioned video, open the settings panel and scroll to 내보내기.

Expected: three rows — `스크립트 내보내기 .html` (accent-filled), `스크립트 내보내기 .pdf`, `저장 항목 내보내기 .sqlite`. Clicking the first downloads a `.html`; clicking the second opens the print tab; clicking the third still exports `.sqlite`.

- [ ] **Step 4: Commit**

```bash
git add core/settings-panel.js
git commit -m "feat: split settings panel script export into html and pdf rows"
```

---

### Task 5: Script panel export dropdown

The user-facing choice on the panel header. Depends on Task 3's API.

**Files:**
- Modify: `core/script-panel.js:269-275` (header markup)
- Modify: `core/script-panel.js` (`exportBtn` listener region, ~line 426-429 after Task 3)
- Modify: `core/script-panel.js` (`toggle()`, ~line 734 — close the menu when the panel hides)
- Modify: `ui/overlay.css` (append after the `.eh-panel-btn:hover` rule, ~line 197)

**Interfaces:**
- Consumes: `ScriptPanel.exportScriptHtml()`, `ScriptPanel.exportScriptPdf()` from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the menu markup to the header**

In `core/script-panel.js`, find:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-expand" title="실제 크기로 확장">⤢</button>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>';
    panel.appendChild(header);
```

Replace with:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-expand" title="실제 크기로 확장">⤢</button>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<div class="eh-panel-export-menu hidden" id="eh-panel-export-menu">' +
        '<div class="eh-panel-export-item" data-format="html">HTML로 저장<span class="eh-panel-export-ext">.html</span></div>' +
        '<div class="eh-panel-export-item" data-format="pdf">PDF로 저장<span class="eh-panel-export-ext">.pdf</span></div>' +
      '</div>';
    // 메뉴를 헤더 기준으로 절대 배치하기 위한 컨테이닝 블록.
    header.style.position = 'relative';
    panel.appendChild(header);
```

- [ ] **Step 2: Add the menu styles**

In `ui/overlay.css`, find:

```css
.eh-panel-btn:hover { color: var(--eh-gold); background: rgba(var(--eh-gold-rgb), 0.1); }
```

Append immediately after it:

```css
/* 내보내기 드롭다운 — ⬇ 버튼 기준으로 헤더 우측 아래에 붙는다.
   헤더에 position:relative를 걸어 컨테이닝 블록으로 삼는다(script-panel.js). */
.eh-panel-export-menu {
  position: absolute; top: calc(100% - 6px); right: 10px;
  z-index: 10; min-width: 148px; padding: 5px;
  border-radius: 9px;
  background: var(--eh-bg);
  border: 1px solid rgba(var(--eh-gold-rgb), 0.18);
  box-shadow: 0 8px 22px rgba(0, 0, 0, 0.42);
}
.eh-panel-export-menu.hidden { display: none !important; }
.eh-panel-export-item {
  display: flex; align-items: center; gap: 8px;
  height: 32px; padding: 0 10px; border-radius: 6px;
  font: 500 12px var(--eh-font-body);
  color: rgba(var(--eh-text-rgb), 0.88);
  cursor: pointer; white-space: nowrap;
}
.eh-panel-export-item:hover { background: rgba(var(--eh-gold-rgb), 0.12); color: var(--eh-gold); }
.eh-panel-export-ext { margin-left: auto; font: 10.5px var(--eh-font-mono); opacity: 0.62; }
```

- [ ] **Step 3: Confirm `--eh-bg` exists, or substitute**

```bash
grep -n "\-\-eh-bg\b" ui/tokens.css
```

Expected: a line defining `--eh-bg`. If it does not exist, run `grep -n "^  --eh-" ui/tokens.css` and use whichever token holds the panel background (the same one `#eh-panel` uses at `ui/overlay.css:121`), so the menu matches the panel surface.

- [ ] **Step 4: Replace the click listener with the dropdown wiring**

In `core/script-panel.js`, find (as left by Task 3):

```js
    const exportBtn   = header.querySelector('#eh-panel-export');
    const expandBtn   = header.querySelector('#eh-panel-expand');

    exportBtn.addEventListener('click', exportScriptHtml);
```

Replace with:

```js
    const exportBtn   = header.querySelector('#eh-panel-export');
    const expandBtn   = header.querySelector('#eh-panel-expand');
    const exportMenu  = header.querySelector('#eh-panel-export-menu');

    exportBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      // 자막이 없으면 메뉴를 열 이유가 없다 — 포맷을 고르게 한 뒤 실패
      // 토스트를 띄우는 것보다, 지금 바로 알려주는 편이 낫다.
      if (!enCues.length) {
        window.EH.showToast?.('내보낼 자막이 없어요');
        return;
      }
      exportMenu.classList.toggle('hidden');
      exportBtn.classList.toggle('active', !exportMenu.classList.contains('hidden'));
    });

    exportMenu.addEventListener('click', (e) => {
      const item = e.target.closest('.eh-panel-export-item');
      if (!item) return;
      _closeExportMenu();
      if (item.dataset.format === 'pdf') exportScriptPdf();
      else exportScriptHtml();
    });

    // 메뉴 바깥 클릭 / Esc로 닫는다. 패널이 body와 #secondary 사이를 오가므로
    // 리스너는 패널이 아니라 document에 건다.
    document.addEventListener('click', _closeExportMenu);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') _closeExportMenu();
    });
```

- [ ] **Step 5: Add the close helper and call it on layout changes**

In `core/script-panel.js`, add this function immediately above `function toggle(forceVisible) {`:

```js
  // 메뉴는 헤더에 절대 배치되므로, 패널이 숨겨지거나 임베드↔고정 모드가
  // 전환되는 동안 열린 채로 두면 엉뚱한 위치에 떠 있게 된다. 상태가 바뀌는
  // 모든 지점에서 닫는다.
  function _closeExportMenu() {
    const menu = document.getElementById('eh-panel-export-menu');
    const btn = document.getElementById('eh-panel-export');
    if (menu) menu.classList.add('hidden');
    if (btn) btn.classList.remove('active');
  }
```

Then inside `toggle()`, find:

```js
    if (wrapper) wrapper.classList.toggle('hidden', nowHidden);
    panel.classList.toggle('hidden', nowHidden);
```

Replace with:

```js
    _closeExportMenu();
    if (wrapper) wrapper.classList.toggle('hidden', nowHidden);
    panel.classList.toggle('hidden', nowHidden);
```

Then find the expand button listener's first line:

```js
    expandBtn.addEventListener('click', () => {
      expanded = !expanded;
```

Replace with:

```js
    expandBtn.addEventListener('click', () => {
      _closeExportMenu();
      expanded = !expanded;
```

- [ ] **Step 6: Reload and verify the dropdown**

Reload the extension, open a captioned YouTube video, open the script panel, click `⬇`.

Expected, checked in order:
1. A two-item menu appears below the button, right-aligned inside the panel, not clipped by the panel edge.
2. `HTML로 저장` downloads a `.html` and the menu closes.
3. `⬇` again → `PDF로 저장` opens the print tab and the menu closes.
4. `⬇` then clicking anywhere else on the page → menu closes.
5. `⬇` then `Esc` → menu closes.
6. `⬇` then `⤢` → menu closes and the panel expands.
7. `⬇` then hiding the panel from the topbar and showing it again → menu is closed.

- [ ] **Step 7: Verify on Netflix**

Play any Netflix title with English subtitles, open the script panel, `⬇` → `PDF로 저장`.

Expected: the print tab opens and the print dialog appears. **This is the single most important check in the whole feature** — Netflix's strict CSP is the reason the print page is an extension page instead of a `blob:` URL, so this is where a wrong approach would visibly fail.

- [ ] **Step 8: Commit**

```bash
git add core/script-panel.js ui/overlay.css
git commit -m "feat: add HTML/PDF dropdown to script panel export button"
```

---

### Task 6: Cross-platform verification and spec status

**Files:**
- Modify: `docs/superpowers/specs/2026-08-25-script-pdf-export-design.md` (status line)

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: nothing.

- [ ] **Step 1: Verify on all four platforms**

For each of YouTube, Netflix, Disney+, 쿠팡플레이: open a title with English subtitles, open the script panel, and exercise `⬇` → `PDF로 저장`.

Expected on each: the print tab opens, the transcript is fully rendered with both languages, and the print dialog appears. Record any platform that fails and stop — do not mark the task done.

- [ ] **Step 2: Verify the print output quality**

In the print dialog on any one platform, set Destination to "PDF로 저장" and save.

Expected in the saved PDF: title/platform/date header on page 1, timestamped rows in reading order, no row split across a page boundary, Korean text rendered correctly (not tofu boxes).

- [ ] **Step 3: Confirm no manifest or permission drift**

```bash
git diff main --stat -- manifest.json
```

Expected: no output — `manifest.json` is untouched, per the global constraints.

- [ ] **Step 4: Update the spec status**

In `docs/superpowers/specs/2026-08-25-script-pdf-export-design.md`, change:

```
**상태:** 승인됨
```

to:

```
**상태:** 구현 완료 (2026-08-25)
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-08-25-script-pdf-export-design.md
git commit -m "docs: mark script PDF export spec as implemented"
```
