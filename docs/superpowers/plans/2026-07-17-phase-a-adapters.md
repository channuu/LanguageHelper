# English Helper Phase A — Platform Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 4개 스트리밍 플랫폼(YouTube, Netflix, Disney+, 쿠팡플레이) 어댑터 구현 — 각 어댑터는 SubtitleAdapter 인터페이스를 구현하고 `window.EH.init(this)` 를 호출해 코어를 활성화한다.

**Architecture:** 각 어댑터 파일은 독립적인 IIFE. SubtitleAdapter를 extends해 플랫폼별 자막 추출 로직만 구현. 공통 렌더링/저장/팝업은 코어가 처리. YouTube는 기존 page_script.js 인터셉트 방식을 유지하고 네이티브 언어 트랙을 추가 fetch. Netflix/Disney+/쿠팡플레이는 DOM MutationObserver 방식.

**Tech Stack:** Chrome Extension MV3 Content Scripts, DOM MutationObserver, YouTube Timedtext API, DOMParser

## Global Constraints

- 모든 어댑터는 `window.EH.SubtitleAdapter` 를 extends (Plan A Task 2에서 정의)
- `getSubtitleTracks()` 반환 형식: `[{ lang: 'en', cues: [{start, end, text}] }, { lang: 'ko', cues: [...] }]`
- `onSubtitleChange(cb)` 콜백 형식: `cb([{ lang: 'en', text: '...' }, { lang: 'ko', text: '...' }])`
- `onTracksReady(cb)` — 비동기로 트랙 로드 완료 시 호출 (ScriptPanel이 사용)
- `destroy()` 에서 모든 Observer, RAF, eventListener 정리
- 어댑터 마지막 줄: `window.EH.init(new PlatformAdapter())` 호출

---

## File Map

| 파일 | 역할 | 신규/수정 |
|------|------|---------|
| `adapters/youtube.js` | YouTube 어댑터 — page_script.js 연동, 두 자막 트랙 fetch | 신규 |
| `adapters/netflix.js` | Netflix 어댑터 — DOM MutationObserver | 신규 |
| `adapters/disney.js` | Disney+ 어댑터 — DOM MutationObserver | 신규 |
| `adapters/coupang.js` | 쿠팡플레이 어댑터 — DOM MutationObserver | 신규 |
| `content/youtube_inject.js` | 유지 (page_script.js 를 page context에 주입) | 유지 |
| `inject/page_script.js` | 유지 (YouTube player API 인터셉트) | 유지 |

---

### Task 7: adapters/youtube.js — YouTube 어댑터

YouTube는 자체 timedtext API로 여러 언어 자막을 제공한다.  
기존 `page_script.js` 가 자막 URL을 인터셉트해 `window.postMessage`로 전달하므로,  
어댑터는 이 메시지를 수신해 영어 + 모국어 두 트랙을 모두 fetch한다.

**Files:**
- Create: `adapters/youtube.js`

**Interfaces:**
- Consumes:
  - `window.EH.SubtitleAdapter` (Plan A Task 2)
  - `window.postMessage { type: 'EH_CAPTIONS_CAPTURED', tracks: [{langCode, baseUrl}] }` from page_script.js
  - `chrome.runtime.sendMessage({ type: 'FETCH_CAPTIONS', payload: { url } })` → `{ success, text }`
- Produces: `SubtitleAdapter` 인터페이스 전부 구현

- [ ] **Step 1: adapters/youtube.js 작성**

