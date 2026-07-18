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
      try {
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
      } catch (e) {
        // extension context invalidated or network error — silently abort
      }
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
