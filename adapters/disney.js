(function () {
  'use strict';

  const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

  // 켜면 RAF 틱 상태를 <html data-eh-diag>에 적는다. 콘텐츠 스크립트는 격리된
  // 세계에서 돌아 페이지 쪽에서 내부 상태를 볼 수 없으므로, 자막이 멈추는
  // 증상을 조사할 때 DOM을 통해 밖으로 내보내는 통로가 필요하다.
  const DEBUG = false;

  class DisneyAdapter extends window.EH.SubtitleAdapter {
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
      this._retryTimer = null;
      // 프로그램 시각 = video.currentTime + _timeOffset (inject에서 갱신)
      this._timeOffset = 0;
      this._duration = 0;

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
      const video = this._video();
      return video ? video.currentTime + this._timeOffset : 0;
    }

    // seconds는 프로그램 시각(자막 cue 기준)이다.
    seekTo(seconds) {
      const video = this._video();
      if (!video) return;
      const target = seconds - this._timeOffset; // <video> 타임라인으로 환산

      let inRange = false;
      for (let i = 0; i < video.seekable.length; i++) {
        if (target >= video.seekable.start(i) && target <= video.seekable.end(i)) { inRange = true; break; }
      }
      if (inRange) { video.currentTime = target; return; }

      // 아직 플레이어가 잡아두지 않은 구간. currentTime에 그냥 넣으면
      // 브라우저가 seekable 범위로 "잘라내" 엉뚱한 지점으로 보내버린다
      // (14:00을 눌렀는데 1:44로 가는 증상). 플레이어 자체 진행바를 눌러
      // 플레이어가 스스로 버퍼를 다시 잡게 하는 수밖에 없다.
      const before = this._timeOffset;
      const notify = () => window.EH.showToast?.('아직 재생하지 않은 구간이라 바로 이동할 수 없어요 · 진행바를 써 주세요');
      this._seekViaProgressBar(seconds).then(async (dispatched) => {
        if (!dispatched) { notify(); return; }
        // 진행바는 픽셀 단위라 몇 초씩 어긋난다(1677초를 1386px에 담으면
        // 1px ≈ 1.2초). 클릭한 문장의 첫머리를 놓치지 않으려면, 플레이어가
        // 새 구간을 잡아 그 근처가 seekable이 된 뒤 currentTime으로 정확히
        // 다시 맞춰야 한다. 타임라인이 리베이스되면서 _timeOffset이 갱신되는
        // 것을 신호로 삼는다 — 갱신 전의 낡은 오프셋으로 환산하면 엉뚱한
        // 지점을 짚는다.
        for (let i = 0; i < 40; i++) {
          await new Promise(r => setTimeout(r, 100));
          if (this._timeOffset === before) continue;
          const t = seconds - this._timeOffset;
          for (let k = 0; k < video.seekable.length; k++) {
            if (t >= video.seekable.start(k) && t <= video.seekable.end(k)) {
              video.currentTime = t;
              return;
            }
          }
        }
        if (Math.abs(this.getCurrentTime() - seconds) > 5) notify();
      }).catch(() => notify());
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
      const title = document.title
        .replace(/\s*\|\s*디즈니\+\s*$/, '')
        .replace(/\s*\|\s*Disney\+\s*$/, '')
        .trim();
      return { platform: 'disney', title, contentId: this._getContentId() };
    }

    destroy() {
      window.removeEventListener('message', this._onMessage);
      if (this._rafId) cancelAnimationFrame(this._rafId);
      if (this._retryTimer) clearInterval(this._retryTimer);
      this._hiddenStyle?.remove();
    }

    // ── Disney+ 전용 ─────────────────────────────────────────────────

    // Disney+ 페이지에는 <video>가 둘 있다. 하나는 자막 스타일 클래스만
    // 얹어둔 더미(.btm-media-client-element, readyState 0, currentTime이 늘 0)이고
    // 실제 재생은 .hive-video에서 일어난다. document.querySelector('video')는
    // 더미를 집어오므로 재생 위치를 영영 못 읽는다.
    _video() {
      return document.querySelector('video.hive-video')
        || Array.from(document.querySelectorAll('video')).find(v => v.readyState > 0)
        || document.querySelector('video');
    }

    // 플레이어 UI는 전부 shadow DOM 안에 있어 일반 셀렉터로 못 찾는다.
    _findInShadow(tagName) {
      let hit = null;
      (function walk(root, depth) {
        if (depth > 8 || hit) return;
        let els;
        try { els = root.querySelectorAll('*'); } catch (e) { return; }
        for (const el of els) {
          if (el.tagName === tagName) { hit = el; return; }
          if (el.shadowRoot) walk(el.shadowRoot, depth + 1);
        }
      })(document, 0);
      return hit;
    }

    // 컨트롤이 숨어 있으면 진행바가 DOM에서 아예 빠지므로 먼저 깨운다.
    _revealControls() {
      const video = this._video();
      const targets = [video, video && video.parentElement, document.body, document]
        .filter(Boolean);
      for (const type of ['mouseover', 'mousemove', 'pointermove']) {
        for (const t of targets) {
          t.dispatchEvent(new MouseEvent(type, {
            bubbles: true, composed: true,
            clientX: Math.round(innerWidth / 2), clientY: Math.round(innerHeight / 2)
          }));
        }
      }
    }

    // 컨트롤을 깨운 직후에는 진행바가 아직 DOM에 붙기 전이다. 마운트될
    // 틈을 주고 다시 찾아야 한다 — 바로 조회하면 늘 실패한다.
    async _seekViaProgressBar(programSeconds) {
      if (!this._duration) return false;
      this._revealControls();
      let pb = this._findInShadow('PROGRESS-BAR');
      for (let i = 0; i < 12 && !pb; i++) {
        await new Promise(r => setTimeout(r, 100));
        pb = this._findInShadow('PROGRESS-BAR');
      }
      const bar = pb && pb.shadowRoot &&
        (pb.shadowRoot.querySelector('.progress-bar__seekable-range')
         || pb.shadowRoot.querySelector('.progress-bar__container'));
      if (!bar) return false;
      const r = bar.getBoundingClientRect();
      if (!r.width) return false;

      const ratio = Math.min(1, Math.max(0, programSeconds / this._duration));
      const opt = {
        bubbles: true, cancelable: true, composed: true,
        clientX: Math.round(r.left + r.width * ratio),
        clientY: Math.round(r.top + r.height / 2),
        pointerId: 1, isPrimary: true, button: 0, buttons: 1
      };
      bar.dispatchEvent(new PointerEvent('pointerover', opt));
      bar.dispatchEvent(new PointerEvent('pointermove', opt));
      bar.dispatchEvent(new PointerEvent('pointerdown', opt));
      bar.dispatchEvent(new PointerEvent('pointerup', Object.assign({}, opt, { buttons: 0 })));
      bar.dispatchEvent(new MouseEvent('click', Object.assign({}, opt, { buttons: 0 })));
      return true;
    }

    _getContentId() {
      const m = location.pathname.match(UUID_RE);
      return m ? m[0] : '';
    }

    _hideNativeSubtitles() {
      if (this._hiddenStyle) return;
      this._hiddenStyle = document.createElement('style');
      // Disney+ 자막은 <timed-text-override-region>의 shadow DOM 안에서
      // 그려진다. 그림자 속 노드는 셀렉터로 잡을 수 없지만 호스트 엘리먼트는
      // 라이트 DOM에 있으므로, 호스트를 숨기면 안에 그려지는 자막까지 사라진다.
      this._hiddenStyle.textContent = 'timed-text-override-region { visibility: hidden !important; }';
      document.head.appendChild(this._hiddenStyle);
    }

    _handleMessage(e) {
      if (e.source !== window) return;

      if (e.data?.type === 'EH_DP_TIME_OFFSET') {
        if (this._timeOffset === e.data.offsetSec) return;
        this._timeOffset = e.data.offsetSec;
        // 시각 기준이 통째로 바뀌었으니 지금 떠 있는 자막은 무효다.
        this._lastEnText = '';
        this._lastNativeText = '';
        this._lastTickTime = -1;
        return;
      }

      if (e.data?.type !== 'EH_DP_CAPTIONS_LOADED') return;
      if (e.data.durationSec) this._duration = e.data.durationSec;

      // 영상이 바뀐 뒤 늦게 도착한 이전 영상용 응답은 무시
      if (e.data.contentId && e.data.contentId !== this._getContentId()) return;

      if (e.data.enVtt)     this._enCues     = this._parseVtt(e.data.enVtt);
      if (e.data.nativeVtt) this._nativeCues = this._parseVtt(e.data.nativeVtt);
      if (this._enCues.length && this._retryTimer) {
        clearInterval(this._retryTimer);
        this._retryTimer = null;
      }
      this._triggerTracksReady();
    }

    _triggerTracksReady() {
      if (this._tracksCb) {
        this._tracksCb(this.getSubtitleTracks());
      }
    }

    // Disney+는 분할 WebVTT를 내려준다. 조각마다 WEBVTT 헤더와 STYLE 블록이
    // 다시 나오지만 타임스탬프 줄만 읽으므로 그대로 이어붙여 파싱하면 된다.
    // 타임스탬프가 프로그램 시작 기준 절대 시각이라(X-TIMESTAMP-MAP 없음)
    // 조각별 오프셋 보정도 필요 없다. 큐 세팅(line:95%,end)은 Netflix
    // 어댑터와 같은 방식으로 떨어낸다.
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
          const endStr = rest.trim().split(/\s+/)[0]; // cue 세팅(line:.. align:..) 제거
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
      // 세그먼트가 순서대로 도착하지 않을 수 있고, 실패분을 건너뛴 채로도
      // 파싱하므로 시작 시각으로 정렬해 둔다 — 이분 탐색의 전제다.
      items.sort((a, b) => a.start - b.start);
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
        const video = this._video();
        // 재생 중일 때만 계산하면, 정지 상태에서 스크립트 패널의 다른 시점을
        // 눌렀을 때 영상만 이동하고 자막은 이전 문장에 그대로 남는다.
        // 시간이 바뀐 프레임에서는 정지 중이어도 다시 계산한다 — 진짜로 멈춰
        // 있는 동안에는 시간이 변하지 않으므로 예전처럼 아무 일도 하지 않는다.
        const nowTime = video ? video.currentTime + this._timeOffset : -1;
        const timeChanged = nowTime !== this._lastTickTime;
        this._lastTickTime = nowTime;
        if (DEBUG) {
          this._tickN = (this._tickN || 0) + 1;
          if (!this._diagAt || performance.now() - this._diagAt > 400) {
            this._diagAt = performance.now();
            document.documentElement.setAttribute('data-eh-diag', JSON.stringify({
              n: this._tickN, t: +nowTime.toFixed(2), paused: video ? video.paused : null,
              en: this._enCues.length, na: this._nativeCues.length, cb: !!this._subtitleCb,
              last: this._lastEnText.slice(0, 25)
            }));
          }
        }
        if (video && (!video.paused || timeChanged) && this._enCues.length) {
          const t = nowTime + 0.1;
          const enCue = this._getCueAtTime(this._enCues, t);
          // native(번역) 자막은 자기 cue의 [start,end]로 독립적으로 찾지
          // 않는다 — 언어별로 자막 파일을 따로 만들다 보니 번역 줄이
          // 원본보다 일찍 끝나는 경우가 흔한데, 그러면 번역이 먼저 사라지고
          // 영어만 잠깐 혼자 남아 "영어 자막이 계속/다시 표시되는" 것처럼
          // 보인다. 시작 시각으로 영어 cue와 짝을 맞춰 영어가 떠 있는 동안은
          // 항상 같이 보여준다.
          const nativeCue = enCue ? window.EH.CueUtils.findPairedCue(this._nativeCues, enCue) : null;
          // §1h "한 줄에 표시할 분량" — 스크립트 패널과 반드시 같은 문장을
          // 보여줘야 하므로 청크 분할도 core/cue-utils.js를 그대로 쓴다.
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
                if (DEBUG) document.documentElement.setAttribute('data-eh-err', String(err && err.stack || err).slice(0, 300));
              }
            }
          }
        }
        this._rafId = requestAnimationFrame(tick);
      };
      this._rafId = requestAnimationFrame(tick);
      if (DEBUG) document.documentElement.setAttribute('data-eh-diag', '{"n":0,"boot":true}');

      const triggerLoad = () => {
        const contentId = this._getContentId();
        if (!contentId) return;
        const nativeLang = window.EH.settings?.nativeLang || 'ko';
        window.postMessage({ type: 'EH_DP_TRIGGER_LOAD', contentId, nativeLang }, '*');
      };

      // 마스터 플레이리스트가 언제 오갈지는 플레이어 사정이라, 한 번 찔러
      // 보고 마는 대신 자막이 들어올 때까지 주기적으로 다시 요청한다.
      const startRequesting = () => {
        if (this._retryTimer) clearInterval(this._retryTimer);
        triggerLoad();
        let tries = 0;
        this._retryTimer = setInterval(() => {
          if (this._enCues.length || ++tries > 15) {
            clearInterval(this._retryTimer);
            this._retryTimer = null;
            return;
          }
          triggerLoad();
        }, 2000);
      };

      // SPA 라우팅 — 영상 변경 감지
      let lastContentId = this._getContentId();
      new MutationObserver(() => {
        const contentId = this._getContentId();
        if (contentId !== lastContentId) {
          lastContentId = contentId;
          this._enCues = [];
          this._nativeCues = [];
          this._lastEnText = '';
          this._lastNativeText = '';
          // 다음 화로 넘어가도 코어 모듈을 다시 초기화하지 않는다 — 패널과
          // 리스너가 중복으로 생긴다. cue만 비우고 다시 받아오면 된다.
          if (contentId) setTimeout(startRequesting, 1500);
        }
      }).observe(document, { subtree: true, childList: true });

      // 초기 자막 요청 — 마스터가 캡처될 시간을 준다
      setTimeout(startRequesting, 1500);
    }
  }

  // 코어가 로드된 후 어댑터 등록
  window.EH.init(new DisneyAdapter());
})();
