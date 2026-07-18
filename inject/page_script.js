// ================================================================
// inject/page_script.js — MAIN world 콘텐츠 스크립트 (document_start)
// YouTube 플레이어 응답 인터셉트 + 자막 XML fetch
// ================================================================
(function() {

  console.log('[EH] page_script.js loaded at', Date.now());

  // 가장 최근 player 응답에서 추출한 트랙 캐시 + pot 캐시
  let _cachedTracks = null;
  let _potCache = {};         // {videoId: pot}
  let _timedtextBase = {};    // {videoId: clean baseUrl (no pot/fmt/tlang)}

  // ── XHR 인터셉터 — timedtext URL에서 pot 토큰 캡처 ──────────────
  const _origXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    _extractPotFromUrl(url);
    return _origXHROpen.apply(this, arguments);
  };

  // ── timedtext URL에서 pot + base URL 추출 (XHR + fetch 공통 헬퍼) ──
  function _extractPotFromUrl(url) {
    if (typeof url !== 'string') return;
    if (!url.includes('timedtext')) return;
    try {
      const [path, qs] = url.split('?');
      const params = new URLSearchParams(qs || '');
      const pot = params.get('pot');
      const videoId = params.get('v');
      if (!videoId) return;
      if (pot) {
        _potCache[videoId] = pot;
        console.log('[EH] pot captured for', videoId, pot.slice(0, 20));
      }
      // YouTube가 사용한 clean baseUrl 저장 (pot/fmt/tlang 제거)
      if (!_timedtextBase[videoId]) {
        params.delete('pot');
        params.delete('fmt');
        params.delete('tlang');
        _timedtextBase[videoId] = path + '?' + params.toString();
        console.log('[EH] timedtext base saved for', videoId);
      }
    } catch (e) {}
  }

  // ── fetch 인터셉터 — /youtubei/v1/player 응답 + timedtext pot 캡처 ──
  const _origFetch = window.fetch;
  window.fetch = async function(...args) {
    const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
    _extractPotFromUrl(url);
    const res = await _origFetch.apply(this, args);
    if (url.includes('/youtubei/v1/player')) {
      const clone = res.clone();
      clone.json().then(data => {
        const tracks = data?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
        if (tracks?.length) {
          _cachedTracks = tracks;
          console.log('[EH] player response intercepted, tracks:', tracks.length);
          window.postMessage({ type: 'EH_TRACKS_AVAILABLE', tracks: tracks.map(t => ({ langCode: t.languageCode, baseUrl: t.baseUrl })) }, '*');
        }
      }).catch(() => {});
    }
    return res;
  };

  // ── pot 대기 (LR과 동일: 최대 3초) ─────────────────────────────
  async function waitForPot(videoId) {
    for (let i = 0; i < 6; i++) {
      if (_potCache[videoId]) return _potCache[videoId];
      await new Promise(r => setTimeout(r, 500));
    }
    return null;
  }

  // ── player.setOption으로 YouTube 내부 XHR 유발 → pot 수집 ───────
  function triggerYouTubeCaptionLoad(player, track) {
    try {
      if (player && typeof player.setOption === 'function') {
        player.setOption('captions', 'track', {
          languageCode: track.languageCode,
          vss_id: track.vss_id || ('.' + track.languageCode)
        });
      }
    } catch (e) {}
  }

  // ── pot 포함하여 자막 fetch ───────────────────────────────────────
  async function fetchCaptionXml(baseUrl, pot, tlang) {
    if (!baseUrl) return null;
    // 기존 fmt/tlang/pot 파라미터 제거 후 재조립
    const base = baseUrl
      .replace(/[&?]fmt=[^&]*/g, '')
      .replace(/[&?]tlang=[^&]*/g, '')
      .replace(/[&?]pot=[^&]*/g, '');
    const sep = base.includes('?') ? '&' : '?';
    let url = base + sep + 'fmt=json3';
    if (tlang) url += '&tlang=' + tlang;
    if (pot)   url += '&c=WEB&pot=' + encodeURIComponent(pot);
    try {
      const res = await _origFetch(url);
      const text = await res.text();
      console.log('[EH] fetch', tlang || 'en', 'status=', res.status, 'len=', text?.length);
      if (text && text.length > 10) return text;
    } catch (e) { console.warn('[EH] fetchCaptionXml error', e); }
    return null;
  }

  // ── content script 메시지 수신 ───────────────────────────────────
  window.addEventListener("message", async (e) => {
    if (e.source !== window) return;

    if (e.data?.type === "EH_TRIGGER_CAPTION_LOAD") {
      try {
        const nativeLang = e.data.nativeLang || 'ko';
        const player = document.querySelector("#movie_player");

        // 캐시된 트랙 우선, 없으면 getPlayerResponse() fallback
        let captionTracks = _cachedTracks;
        if (!captionTracks?.length) {
          captionTracks = player?.getPlayerResponse()
            ?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
        }
        if (!captionTracks?.length) {
          console.warn('[EH] no captionTracks available');
          return;
        }
        console.log('[EH] tracks:', captionTracks.map(t => t.languageCode + (t.kind ? '(' + t.kind + ')' : '')));

        // 'en', 'en-US', 'en-GB' 등 모두 매칭 (asr 아닌 것 우선)
        const isEn = t => t.languageCode?.startsWith('en');
        const enTrack = captionTracks.find(t => isEn(t) && t.kind !== 'asr')
                     || captionTracks.find(t => isEn(t));
        console.log('[EH] enTrack:', enTrack?.languageCode, enTrack?.baseUrl?.slice(0, 60) || 'NONE');

        // YouTube 내부 XHR 유발 → pot 수집 (LR 방식)
        if (enTrack) triggerYouTubeCaptionLoad(player, enTrack);

        // videoId 추출
        const videoId = new URLSearchParams(location.search).get('v') || '';
        console.log('[EH] waiting for pot, videoId=', videoId);
        const pot = videoId ? await waitForPot(videoId) : null;
        console.log('[EH] pot=', pot ? pot.slice(0, 20) + '...' : null);

        // baseUrl 결정: YouTube가 캡처한 URL 우선, 없으면 track.baseUrl
        const resolvedBase = _timedtextBase[videoId] || enTrack?.baseUrl || null;
        console.log('[EH] resolvedBase:', resolvedBase?.slice(0, 80) || 'NULL');

        const [enXml, nativeXml] = await Promise.all([
          fetchCaptionXml(resolvedBase, pot, null),
          fetchCaptionXml(resolvedBase, pot, nativeLang)
        ]);

        console.log('[EH] enXml len=', enXml?.length, 'nativeXml len=', nativeXml?.length);
        window.postMessage({
          type: 'EH_CAPTIONS_LOADED',
          enXml: enXml || '',
          nativeXml: nativeXml || '',
          nativeLang
        }, '*');
      } catch (err) { console.error('[EH] TRIGGER error', err); }
    }
  });
})();
