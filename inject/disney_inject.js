// ================================================================
// inject/disney_inject.js — MAIN world 콘텐츠 스크립트 (document_start)
// Disney+ HLS 마스터 플레이리스트를 가로채 모든 언어의 분할 WebVTT를 수집
// ================================================================
(function () {

  const DEBUG = false;
  const dlog = DEBUG ? console.log.bind(console) : () => {};

  const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

  // 자막 트랙 목록이 든 마스터 플레이리스트. URL에 만료 시각과 hmac이 서명돼
  // 있어 우리가 만들어낼 수 없다 — 플레이어 요청에서 가로채는 수밖에 없다.
  let _master = null; // { url, text, contentId }
  let _durationSec = 0;

  function _currentContentId() {
    const m = location.pathname.match(UUID_RE);
    return m ? m[0] : null;
  }

  // 마스터와 변형(variant)·자막 플레이리스트가 모두 .m3u8이다. 자막 트랙
  // 목록(EXT-X-MEDIA)이 들어 있는 것만 마스터로 보고 잡아 둔다.
  function _captureIfMaster(url, text) {
    if (!text || text.indexOf('TYPE=SUBTITLES') === -1) return;
    // 본편 말고도 프로모·범퍼 같은 짧은 스트림이 자기 마스터를 따로 들고
    // 온다. 그쪽 자막 트랙은 zxx(= 대사 없음) 하나뿐이라, 늦게 왔다는
    // 이유로 덮어쓰면 본편 자막을 통째로 잃는다("자막 없음"). 영어 트랙이
    // 들어 있는 마스터만 잡는다 — 애초에 영어가 없으면 이 확장이 할 일이
    // 없으므로 조건을 좁혀도 잃는 것이 없다.
    if (!_pickTrack(_parseSubtitleTracks(text), 'en')) {
      dlog('[EH:dp] master without en track — ignored', text.length);
      return;
    }
    _master = { url, text, contentId: _currentContentId() };
    dlog('[EH:dp] master captured', text.length, _master.contentId);
  }

  // ── fetch 인터셉터 ────────────────────────────────────────────────
  const _origFetch = window.fetch;
  window.fetch = async function (...args) {
    const res = await _origFetch.apply(this, args);
    const url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '';
    if (url.includes('.m3u8')) {
      try { res.clone().text().then(t => _captureIfMaster(url, t)).catch(() => {}); } catch (e) {}
    }
    return res;
  };

  // ── XHR 인터셉터 — hive 플레이어가 버전에 따라 어느 쪽이든 쓴다 ─────
  const _origOpen = XMLHttpRequest.prototype.open;
  const _origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__ehUrl = typeof url === 'string' ? url : '';
    return _origOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function (...args) {
    if (this.__ehUrl && this.__ehUrl.includes('.m3u8')) {
      this.addEventListener('load', () => {
        try {
          const t = this.responseType === '' || this.responseType === 'text' ? this.responseText : null;
          if (typeof t === 'string') _captureIfMaster(this.__ehUrl, t);
        } catch (e) {}
      });
    }
    return _origSend.apply(this, args);
  };

  // ── 프로그램 시각 복구 ────────────────────────────────────────────
  // Disney+ 플레이어는 시크할 때마다 MSE 버퍼를 새로 잡으면서 <video>의
  // currentTime을 0 근처로 리베이스한다. 그래서 시크 뒤에는 currentTime이
  // 더 이상 프로그램 시각이 아니고, 자막 cue와 통째로 어긋난다.
  // 세그먼트 안의 타임스탬프는 프로그램 절대시각 그대로이고 플레이어는
  // SourceBuffer.timestampOffset으로 그걸 끌어내리는 것이므로,
  //   프로그램 시각 = video.currentTime - timestampOffset
  // 이 성립한다. 플레이어 UI(진행바 시각 라벨)를 읽는 방법도 있지만 컨트롤이
  // 떠 있을 때만 존재하고 1초 해상도라, 이 값을 쓰는 편이 정확하고 안정적이다.
  const _tsDesc = Object.getOwnPropertyDescriptor(SourceBuffer.prototype, 'timestampOffset');
  if (_tsDesc && _tsDesc.set) {
    let _pending = null, _timer = null;
    Object.defineProperty(SourceBuffer.prototype, 'timestampOffset', {
      configurable: true,
      enumerable: _tsDesc.enumerable,
      get() { return _tsDesc.get.call(this); },
      set(val) {
        // 플레이어는 시크마다 0으로 한 번 되돌린 뒤 실제 값을 넣는다. 그
        // 찰나의 0을 그대로 쓰면 자막이 한 번 튀므로 잠깐 묵혔다가 최종값만
        // 내보낸다 — 진짜로 0으로 끝나는 경우(맨 앞으로 이동)도 같이 처리된다.
        _pending = Number(val) || 0;
        clearTimeout(_timer);
        _timer = setTimeout(() => {
          window.postMessage({ type: 'EH_DP_TIME_OFFSET', offsetSec: -_pending }, '*');
          dlog('[EH:dp] program time offset', -_pending);
        }, 60);
        return _tsDesc.set.call(this, val);
      }
    });
  }

  // ── 마스터 파싱 ───────────────────────────────────────────────────

  function _parseSubtitleTracks(masterText) {
    return masterText.split('\n')
      .filter(l => l.startsWith('#EXT-X-MEDIA:') && l.includes('TYPE=SUBTITLES'))
      .map(l => {
        const attr = (k) => { const m = l.match(new RegExp(k + '="([^"]*)"')); return m ? m[1] : null; };
        return { lang: attr('LANGUAGE'), name: attr('NAME'), uri: attr('URI'), forced: /FORCED=YES/.test(l) };
      })
      // forced 자막은 외국어 대사만 번역한 것이라 대본이 아니다 — 제외한다.
      .filter(t => t.lang && t.uri && !t.forced);
  }

  function _pickTrack(tracks, lang) {
    if (!lang) return null;
    const lower = lang.toLowerCase();
    const base = lower.split('-')[0];
    return tracks.find(t => t.lang.toLowerCase() === lower)
        || tracks.find(t => t.lang.toLowerCase().split('-')[0] === base)
        || null;
  }

  // ── 세그먼트 수집 ─────────────────────────────────────────────────

  const _sleep = (ms) => new Promise(r => setTimeout(r, ms));

  // CDN이 몰아치는 요청을 끊는다 — 세그먼트를 병렬로 받으면 전부 실패하고
  // 순차로 받아도 일부가 떨어진다. 간격을 두고 하나씩 받되, 실패분은 대기를
  // 늘려 가며 다시 시도한다.
  async function _fetchWithRetry(url, tries = 3) {
    for (let i = 0; i < tries; i++) {
      try {
        const r = await fetch(url);
        if (r.ok) return await r.text();
      } catch (e) {}
      await _sleep(500 * (i + 1) * (i + 1));
    }
    return '';
  }

  // 세그먼트를 받는 대로 onProgress로 넘겨, 전부 모이기 전에도 스크립트
  // 패널이 채워지기 시작하게 한다. 조각마다 WEBVTT 헤더와 STYLE 블록이
  // 다시 나오지만, 타임스탬프 줄만 읽는 파서에는 영향이 없다.
  async function _loadTrack(track, masterUrl, onProgress) {
    const plUrl = new URL(track.uri, masterUrl).href;
    const pl = await _fetchWithRetry(plUrl);
    if (!pl) return '';

    // 진행바로 이동시키려면 전체 길이가 필요한데 video.duration이 null이다.
    // 이미 받은 플레이리스트의 EXTINF 합이 유일하고 정확한 출처다.
    const total = pl.split('\n')
      .filter(l => l.startsWith('#EXTINF'))
      .reduce((n, l) => n + (parseFloat(l.split(':')[1]) || 0), 0);
    if (total > 0) _durationSec = total;

    const segs = pl.split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#'));
    const parts = new Array(segs.length).fill('');
    for (let i = 0; i < segs.length; i++) {
      parts[i] = await _fetchWithRetry(new URL(segs[i], plUrl).href);
      if (onProgress) onProgress(parts.filter(Boolean).join('\n\n'));
      await _sleep(150);
    }
    dlog('[EH:dp] track', track.lang, 'segments', parts.filter(Boolean).length, '/', segs.length);
    return parts.filter(Boolean).join('\n\n');
  }

  // ── content script 메시지 수신 ───────────────────────────────────
  let _loading = false;

  window.addEventListener('message', async (e) => {
    if (e.source !== window) return;
    if (e.data?.type !== 'EH_DP_TRIGGER_LOAD') return;
    if (_loading) return;

    const { contentId, nativeLang } = e.data;
    if (!_master) { dlog('[EH:dp] master not captured yet'); return; }
    // 다음 화로 넘어간 뒤 이전 화의 마스터로 자막을 받아버리면 안 된다.
    if (_master.contentId && contentId && _master.contentId !== contentId) {
      dlog('[EH:dp] master is for another content'); return;
    }

    _loading = true;
    try {
      const tracks = _parseSubtitleTracks(_master.text);
      const en = _pickTrack(tracks, 'en');
      const native = _pickTrack(tracks, nativeLang);
      dlog('[EH:dp] en:', en && en.name, 'native:', native && native.name);

      let enVtt = '', nativeVtt = '';
      const post = () => window.postMessage({
        type: 'EH_DP_CAPTIONS_LOADED', contentId, enVtt, nativeVtt, nativeLang,
        durationSec: _durationSec
      }, '*');

      if (en) enVtt = await _loadTrack(en, _master.url, (t) => { enVtt = t; post(); });
      if (native && native !== en) {
        nativeVtt = await _loadTrack(native, _master.url, (t) => { nativeVtt = t; post(); });
      }
      post();
    } catch (err) {
      console.error('[EH:dp] TRIGGER error', err);
    } finally {
      _loading = false;
    }
  });
})();