```js
(function () {
  'use strict';

  class YouTubeAdapter extends window.EH.SubtitleAdapter {
    constructor() {
      super();
      this._enCues = [];
      this._nativeCues = [];
      this._subtitleCb = null;
      this._tracksCb = null;
      this._rafId = null;
      this._lastEnText = '';
      this._lastNativeText = '';
      this._currentVideoId = '';
      this._availableTracks = []; // [{langCode, baseUrl}]

      this._onMessage = this._handleMessage.bind(this);
      window.addEventListener('message', this._onMessage);
      this._initVideoTracking();
    }

    // ── 인터페이스 구현 ──────────────────────────────────────────────

    getSubtitleTracks() {
      return [
        { lang: 'en', cues: this._enCues },
        { lang: window.EH.settings?.nativeLang || 'ko', cues: this._nativeCues }
      ];
    }

    getCurrentTime() {
      return document.querySelector('video')?.currentTime || 0;
    }

    seekTo(seconds) {
      const video = document.querySelector('video');
      if (video) video.currentTime = seconds;
    }

    onSubtitleChange(callback) {
      this._subtitleCb = callback;
    }

    onTimeUpdate(callback) {
      // RAF 루프로 대체 — onSubtitleChange가 주 방식
    }

    onTracksReady(callback) {
      this._tracksCb = callback;
    }

    getPlatformMeta() {
      const videoId = new URLSearchParams(location.search).get('v') || '';
      const title = document.querySelector('h1.ytd-watch-metadata yt-formatted-string')?.textContent?.trim()
        || document.title.replace(' - YouTube', '');
      return { platform: 'youtube', title, contentId: videoId };
    }

    destroy() {
      window.removeEventListener('message', this._onMessage);
      if (this._rafId) cancelAnimationFrame(this._rafId);
    }

    // ── YouTube 전용 ─────────────────────────────────────────────────

    _handleMessage(e) {
      if (e.source !== window) return;
      const { type, tracks } = e.data || {};

      // page_script.js 가 보내는 트랙 목록 (langCode + baseUrl)
      if (type === 'EH_TRACKS_AVAILABLE' && tracks?.length) {
        this._availableTracks = tracks;
        this._loadTracks();
      }
      // 기존 호환: 단일 자막 XML 직접 전달
      if ((type === 'EH_CAPTIONS_CAPTURED' || type === 'EH_CAPTURED_CAPTIONS_RESULT') && e.data.text) {
        this._enCues = this._parseXml(e.data.text);
        this._triggerTracksReady();
      }
    }

    async _loadTracks() {
      const nativeLang = window.EH.settings?.nativeLang || 'ko';
      const enTrack = this._availableTracks.find(t => t.langCode === 'en' || t.langCode === 'en-US');
      const nativeTrack = this._availableTracks.find(t => t.langCode === nativeLang);

      if (enTrack) {
        const res = await chrome.runtime.sendMessage({ type: 'FETCH_CAPTIONS', payload: { url: enTrack.baseUrl } });
        if (res.success) this._enCues = this._parseXml(res.text);
      }
      if (nativeTrack) {
        const res = await chrome.runtime.sendMessage({ type: 'FETCH_CAPTIONS', payload: { url: nativeTrack.baseUrl } });
        if (res.success) this._nativeCues = this._parseXml(res.text);
      }
      this._triggerTracksReady();
    }

    _triggerTracksReady() {
      if (this._tracksCb) {
        this._tracksCb(this.getSubtitleTracks());
      }
    }

    _parseXml(xmlText) {
      try {
        const doc = new DOMParser().parseFromString(xmlText, 'text/xml');
        const items = [];
        for (const el of doc.querySelectorAll('p')) {
          const start = parseFloat(el.getAttribute('t') || '0') / 1000;
          const dur   = parseFloat(el.getAttribute('d') || '3000') / 1000;
          const text  = this._decodeEntities(el.textContent || '').replace(/\n/g, ' ').trim();
          if (text) items.push({ start, end: start + dur, text });
        }
        if (!items.length) {
          for (const el of doc.querySelectorAll('text')) {
            const start = parseFloat(el.getAttribute('start') || '0');
            const dur   = parseFloat(el.getAttribute('dur') || '3');
            const text  = this._decodeEntities(el.textContent || '').replace(/\n/g, ' ').trim();
            if (text) items.push({ start, end: start + dur, text });
          }
        }
        return this._mergeCues(items);
      } catch (e) { return []; }
    }

    _decodeEntities(str) {
      const el = document.createElement('textarea');
      el.innerHTML = str;
      return el.value;
    }

    _mergeCues(items) {
      if (!items.length) return [];
      const merged = [{ ...items[0] }];
      for (let i = 1; i < items.length; i++) {
        const prev = merged[merged.length - 1];
        const cur = items[i];
        if ((cur.start - prev.end) < 1.2 && (prev.text + cur.text).length < 130) {
          prev.text += ' ' + cur.text;
          prev.end = cur.end;
        } else {
          merged.push({ ...cur });
        }
      }
      return merged;
    }

    _getCueAtTime(cues, t) {
      let lo = 0, hi = cues.length - 1;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        const c = cues[mid];
        if (t < c.start) hi = mid - 1;
        else if (t > c.end) lo = mid + 1;
        else return c;
      }
      return null;
    }

    _initVideoTracking() {
      // RAF 루프로 현재 자막 감지
      const tick = () => {
        const video = document.querySelector('video');
        if (video && !video.paused && this._enCues.length) {
          const t = video.currentTime + 0.1;
          const enCue = this._getCueAtTime(this._enCues, t);
          const nativeCue = this._getCueAtTime(this._nativeCues, t);
          const enText = enCue?.text || '';
          const nativeText = nativeCue?.text || '';

          if (enText !== this._lastEnText || nativeText !== this._lastNativeText) {
            this._lastEnText = enText;
            this._lastNativeText = nativeText;
            const nativeLang = window.EH.settings?.nativeLang || 'ko';
            if (this._subtitleCb) {
              this._subtitleCb([
                { lang: 'en', text: enText },
                { lang: nativeLang, text: nativeText }
              ]);
            }
          }
        }
        this._rafId = requestAnimationFrame(tick);
      };
      this._rafId = requestAnimationFrame(tick);

      // SPA 라우팅 — 영상 변경 감지
      let lastUrl = location.href;
      new MutationObserver(() => {
        if (location.href !== lastUrl) {
          lastUrl = location.href;
          this._enCues = [];
          this._nativeCues = [];
          this._lastEnText = '';
          this._lastNativeText = '';
          this._currentVideoId = '';
          // page_script.js 에 새 자막 로드 요청
          setTimeout(() => {
            window.postMessage({ type: 'EH_GET_CAPTURED_CAPTIONS' }, '*');
          }, 500);
        }
      }).observe(document, { subtree: true, childList: true });

      // 초기 자막 요청
      setTimeout(() => {
        window.postMessage({ type: 'EH_GET_CAPTURED_CAPTIONS' }, '*');
      }, 1000);
    }
  }

  // 코어가 로드된 후 어댑터 등록
  window.EH.init(new YouTubeAdapter());
})();
```

