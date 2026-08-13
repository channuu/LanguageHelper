# Script HTML Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an export button to the Chrome extension's script-panel sidebar that saves the current video's full dual-language transcript as a standalone HTML file.

**Architecture:** A pure function `_buildExportHtml(enCues, nativeCues, meta)` in `core/script-panel.js` builds a self-contained HTML string (inline CSS, HTML-escaped cue text); a `exportScript()` function wraps it in the extension's existing `Blob` + `URL.createObjectURL` + `<a download>` pattern (already used by `popup/popup.js`'s SQLite export); a new header button wires the click.

**Tech Stack:** Vanilla JS, no new dependencies — matches the existing extension's zero-build-step architecture.

## Global Constraints

- HTML export only — no PDF generation in this pass (per design doc §2, browser print-to-PDF on the exported HTML covers that need).
- No new dependencies or external resources — the exported file must be self-contained (inline `<style>`, no CDN links, no external fonts).
- Reuse `window.EH.adapter` (already set globally by `core/adapter-interface.js`'s `init()`) to read `getPlatformMeta()` at export time — do NOT add a new module-scope adapter-reference variable to `script-panel.js`; the existing global already provides this, so the extra state the design doc originally proposed is unnecessary.
- All cue text must be HTML-escaped before insertion into the exported document (cue text can contain `<`, `>`, `&` from real captions).
- Widget test coverage stays minimal, matching the rest of this codebase's testing style (headless-Chrome simulation harnesses, as used for the YouTube/Netflix/Coupang adapters) — cover HTML structure and escaping, not the actual browser download trigger (that's UI plumbing, verified manually).

---

### Task 1: `_buildExportHtml` — pure HTML string builder

**Files:**
- Modify: `core/script-panel.js`
- Test: none checked into the repo (this codebase has no JS test runner configured — verification is via a headless-Chrome simulation harness run manually during implementation, matching how the YouTube/Netflix/Coupang adapters were verified in this project's history. Do not add a new test framework/dependency to introduce automated JS tests — that is out of scope for this task).

**Interfaces:**
- Consumes: `formatTime(sec)` (existing function in the same file, used for timestamp formatting) and a `meta` object shaped `{platform: string, title: string}` (matches `SubtitleAdapter.getPlatformMeta()`'s return shape, defined in `core/adapter-interface.js`). Does NOT reuse the module-scope `findNativeText` function — `_buildExportHtml` takes `cues`/`nativeCuesArr` as plain parameters (not reading module state) so it stays a pure, directly-testable function; it re-implements the same proximity-matching logic as a local closure inside itself (a small, deliberate duplication in exchange for testability — the existing `findNativeText` reads the module-scope `nativeCues` variable directly and can't be called with arbitrary test data).
- Produces: `_buildExportHtml(cues, nativeCuesArr, meta) -> string` — a complete, self-contained HTML document as a string. Used by Task 2's `exportScript()`.

- [ ] **Step 1: Read the existing file to confirm current line numbers before editing**

```bash
grep -n "function formatTime\|function findNativeText\|window.EH.ScriptPanel" core/script-panel.js
```
Expected output should show `formatTime` and `findNativeText` near the top of the file (lines 8-16 as of this plan's writing) and the `window.EH.ScriptPanel = { ... }` export statement near the bottom (line 283 as of this plan's writing) — confirm these before editing, since exact line numbers may have drifted since this plan was written.

- [ ] **Step 2: Add `_buildExportHtml` to `core/script-panel.js`**

Add this function after `findNativeText` (which is defined right after `formatTime` near the top of the file):

```js
  function _escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function _buildExportHtml(cues, nativeCuesArr, meta) {
    const title = _escapeHtml(meta?.title || '제목 없음');
    const platform = _escapeHtml(meta?.platform || '');
    const exportedAt = new Date().toLocaleDateString();

    const findNative = (enCue) =>
      nativeCuesArr.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';

    const rows = cues.map(cue => {
      const time = _escapeHtml(formatTime(cue.start));
      const en = _escapeHtml(cue.text);
      const native = _escapeHtml(findNative(cue));
      return `
        <div class="row">
          <span class="time">${time}</span>
          <div class="text">
            <div class="en">${en}</div>
            ${native ? `<div class="native">${native}</div>` : ''}
          </div>
        </div>`;
    }).join('\n');

    return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>${title}</title>
<style>
  body { font-family: -apple-system, 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif; max-width: 720px; margin: 40px auto; padding: 0 20px; color: #1a1a1a; }
  header { border-bottom: 2px solid #ddd; padding-bottom: 16px; margin-bottom: 24px; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  .meta { color: #666; font-size: 13px; }
  .row { display: flex; gap: 16px; padding: 10px 0; border-bottom: 1px solid #eee; }
  .time { color: #999; font-size: 12px; font-variant-numeric: tabular-nums; flex-shrink: 0; width: 48px; }
  .text { flex: 1; }
  .en { font-size: 15px; }
  .native { font-size: 13px; color: #666; margin-top: 2px; }
</style>
</head>
<body>
<header>
  <h1>${title}</h1>
  <div class="meta">${platform} · ${exportedAt} 내보냄</div>
</header>
<main>
${rows}
</main>
</body>
</html>`;
  }
