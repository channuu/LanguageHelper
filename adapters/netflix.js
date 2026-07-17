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
  let adapter = null;
  let lastUrl = location.href;

  function startAdapter() { adapter?.destroy(); adapter = new NetflixAdapter(); window.EH.init(adapter); }

  new MutationObserver(() => { if (location.href !== lastUrl) { lastUrl = location.href; setTimeout(startAdapter, 2000); } }).observe(document, { subtree: true, childList: true });

  startAdapter();
})();
