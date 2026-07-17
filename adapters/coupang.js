(function () {
  'use strict';

  // 쿠팡플레이 자막 선택자 (DOM 구조 확인 필요 — 아래는 일반적인 OTT 패턴)
  const EN_SELECTORS = [
    '.subtitle-text',
    '[class*="subtitle"] span',
    '.player-subtitle span'
  ];
  const NATIVE_SELECTORS = [
    '.subtitle-text[lang]:not([lang="en"])',
    '[class*="subtitle"][lang]:not([lang="en"]) span'
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
      const title = document.querySelector('.title-text')?.textContent?.trim()
        || document.title;
      const contentId = location.pathname.split('/').filter(Boolean).pop() || '';
      return { platform: 'coupang', title, contentId };
    }

    destroy() {
      this._observer?.disconnect();
      this._hiddenStyle?.remove();
    }

    // ── 쿠팡플레이 전용 ──────────────────────────────────────────────

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
      this._hiddenStyle.textContent = '.subtitle-text { visibility: hidden !important; } [class*="subtitle"] { visibility: hidden !important; }';
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

      const root = document.querySelector('.player-container') || document.body;
      this._observer.observe(root, { childList: true, subtree: true, characterData: true });
    }
  }

  let adapter = null;
  let lastUrl = location.href;
  function startAdapter() { adapter?.destroy(); adapter = new CoupangAdapter(); window.EH.init(adapter); }
  new MutationObserver(() => { if (location.href !== lastUrl) { lastUrl = location.href; setTimeout(startAdapter, 2000); } }).observe(document, { subtree: true, childList: true });
  startAdapter();
})();