```

- [ ] **Step 3: Verify with a headless-Chrome simulation harness**

```bash
python3 - <<'PYEOF'
script_panel_js = open('core/script-panel.js').read()

html = """<!doctype html><html><body><script>
window.EH = { settings: { mode: 'both' } };
""" + script_panel_js + """
</script>
<script>
const results = [];

// 1) HTML escaping — cue text with special chars must be escaped
try {
  const cues = [{ start: 5, end: 8, text: '<script>alert(1)</script> & "quotes"' }];
  const nativeCues = [{ start: 5, end: 8, text: '테스트 & 특수문자' }];
  const html = window.__buildExportHtml(cues, nativeCues, { platform: 'youtube', title: 'Test <Video>' });
  results.push('no_raw_script_tag:' + (!html.includes('<script>alert') ? 'OK' : 'FAILED'));
  results.push('escaped_ampersand:' + (html.includes('&amp;') ? 'OK' : 'FAILED'));
  results.push('title_escaped:' + (html.includes('Test &lt;Video&gt;') ? 'OK' : 'FAILED'));
  results.push('contains_timestamp:' + (html.includes('0:05') ? 'OK' : 'FAILED'));
  results.push('contains_native:' + (html.includes('테스트 &amp; 특수문자') ? 'OK' : 'FAILED'));
} catch (e) {
  results.push('ERROR:' + e.message);
}

// 2) Empty cues produce a valid document with no rows, no crash
try {
  const html = window.__buildExportHtml([], [], { platform: 'netflix', title: 'Empty' });
  results.push('empty_cues_no_crash:' + (html.includes('<html') ? 'OK' : 'FAILED'));
} catch (e) {
  results.push('empty_cues_no_crash:ERROR:' + e.message);
}

// 3) Missing meta falls back gracefully
try {
  const html = window.__buildExportHtml([{start:0,end:1,text:'hi'}], [], null);
  results.push('missing_meta_fallback:' + (html.includes('제목 없음') ? 'OK' : 'FAILED'));
} catch (e) {
  results.push('missing_meta_fallback:ERROR:' + e.message);
}

document.title = results.join(' || ');
</script>
</body></html>"""

open('/tmp/synchk_export_html_test.html', 'w').write(html)
print('written')
PYEOF
```

Expected: `written` printed with no Python errors. Note: `_buildExportHtml` is defined inside script-panel.js's IIFE and is not exposed on `window` by default — before running the harness, temporarily add `window.__buildExportHtml = _buildExportHtml;` at the very end of `core/script-panel.js`'s IIFE (just before the closing `})();`) so the harness can call it directly. Remove this line again after verification succeeds (Step 4) — it must not ship in the committed file.

- [ ] **Step 4: Run the harness and verify all checks pass, then remove the temporary export line**

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=3000 --dump-dom "file:///tmp/synchk_export_html_test.html" 2>/dev/null | grep -o '<title>.*</title>'
```
Expected: title contains `no_raw_script_tag:OK || escaped_ampersand:OK || title_escaped:OK || contains_timestamp:OK || contains_native:OK || empty_cues_no_crash:OK || missing_meta_fallback:OK`. If any check fails, fix `_buildExportHtml` and re-run. Once all pass, remove the temporary `window.__buildExportHtml = _buildExportHtml;` line added in Step 3 and clean up: `rm -f /tmp/synchk_export_html_test.html`.

- [ ] **Step 5: Commit**

```bash
git add core/script-panel.js
git commit -m "feat: add _buildExportHtml pure builder for script export"
```

---

### Task 2: `exportScript()` + header button wiring

**Files:**
- Modify: `core/script-panel.js`