- [ ] **Step 2: inject/page_script.js 업데이트 — EH_TRACKS_AVAILABLE 메시지 추가**

기존 page_script.js에서 자막 트랙 목록을 탐지하면 `EH_TRACKS_AVAILABLE`를 postMessage로 전송하도록 추가:

```js
// inject/page_script.js 하단에 추가 (기존 코드 유지)

// 플레이어 응답에서 captions 트랙 목록 추출
function extractTracks(playerResponse) {
  try {
    const captions = playerResponse?.captions?.playerCaptionsTracklistRenderer;
    if (!captions?.captionTracks) return;
    const tracks = captions.captionTracks.map(t => ({
      langCode: t.languageCode,
      baseUrl: t.baseUrl
    }));
    window.postMessage({ type: 'EH_TRACKS_AVAILABLE', tracks }, '*');
  } catch (e) {}
}

// fetch 인터셉트에서 플레이어 응답 파싱 후 extractTracks 호출
const _origFetch = window.fetch;
window.fetch = async function(...args) {
  const res = await _origFetch.apply(this, args);
  const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
  if (url.includes('/youtubei/v1/player')) {
    const clone = res.clone();
    clone.json().then(extractTracks).catch(() => {});
  }
  return res;
};
```

- [ ] **Step 3: YouTube 수동 테스트**

