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
      this._hideNativeCaptions();
      this._initVideoTracking();
    }

    // pot 토큰을 얻으려고 page_script.js가 player.setOption('captions','track',...)을
    // 호출하는데, 이 호출 자체가 부작용으로 유튜브 자체 자막 표시를 켜버린다 —
    // 그러면 저희 오버레이 위에 유튜브 기본 자막 박스가 겹쳐서 두 겹으로 보인다.
    // Netflix 어댑터의 _hideNativeSubtitles()와 동일한 방식으로 CSS로 숨긴다.
    _hideNativeCaptions() {
      if (this._hiddenCaptionStyle) return;
      this._hiddenCaptionStyle = document.createElement('style');
      this._hiddenCaptionStyle.textContent = '.ytp-caption-window-container { display: none !important; }';
      document.head.appendChild(this._hiddenCaptionStyle);
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
      // #movie_player의 자체 seekTo API를 우선 사용한다 — video.currentTime을
      // 직접 바꾸면 YouTube 플레이어 내부의 버퍼링/스트리밍 상태 관리자가
      // 이 변경을 인지하지 못해 "재동기화"를 위해 재생을 멈춰버릴 수 있다
      // (실제로 스크립트 패널에서 줄 클릭 시 영상이 일시정지되는 버그로 확인됨).
      const player = document.querySelector('#movie_player');
      if (player && typeof player.seekTo === 'function') {
        const wasPlaying = typeof player.getPlayerState === 'function' && player.getPlayerState() === 1;
        player.seekTo(seconds, true);
        if (wasPlaying && typeof player.playVideo === 'function') player.playVideo();
        return;
      }
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
      this._hiddenCaptionStyle?.remove();
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
        // loadFailed: 변조 증거는 없지만(=다른 확장 탓이 아님) pot 타임아웃 등으로
        // 이번 시도에서 자막을 못 가져온 경우 — 최대 1회 자동 재시도한다.
        const loadFailed = !!e.data.loadFailed && !e.data.conflictSuspected;
        document.dispatchEvent(new CustomEvent('eh-caption-conflict', {
          detail: { suspected: !!e.data.conflictSuspected, loadFailed }
        }));
        if (e.data.conflictSuspected && !this._conflictWarned) {
          this._conflictWarned = true;
          window.EH.showToast?.('다른 자막 확장 프로그램(예: Language Reactor)과 충돌해 자막을 불러오지 못했어요');
        }
        if (loadFailed && !this._captionRetried && !this._enCues.length) {
          this._captionRetried = true;
          setTimeout(() => {
            const nativeLang = window.EH.settings?.nativeLang || 'ko';
            window.postMessage({ type: 'EH_TRIGGER_CAPTION_LOAD', nativeLang }, '*');
          }, 2000);
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
          // §1h "한 줄에 표시할 분량" — 스크립트 패널과 반드시 같은 문장을
          // 보여줘야 하므로 청크 분할도 core/cue-utils.js를 그대로 쓴다.
          // 번역은 패널과 마찬가지로 문장의 첫 청크에서만 보여준다(문장
          // 단위 번역이라 청크별로 쪼갤 수 없음).
          const cueLines = window.EH.settings?.cueLines || 2;
          const chunk = enCue ? window.EH.CueUtils.getChunkAtTime(enCue, t, cueLines) : null;
          const enText = chunk?.text || '';
          const nativeText = (chunk && chunk.isFirst) ? (nativeCue?.text || '') : '';

          if (enText !== this._lastEnText || nativeText !== this._lastNativeText) {
            this._lastEnText = enText;
            this._lastNativeText = nativeText;
            const nativeLang = window.EH.settings?.nativeLang || 'ko';
            if (this._subtitleCb) {
              this._subtitleCb([
                { lang: 'en', text: enText, fullText: enCue?.text || '' },
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
          this._captionRetried = false;
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

  // content_scripts는 youtube.com 전체(홈, 검색결과, 채널 페이지 등)에 매칭되므로,
  // 영상이 없는 페이지에서도 topbar/패널이 그대로 마운트돼 레이아웃을 불필요하게
  // 줄여버리는 문제가 있었다 — 실제로 /watch 페이지에 들어갈 때까지 초기화를
  // 미룬다. 홈에서 SPA 방식으로(새로고침 없이) 영상을 눌러 들어가는 경우를
  // 잡기 위해 MutationObserver로 경로 변화를 감시한다.
  function _isWatchPage() {
    return location.pathname === '/watch';
  }

  if (_isWatchPage()) {
    window.EH.init(new YouTubeAdapter());
  } else {
    const waitForWatch = new MutationObserver(() => {
      if (_isWatchPage()) {
        waitForWatch.disconnect();
        window.EH.init(new YouTubeAdapter());
      }
    });
    waitForWatch.observe(document, { subtree: true, childList: true });
  }
})();
