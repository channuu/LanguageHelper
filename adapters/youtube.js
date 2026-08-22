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
      const { type } = e.data || {};

      if (type === 'EH_CAPTIONS_LOADED') {
        // 영상이 바뀐 뒤 늦게 도착한 이전 영상용 응답은 무시 (안 그러면 새 영상 자막이
        // 이전 영상 데이터로 덮어써질 수 있음)
        const currentVideoId = new URLSearchParams(location.search).get('v') || '';
        if (e.data.videoId && e.data.videoId !== currentVideoId) return;

        if (e.data.enXml)     this._enCues     = this._parseContent(e.data.enXml);
        if (e.data.nativeXml) this._nativeCues  = this._parseContent(e.data.nativeXml);
        // 자막 URL이 다른 확장(예: Language Reactor)에 의해 오염된 것으로 보이면
        // 조용히 빈 자막을 보여주는 대신 원인을 알린다 — 토스트(1회)와, 스크립트
        // 패널이 "자막 없음" 대신 안내 문구를 보여줄 수 있도록 이벤트로도 전달.
        document.dispatchEvent(new CustomEvent('eh-caption-conflict', {
          detail: { suspected: !!e.data.conflictSuspected }
        }));
        if (e.data.conflictSuspected && !this._conflictWarned) {
          this._conflictWarned = true;
          window.EH.showToast?.('다른 자막 확장 프로그램(예: Language Reactor)과 충돌해 자막을 불러오지 못했어요');
        }
        this._triggerTracksReady();
      }
    }

    _triggerTracksReady() {
      if (this._tracksCb) {
        this._tracksCb(this.getSubtitleTracks());
      }
    }

    // srv3/srv1 XML 또는 json3 포맷 자동 감지 후 파싱
    _parseContent(content) {
      if (!content) return [];
      return content.trimStart().startsWith('{')
        ? this._parseJson3(content)
        : this._parseXml(content);
    }

    _parseJson3(jsonText) {
      try {
        const data = JSON.parse(jsonText);
        const items = [];
        for (const ev of (data.events || [])) {
          if (!ev.segs) continue;
          const start = (ev.tStartMs || 0) / 1000;
          const dur   = (ev.dDurationMs || 3000) / 1000;
          const text  = ev.segs.map(s => s.utf8 || '').join('').replace(/\n/g, ' ').trim();
          if (text) items.push({ start, end: start + dur, text });
        }
        return this._mergeCues(items);
      } catch (e) { return []; }
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

    // LR과 동일: json3 이벤트(=YouTube 네이티브 자막 세그먼트) 하나 = 큐 하나.
    // 길이/문장 기준 병합은 하지 않는다. 간격이 사실상 0(≤10ms)인 인접
    // 조각만 최대 한 쌍씩 이어붙인다(YouTube가 한 줄을 두 이벤트로 쪼갠 경우 복원).
    _mergeCues(items) {
      if (!items.length) return [];

      // 빈 항목 제거 + 시간순 정렬
      const src = items
        .filter(it => it.text && it.text.trim())
        .map(it => ({ start: it.start, end: it.end, text: it.text.trim() }))
        .sort((a, b) => a.start - b.start);

      const out = [];
      for (let i = 0; i < src.length; i++) {
        const cur = src[i];
        const next = src[i + 1];
        const gap = next ? next.start - cur.end : Infinity; // 초 단위
        // 다음 조각과 간격이 ≤10ms면 한 쌍으로 병합 (LR 방식)
        if (next && gap <= 0.01) {
          out.push({ start: cur.start, end: next.end, text: cur.text + ' ' + next.text });
          i++; // 쌍으로 소비
        } else {
          out.push(cur);
        }
      }
      return out;
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
          this._conflictWarned = false;
          // 영상 변경 시 새 자막 로드
          setTimeout(() => {
            const nativeLang = window.EH.settings?.nativeLang || 'ko';
            window.postMessage({ type: 'EH_TRIGGER_CAPTION_LOAD', nativeLang }, '*');
          }, 1500);
        }
      }).observe(document, { subtree: true, childList: true });

      // 초기 자막 요청 — page_script가 page context에서 직접 fetch
      setTimeout(() => {
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        window.postMessage({ type: 'EH_TRIGGER_CAPTION_LOAD', nativeLang }, '*');
      }, 1500);
    }
  }

  // 코어가 로드된 후 어댑터 등록
  window.EH.init(new YouTubeAdapter());
})();