1. YouTube 영상 재생 (영어 + 한국어 자막 있는 영상)
2. 자막 오버레이 표시 확인 (영어 흰색 + 한국어 노란색)
3. 사이드패널에 스크립트 목록 표시 확인
4. 영어 단어 클릭 → 단어 팝업 표시 확인
5. 팝업에서 "단어 저장" 클릭 → 토스트 "저장됨" 확인

- [ ] **Step 4: 커밋**

```bash
git add adapters/youtube.js inject/page_script.js
git commit -m "feat: add YouTube adapter with dual subtitle track support"
```

---

### Task 8: adapters/netflix.js — Netflix 어댑터

Netflix는 영어 자막과 한국어 자막을 별도 DOM 요소로 동시에 렌더링한다.  
두 트랙의 DOM을 감지해 텍스트를 추출하고, 플랫폼 기본 자막을 숨긴 뒤 EH 오버레이를 표시한다.

**Files:**
- Create: `adapters/netflix.js`

**Interfaces:**
- Consumes: `window.EH.SubtitleAdapter`
- Produces: `SubtitleAdapter` 인터페이스 전부 구현

- [ ] **Step 1: adapters/netflix.js 작성**

```js
(function () {
  'use strict';

  // Netflix 자막 선택자 (구조 변경에 대비해 복수 후보)
  const EN_SELECTORS = [
    '.player-timedtext-text-container span',
    '[data-uia="player-timedtext"] span',
    '.nf-subtitle-container span'
  ];
  // Netflix는 lang attribute 또는 aria-label로 트랙을 구분함
  const NATIVE_SELECTORS = [
    '.player-timedtext[lang]:not([lang="en"]) span',
    '[data-uia="player-timedtext"][lang]:not([lang="en"]) span'
  ];

  class NetflixAdapter extends window.EH.SubtitleAdapter {
    constructor() {
      super();
      this._subtitleCb = null;
      this._observer = null;
      this._hiddenStyle = null;
      this._lastEnText = '';
      this._lastNativeText = '';
    }

    getSubtitleTracks() {
      // Netflix는 실시간 DOM에서만 현재 자막을 제공 — 전체 트랙 사전 로드 불가
      return [{ lang: 'en', cues: [] }];
    }

    getCurrentTime() {
      return document.querySelector('video')?.currentTime || 0;
    }

    seekTo(seconds) {
      const video = document.querySelector('video');
      if (video) video.currentTime = seconds;
    }

    onSubtitleChange(callback) {
      this._subtitleCb = callback;
      this._startObserving();
    }

    onTimeUpdate(callback) {}

    onTracksReady(callback) {
      // Netflix는 전체 트랙을 제공하지 않으므로 즉시 빈 배열로 호출
      callback([{ lang: 'en', cues: [] }]);
    }

    getPlatformMeta() {
      const title = document.querySelector('.video-title')?.textContent?.trim()
        || document.querySelector('[data-uia="video-title"]')?.textContent?.trim()
        || document.title.replace(' | Netflix', '');
      const contentId = location.pathname.split('/').pop() || '';
      return { platform: 'netflix', title, contentId };
    }

    destroy() {
      this._observer?.disconnect();
      this._hiddenStyle?.remove();
    }

    // ── Netflix 전용 ─────────────────────────────────────────────────

    _getText(selectors) {
      for (const sel of selectors) {
        const els = document.querySelectorAll(sel);
        if (els.length) return Array.from(els).map(e => e.textContent.trim()).filter(Boolean).join(' ');
      }
      return '';
    }

    _hideNativeSubtitles() {
      if (this._hiddenStyle) return;
      this._hiddenStyle = document.createElement('style');
      // Netflix 자막 DOM을 숨기고 EH 오버레이로 대체
      this._hiddenStyle.textContent = '.player-timedtext { visibility: hidden !important; } [data-uia="player-timedtext"] { visibility: hidden !important; }';
      document.head.appendChild(this._hiddenStyle);
    }

    _startObserving() {
      this._hideNativeSubtitles();
      if (this._observer) this._observer.disconnect();

      this._observer = new MutationObserver(() => {
        const enText = this._getText(EN_SELECTORS);
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        const nativeText = this._getText(NATIVE_SELECTORS);

        if (enText === this._lastEnText && nativeText === this._lastNativeText) return;
        this._lastEnText = enText;
        this._lastNativeText = nativeText;

        if (this._subtitleCb) {
          this._subtitleCb([
            { lang: 'en', text: enText },
            { lang: nativeLang, text: nativeText }
          ]);
        }
      });

      const root = document.querySelector('.NFPlayer') || document.body;
      this._observer.observe(root, { childList: true, subtree: true, characterData: true });
    }
  }

  // Netflix SPA 라우팅 대응
  let lastUrl = location.href;
  let adapter = null;

  function startAdapter() {
    adapter?.destroy();
    adapter = new NetflixAdapter();
    window.EH.init(adapter);
  }

  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(startAdapter, 2000); // Netflix 플레이어 로드 대기
    }
  }).observe(document, { subtree: true, childList: true });

  startAdapter();
})();
```