**Interfaces:**
- Consumes: `_buildExportHtml` (Task 1), `enCues`/`nativeCues` (existing module-scope state), `window.EH.adapter` (global, set by `core/adapter-interface.js`'s `init()` before `ScriptPanel.setup()` is ever called — confirm this ordering by reading `core/adapter-interface.js:42-55` if in doubt), `window.EH.showToast` (existing global helper used elsewhere in this file for the "패널 숨김" toast).
- Produces: `exportScript()` (top-level function in the IIFE) — wired to a new header button's click listener inside `createDOM()`. No other task depends on this function's signature since it's the final piece of this feature.

- [ ] **Step 1: Add the export button to the header markup**

In `core/script-panel.js`'s `createDOM()` function, find this block:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
```

Replace it with:

```js
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
```

- [ ] **Step 2: Implement `exportScript()`**

Add this function right after `_buildExportHtml` (from Task 1):

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

(The `.replace(/[\\/:*?"<>|]/g, '_')` on the filename strips characters that are invalid in Windows/macOS filenames, since `meta.title` comes from arbitrary video/content titles.)

- [ ] **Step 3: Wire the button's click listener**

In `createDOM()`, find this block:

```js
    const collapseBtn = header.querySelector('#eh-panel-collapse');
    const hideBtn     = header.querySelector('#eh-panel-hide');

    collapseBtn.addEventListener('click', () => {
```

Replace it with:

```js
    const collapseBtn = header.querySelector('#eh-panel-collapse');
    const hideBtn     = header.querySelector('#eh-panel-hide');
    const exportBtn   = header.querySelector('#eh-panel-export');

    exportBtn.addEventListener('click', exportScript);

    collapseBtn.addEventListener('click', () => {
```

- [ ] **Step 4: Verify with a headless-Chrome simulation harness**

```bash
python3 - <<'PYEOF'
script_panel_js = open('core/script-panel.js').read()

html = """<!doctype html><html><body><script>
window.EH = {
  settings: { mode: 'both' },
  adapter: { getPlatformMeta: () => ({ platform: 'youtube', title: 'My Video: Special/Chars' }) },
  showToast: (msg) => { window.__lastToast = msg; }
};
""" + script_panel_js + """
</script>
<script>
const results = [];

// Mock the anchor click + Blob/URL.createObjectURL so we can inspect what
// exportScript() would have downloaded, without actually triggering a
// browser download in headless mode.
let capturedHref = null, capturedDownload = null, capturedBlobText = null;
const origCreateElement = document.createElement.bind(document);
document.createElement = function(tag) {
  const el = origCreateElement(tag);
  if (tag === 'a') {
    const origClick = el.click.bind(el);
    Object.defineProperty(el, 'click', {
      value: function() {
        capturedHref = el.href;
        capturedDownload = el.download;
      }
    });
  }
  return el;
};
const origCreateObjectURL = URL.createObjectURL;
URL.createObjectURL = function(blob) {
  blob.text().then(t => { capturedBlobText = t; });
  return origCreateObjectURL.call(URL, blob);
};

// 1) Export with cues present
window.EH.ScriptPanel.setup({
  getSubtitleTracks: () => [
    { lang: 'en', cues: [{ start: 5, end: 8, text: 'Hello world' }] },
    { lang: 'ko', cues: [{ start: 5, end: 8, text: '안녕 세상' }] }
  ]
});

const exportBtn = document.getElementById('eh-panel-export');
results.push('export_button_exists:' + (exportBtn ? 'OK' : 'FAILED'));
exportBtn.click();

setTimeout(() => {
  results.push('download_filename_sanitized:' + (capturedDownload === 'My Video_ Special_Chars.html' ? 'OK' : 'FAILED:' + capturedDownload));
  results.push('blob_contains_cue_text:' + (capturedBlobText && capturedBlobText.includes('Hello world') ? 'OK' : 'FAILED'));

  // 2) Export with no cues shows a toast, doesn't create a new download
  capturedDownload = null;
  window.__lastToast = null;
  window.EH.ScriptPanel.setup({ getSubtitleTracks: () => [{ lang: 'en', cues: [] }, { lang: 'ko', cues: [] }] });
  exportBtn.click();
  results.push('empty_shows_toast:' + (window.__lastToast === '내보낼 자막이 없어요' ? 'OK' : 'FAILED'));
  results.push('empty_no_new_download:' + (capturedDownload === null ? 'OK' : 'FAILED'));

  document.title = results.join(' || ');
}, 100);
</script>
</body></html>"""

open('/tmp/synchk_export_wiring_test.html', 'w').write(html)
print('written')
PYEOF
```

- [ ] **Step 5: Run the harness and verify all checks pass**

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=3000 --dump-dom "file:///tmp/synchk_export_wiring_test.html" 2>/dev/null | grep -o '<title>.*</title>'
```
Expected: title contains `export_button_exists:OK || download_filename_sanitized:OK || blob_contains_cue_text:OK || empty_shows_toast:OK || empty_no_new_download:OK`. If any check fails, fix the implementation and re-run. Once all pass: `rm -f /tmp/synchk_export_wiring_test.html`.

- [ ] **Step 6: Commit**

```bash
git add core/script-panel.js
git commit -m "feat: wire script export button in side panel header"
```

---

### Task 3: Manual verification in a real browser

**Files:** none (verification-only task).

**Interfaces:** none — this task drives the already-built extension, it doesn't produce anything later tasks depend on.

- [ ] **Step 1: Load the unpacked extension in Chrome**

```
1. chrome://extensions
2. Enable Developer mode
3. "Load unpacked" → select the repo root
```

- [ ] **Step 2: Verify the export button on YouTube**

Navigate to any YouTube video with captions, open the side script panel, confirm:
1. A "⬇" button appears in the header next to the hide/collapse buttons.
2. Clicking it downloads an `.html` file named after the video title.
3. Opening the downloaded file in a browser shows the video title, platform, export date, and every English/native subtitle line with timestamps, correctly rendered (no raw `<`/`>`/`&` visible as text, no broken layout).

- [ ] **Step 3: Verify the empty-state toast**

Immediately after switching to a new video (before captions finish loading), click export quickly — confirm the "내보낼 자막이 없어요" toast appears instead of downloading an empty/broken file.

- [ ] **Step 4: No commit** — this task only verifies Tasks 1–2's output runs correctly; it makes no code changes.
