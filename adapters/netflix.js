(function () {
  'use strict';

  class NetflixAdapter extends window.EH.SubtitleAdapter {
    constructor() {
      super();
      this._enCues = [];
      this._nativeCues = [];
      this._subtitleCb = null;
      this._tracksCb = null;
      this._rafId = null;
      this._lastEnText = '';
      this._lastNativeText = '';
      this._lastTickTime = -1;
      this._hiddenStyle = null;

      this._onMessage = this._handleMessage.bind(this);
      window.addEventListener('message', this._onMessage);
      this._hideNativeSubtitles();
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
      // Netflix 자체 플레이어 API로 이동시켜야 한다 — video.currentTime을
      // 직접 바꾸면 스트리밍 상태 관리자가 이를 인지 못 해 재생이 멈춘다.
      // 실제 API 호출은 페이지 컨텍스트(MAIN world)에서만 가능하므로
      // inject/netflix_inject.js로 메시지를 보내 처리한다.
      window.postMessage({ type: 'EH_NF_SEEK', seconds }, '*');
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
      const title = document.querySelector('[data-uia="video-title"]')?.textContent?.trim()
        || document.querySelector('.video-title')?.textContent?.trim()
        || document.title.replace(' | Netflix', '');
      return { platform: 'netflix', title, contentId: this._getMovieId() };
    }

    destroy() {
      window.removeEventListener('message', this._onMessage);
      if (this._rafId) cancelAnimationFrame(this._rafId);
      this._hiddenStyle?.remove();
    }

    // ── Netflix 전용 ─────────────────────────────────────────────────

    _getMovieId() {
      return location.pathname.split('/').pop() || '';
    }

    _hideNativeSubtitles() {
      if (this._hiddenStyle) return;
      this._hiddenStyle = document.createElement('style');
      // Netflix 자막 DOM을 숨기고 EH 오버레이로 대체
      this._hiddenStyle.textContent = '.player-timedtext { visibility: hidden !important; } [data-uia="player-timedtext"] { visibility: hidden !important; }';
      document.head.appendChild(this._hiddenStyle);
    }

    _handleMessage(e) {
      if (e.source !== window) return;
      if (e.data?.type !== 'EH_NF_CAPTIONS_LOADED') return;

      // 영상이 바뀐 뒤 늦게 도착한 이전 영상용 응답은 무시
      if (e.data.movieId && String(e.data.movieId) !== this._getMovieId()) return;

      if (e.data.enVtt)     this._enCues     = this._parseVtt(e.data.enVtt);
      if (e.data.nativeVtt) this._nativeCues = this._parseVtt(e.data.nativeVtt);
      this._triggerTracksReady();
    }

    _triggerTracksReady() {
      if (this._tracksCb) {
        this._tracksCb(this.getSubtitleTracks());
      }
    }

    // Netflix webvtt-lssdh-ios8 포맷(표준 WebVTT) 파서.
    // 큐가 이미 온전한 자막 줄 단위로 나뉘어 오므로 YouTube 어댑터처럼
    // 인접 조각을 병합할 필요는 없다.
    _parseVtt(vttText) {
      if (!vttText) return [];
      const timeRe = /(?:\d{2}:)?\d{2}:\d{2}\.\d{3}\s*-->\s*(?:\d{2}:)?\d{2}:\d{2}\.\d{3}/;
      const toSeconds = (ts) => {
        const parts = ts.split(':').map(Number);
        return parts.length === 3
          ? parts[0] * 3600 + parts[1] * 60 + parts[2]
          : parts[0] * 60 + parts[1];
      };

      const lines = vttText.replace(/\r/g, '').split('\n');
      const items = [];
      let i = 0;
      while (i < lines.length) {
        const line = lines[i].trim();
        if (timeRe.test(line)) {
          const [startStr, rest] = line.split('-->');
          const endStr = rest.trim().split(/\s+/)[0]; // cue 세팅(align:.. position:..) 제거
          const start = toSeconds(startStr.trim());
          const end = toSeconds(endStr);
          i++;
          const textLines = [];
          while (i < lines.length && lines[i].trim() !== '') {
            textLines.push(lines[i]);
            i++;
          }
          const text = textLines.join(' ')
            .replace(/<[^>]+>/g, '')   // <c>, <v>, <00:00:01.000> 등 태그 제거
            .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
            .replace(/\s+/g, ' ')
            .trim();
          if (text) items.push({ start, end, text });
        }
        i++;
      }
      return items;
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
        // 재생 중일 때만 계산하면, 정지 상태에서 스크립트 패널의 다른 시점을
        // 눌렀을 때 영상만 이동하고 자막은 이전 문장에 그대로 남는다.
        // 시간이 바뀐 프레임에서는 정지 중이어도 다시 계산한다 — 진짜로 멈춰
        // 있는 동안에는 시간이 변하지 않으므로 예전처럼 아무 일도 하지 않는다.
        const nowTime = video ? video.currentTime : -1;
        const timeChanged = nowTime !== this._lastTickTime;
        this._lastTickTime = nowTime;
        if (video && (!video.paused || timeChanged) && this._enCues.length) {
          const t = video.currentTime + 0.1;
          const enCue = this._getCueAtTime(this._enCues, t);
          // native(번역) 자막은 자기 cue의 [start,end]로 독립적으로 찾지
          // 않는다 — 넷플릭스가 언어별로 자막 파일을 따로 만들다 보니 번역
          // 줄이 원본보다 일찍 끝나는 경우가 흔한데, 그러면 번역이 먼저
          // 사라지고 영어만 잠깐 혼자 남아 "영어 자막이 계속/다시 표시되는"
          // 것처럼 보인다. 시작 시각으로 영어 cue와 짝을 맞춰 영어가 떠 있는
          // 동안은 항상 같이 보여준다.
          const nativeCue = enCue ? window.EH.CueUtils.findPairedCue(this._nativeCues, enCue) : null;
          // §1h "한 줄에 표시할 분량" — 스크립트 패널과 반드시 같은 문장을
          // 보여줘야 하므로 청크 분할도 core/cue-utils.js를 그대로 쓴다.
          // 번역도 (원문과 어순이 정확히 안 맞더라도) 영어 청크 개수에 맞춰
          // 같은 비율로 나눠서, 지금 보이는 영어 청크에 해당하는 분량만
          // 보여준다 — 스크립트 패널과 동일한 방식.
          const cueLines = window.EH.settings?.cueLines || 2;
          const chunk = enCue ? window.EH.CueUtils.getChunkAtTime(enCue, t, cueLines) : null;
          const enText = chunk?.text || '';
          const nativeText = (chunk && nativeCue)
            ? (window.EH.CueUtils.splitIntoNChunks(nativeCue.text, chunk.total)[chunk.index] || '')
            : '';

          if (enText !== this._lastEnText || nativeText !== this._lastNativeText) {
            this._lastEnText = enText;
            this._lastNativeText = nativeText;
            const nativeLang = window.EH.settings?.nativeLang || 'ko';
            if (this._subtitleCb) {
              // 렌더 중 난 예외가 여기서 새어 나가면 아래 requestAnimationFrame이
              // 예약되지 않아 루프가 죽고, 자막이 새로고침 전까지 영구히 멈춘다.
              // 한 프레임을 잃는 건 감수하되 루프는 반드시 살려 둔다.
              try {
                this._subtitleCb([
                  { lang: 'en', text: enText, fullText: enCue?.text || '', cueStart: enCue?.start },
                  { lang: nativeLang, text: nativeText }
                ]);
              } catch (err) {
                console.warn('[EH] 자막 렌더 실패 — 루프는 계속한다', err);
              }
            }
          }
        }
        this._rafId = requestAnimationFrame(tick);
      };
      this._rafId = requestAnimationFrame(tick);

      const triggerLoad = () => {
        const movieId = this._getMovieId();
        if (!movieId) return;
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        window.postMessage({ type: 'EH_NF_TRIGGER_LOAD', movieId, nativeLang }, '*');
      };

      // SPA 라우팅 — 영상 변경 감지
      let lastMovieId = this._getMovieId();
      new MutationObserver(() => {
        const movieId = this._getMovieId();
        if (movieId !== lastMovieId) {
          lastMovieId = movieId;
          this._enCues = [];
          this._nativeCues = [];
          this._lastEnText = '';
          this._lastNativeText = '';
          if (movieId) setTimeout(triggerLoad, 1500);
        }
      }).observe(document, { subtree: true, childList: true });

      // 초기 자막 요청 — 매니페스트가 캡처될 시간을 준다
      setTimeout(triggerLoad, 1500);
    }
  }

  // 코어가 로드된 후 어댑터 등록
  window.EH.init(new NetflixAdapter());
})();