- [ ] **Step 2: Netflix 수동 테스트**

1. Netflix 영상 재생 (영어 + 한국어 자막 선택)
2. 기본 Netflix 자막이 숨겨지고 EH 오버레이 표시 확인
3. 영어/한국어 이중 자막 표시 확인
4. 단어 클릭 → 팝업 표시 확인

- [ ] **Step 3: 커밋**

```bash
git add adapters/netflix.js
git commit -m "feat: add Netflix adapter with DOM MutationObserver dual subtitle"
```

---

### Task 9: adapters/disney.js — Disney+ 어댑터

**Files:**
- Create: `adapters/disney.js`

**Interfaces:**
- Consumes: `window.EH.SubtitleAdapter`
- Produces: `SubtitleAdapter` 인터페이스 전부 구현

- [ ] **Step 1: adapters/disney.js 작성**

```js
(function () {
  'use strict';

  // Disney+ 자막 선택자 (2024 구조 기준, 변경될 수 있음)
  const EN_SELECTORS = [
    '[data-testid="player-ux-subtitle-renderer"] span',
    '.subtitle-container span',
    '[class*="SubtitleTextContainer"] span'
  ];
  const NATIVE_SELECTORS = [
    '[data-testid="player-ux-subtitle-renderer"][lang]:not([lang="en"]) span',
    '[lang]:not([lang="en"]) [class*="SubtitleTextContainer"] span'
  ];

  class DisneyAdapter extends window.EH.SubtitleAdapter {
    constructor() {
      super();
      this._subtitleCb = null;
      this._observer = null;
      this._hiddenStyle = null;
      this._lastEnText = '';
      this._lastNativeText = '';
    }

    getSubtitleTracks() {
      return [{ lang: 'en', cues: [] }];
    }

    getCurrentTime() {
      return document.querySelector('video')?.currentTime || 0;
    }

    seekTo(seconds) {
      const video = document.querySelector('video');
      if (video) video.currentTime = seconds;
    }

    onSubtitleChange(callback) {
      this._subtitleCb = callback;
      this._startObserving();
    }

    onTimeUpdate(callback) {}

    onTracksReady(callback) {
      callback([{ lang: 'en', cues: [] }]);
    }

    getPlatformMeta() {
      const title = document.querySelector('[class*="title-field"]')?.textContent?.trim()
        || document.title.replace(' | Disney+', '');
      const contentId = location.pathname.split('/').filter(Boolean).pop() || '';
      return { platform: 'disney', title, contentId };
    }

    destroy() {
      this._observer?.disconnect();
      this._hiddenStyle?.remove();
    }

    _getText(selectors) {
      for (const sel of selectors) {
        const els = document.querySelectorAll(sel);
        if (els.length) return Array.from(els).map(e => e.textContent.trim()).filter(Boolean).join(' ');
      }
      return '';
    }

    _hideNativeSubtitles() {
      if (this._hiddenStyle) return;
      this._hiddenStyle = document.createElement('style');
      this._hiddenStyle.textContent = '[data-testid="player-ux-subtitle-renderer"] { visibility: hidden !important; } [class*="SubtitleTextContainer"] { visibility: hidden !important; }';
      document.head.appendChild(this._hiddenStyle);
    }

    _startObserving() {
      this._hideNativeSubtitles();
      if (this._observer) this._observer.disconnect();

      this._observer = new MutationObserver(() => {
        const enText = this._getText(EN_SELECTORS);
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        const nativeText = this._getText(NATIVE_SELECTORS);

        if (enText === this._lastEnText && nativeText === this._lastNativeText) return;
        this._lastEnText = enText;
        this._lastNativeText = nativeText;

        if (this._subtitleCb) {
          this._subtitleCb([
            { lang: 'en', text: enText },
            { lang: nativeLang, text: nativeText }
          ]);
        }
      });

      const root = document.querySelector('[class*="PlayerContainer"]') || document.body;
      this._observer.observe(root, { childList: true, subtree: true, characterData: true });
    }
  }

  let adapter = null;
  let lastUrl = location.href;

  function startAdapter() {
    adapter?.destroy();
    adapter = new DisneyAdapter();
    window.EH.init(adapter);
  }

  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(startAdapter, 2000);
    }
  }).observe(document, { subtree: true, childList: true });

  startAdapter();
})();
```

- [ ] **Step 2: Disney+ 수동 테스트**

1. Disney+ 영상 재생 (영어 + 한국어 자막)
2. EH 이중 자막 오버레이 표시 확인
3. 자막 선택자가 작동하지 않으면 DevTools로 실제 자막 DOM 요소 확인 후 `EN_SELECTORS` 업데이트

- [ ] **Step 3: 커밋**

```bash
git add adapters/disney.js
git commit -m "feat: add Disney+ adapter with DOM MutationObserver"
```

---

### Task 10: adapters/coupang.js — 쿠팡플레이 어댑터

쿠팡플레이 자막 DOM 구조는 사전 확인이 필요하다.  
아래 코드는 일반적인 OTT 패턴으로 작성했으며, 실제 배포 전 DevTools로 선택자를 검증해야 한다.

**Files:**
- Create: `adapters/coupang.js`

**Interfaces:**
- Consumes: `window.EH.SubtitleAdapter`
- Produces: `SubtitleAdapter` 인터페이스 전부 구현

- [ ] **Step 1: 쿠팡플레이 자막 DOM 구조 파악**

쿠팡플레이(play.coupang.com)에서 영상 재생 후 DevTools 콘솔에서 실행:
```js
// 자막 요소 탐색
document.querySelectorAll('[class*="subtitle"], [class*="caption"], [class*="text"]')
  .forEach(el => console.log(el.tagName, el.className, el.textContent.slice(0, 30)));
```
Expected: 자막 텍스트를 포함한 요소 목록 출력 → 선택자 확인

- [ ] **Step 2: adapters/coupang.js 작성** (Step 1에서 확인한 선택자 반영)

```js
(function () {
  'use strict';

  // Step 1에서 확인한 실제 선택자로 교체할 것
  const EN_SELECTORS = [
    '.subtitle-text span',
    '[class*="CaptionText"] span',
    '[class*="subtitle"] span'
  ];
  const NATIVE_SELECTORS = [
    '.subtitle-translation span',
    '[class*="CaptionTranslation"] span'
  ];

  class CoupangAdapter extends window.EH.SubtitleAdapter {
    constructor() {
      super();
      this._subtitleCb = null;
      this._observer = null;
      this._hiddenStyle = null;
      this._lastEnText = '';
      this._lastNativeText = '';
    }

    getSubtitleTracks() {
      return [{ lang: 'en', cues: [] }];
    }

    getCurrentTime() {
      return document.querySelector('video')?.currentTime || 0;
    }

    seekTo(seconds) {
      const video = document.querySelector('video');
      if (video) video.currentTime = seconds;
    }

    onSubtitleChange(callback) {
      this._subtitleCb = callback;
      this._startObserving();
    }

    onTimeUpdate(callback) {}

    onTracksReady(callback) {
      callback([{ lang: 'en', cues: [] }]);
    }

    getPlatformMeta() {
      const title = document.querySelector('[class*="title"]')?.textContent?.trim()
        || document.title.replace(' - 쿠팡플레이', '');
      const contentId = location.pathname.split('/').filter(Boolean).pop() || '';
      return { platform: 'coupang', title, contentId };
    }

    destroy() {
      this._observer?.disconnect();
      this._hiddenStyle?.remove();
    }

    _getText(selectors) {
      for (const sel of selectors) {
        const els = document.querySelectorAll(sel);
        if (els.length) return Array.from(els).map(e => e.textContent.trim()).filter(Boolean).join(' ');
      }
      return '';
    }

    _hideNativeSubtitles() {
      if (this._hiddenStyle) return;
      this._hiddenStyle = document.createElement('style');
      // Step 1에서 확인한 실제 자막 컨테이너 클래스로 교체
      this._hiddenStyle.textContent = '.subtitle-text { visibility: hidden !important; } [class*="CaptionText"] { visibility: hidden !important; }';
      document.head.appendChild(this._hiddenStyle);
    }

    _startObserving() {
      this._hideNativeSubtitles();
      if (this._observer) this._observer.disconnect();

      this._observer = new MutationObserver(() => {
        const enText = this._getText(EN_SELECTORS);
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        const nativeText = this._getText(NATIVE_SELECTORS);

        if (enText === this._lastEnText && nativeText === this._lastNativeText) return;
        this._lastEnText = enText;
        this._lastNativeText = nativeText;

        if (this._subtitleCb) {
          this._subtitleCb([
            { lang: 'en', text: enText },
            { lang: nativeLang, text: nativeText }
          ]);
        }
      });

      const root = document.querySelector('[class*="Player"]') || document.body;
      this._observer.observe(root, { childList: true, subtree: true, characterData: true });
    }
  }

  let adapter = null;
  let lastUrl = location.href;

  function startAdapter() {
    adapter?.destroy();
    adapter = new CoupangAdapter();
    window.EH.init(adapter);
  }

  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(startAdapter, 2000);
    }
  }).observe(document, { subtree: true, childList: true });

  startAdapter();
})();
```

- [ ] **Step 3: 쿠팡플레이 수동 테스트**

1. play.coupang.com 에서 영어 콘텐츠 재생
2. 자막 오버레이 표시 확인
3. 자막이 표시되지 않으면 Step 1 재실행 후 선택자 업데이트

- [ ] **Step 4: 커밋**

```bash
git add adapters/coupang.js
git commit -m "feat: add Coupang Play adapter with DOM MutationObserver"
```

---

## Plan B 완료 체크리스트

- [ ] Task 7: YouTube 어댑터 — 이중 트랙 fetch, RAF 루프
- [ ] Task 8: Netflix 어댑터 — DOM Observer, 자막 숨김
- [ ] Task 9: Disney+ 어댑터 — DOM Observer, 자막 숨김
- [ ] Task 10: 쿠팡플레이 어댑터 — DOM 구조 확인 후 선택자 반영

**Plan B 완료 후 → Plan C (popup-export) 로 이동**
