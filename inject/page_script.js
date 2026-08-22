// ================================================================
// inject/page_script.js — MAIN world 콘텐츠 스크립트 (document_start)
// YouTube 플레이어 응답 인터셉트 + 자막 XML fetch
// ================================================================
(function() {

  const DEBUG = false;
  const dlog = DEBUG ? console.log.bind(console) : () => {};

  // 가장 최근 player 응답에서 추출한 트랙 캐시 + pot 캐시
  let _cachedTracks = null;
  let _potCache = {};         // {videoId: pot}
  let _timedtextBase = {};    // {"videoId:langCode": clean baseUrl (no pot/fmt/tlang)}

  // ── XHR 인터셉터 — timedtext URL에서 pot 토큰 캡처 ──────────────
  const _origXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    _extractPotFromUrl(url);
    return _origXHROpen.apply(this, arguments);
  };

  // ── 다른 확장 프로그램(예: Language Reactor)이 같은 페이지 컨텍스트에서
  // fetch/XHR을 똑같이 가로채는 경우, 우리가 그 확장의 자체 프록시/난독화된
  // timedtext 요청을 "YouTube 진짜 요청"으로 착각해 캡처할 수 있다. 진짜
  // YouTube 파라미터의 형태와 명백히 다른 값(예: signature가 ip와 동일,
  // lang이 실제 언어 코드 형태가 아님)이면 신뢰하지 않고 무시한다. ──
  function _looksLikeRealTimedtextParams(params) {
    const lang = params.get('lang') || '';
    const sig = params.get('signature') || '';
    const ip = params.get('ip') || '';
    // 실제 YouTube 언어 코드는 소문자(+옵션 점/하이픈) 조합만 쓴다
    // (en, ko, a.en, en-US 등). 숫자가 섞인 짧은 토큰은 다른 확장이 채워
    // 넣은 난독화 값일 가능성이 높다.
    if (lang && !/^[a-zA-Z]{1,3}(\.[a-zA-Z]{1,3})?(-[A-Za-z0-9]+)?$/.test(lang)) return false;
    // signature가 ip와 완전히 같은 값이면 정상적인 서명이 아니다 — 다른
    // 확장이 익명화용으로 같은 자리표시자를 여러 필드에 채워 넣은 흔적.
    if (sig && ip && sig === ip) return false;
    return true;
  }

  // ── timedtext URL에서 pot + base URL 추출 (XHR + fetch 공통 헬퍼) ──
  function _extractPotFromUrl(url) {
    if (typeof url !== 'string') return;
    if (!url.includes('timedtext')) return;
    try {
      const [path, qs] = url.split('?');
      const params = new URLSearchParams(qs || '');
      if (!_looksLikeRealTimedtextParams(params)) {
        dlog('[EH] ignoring timedtext URL — looks mutated by another extension');
        return;
      }
      const pot = params.get('pot');
      const videoId = params.get('v');
      const lang = params.get('lang');
      if (!videoId) return;
      if (pot) {
        _potCache[videoId] = pot;
        dlog('[EH] pot captured for', videoId, pot.slice(0, 20));
      }
      // YouTube가 사용한 clean baseUrl 저장 (pot/fmt/tlang 제거), 트랙(lang)별로 캐싱
      // — 트랙마다 다른 요청이 섞여 들어올 수 있으므로 videoId만으로 키를 잡으면
      //   먼저 도착한 다른 언어 트랙의 baseUrl이 고정돼버린다.
      const key = videoId + ':' + (lang || '');
      if (!_timedtextBase[key]) {
        params.delete('pot');
        params.delete('fmt');
        params.delete('tlang');
        _timedtextBase[key] = path + '?' + params.toString();
        dlog('[EH] timedtext base saved for', key);
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
          dlog('[EH] player response intercepted, tracks:', tracks.length);
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

  // ── baseUrl 자체(예: player.getPlayerResponse()로 읽은 captionTracks[].baseUrl)가
  // 다른 확장(예: Language Reactor)에 의해 이미 오염된 값인지 확인. 네트워크 캡처
  // (_extractPotFromUrl)뿐 아니라 이 fallback 경로도 같은 검증을 거쳐야 한다 —
  // LR은 페이지의 player 응답 객체 자체를 패치하므로, 우리가 getPlayerResponse()로
  // 직접 읽어도 이미 변형된 값을 받을 수 있다. ──
  function _baseUrlLooksReal(baseUrl) {
    if (!baseUrl) return false;
    try {
      const qs = baseUrl.split('?')[1] || '';
      return _looksLikeRealTimedtextParams(new URLSearchParams(qs));
    } catch (e) {
      return true; // 파싱 자체가 실패하면 판단 보류 — 기존 동작 유지
    }
  }

  // ── pot 포함하여 자막 fetch ───────────────────────────────────────
  async function fetchCaptionXml(baseUrl, pot, tlang) {
    if (!baseUrl) return null;
    // 기존 fmt/tlang/pot 파라미터 제거 후 재조립 (파라미터 순서에 무관하게 안전)
    const [path, qs] = baseUrl.split('?');
    const params = new URLSearchParams(qs || '');
    params.delete('fmt');
    params.delete('tlang');
    params.delete('pot');
    params.set('fmt', 'json3');
    if (tlang) params.set('tlang', tlang);
    if (pot) { params.set('c', 'WEB'); params.set('pot', pot); }
    const url = path + '?' + params.toString();
    try {
      const res = await _origFetch(url);
      const text = await res.text();
      dlog('[EH] fetch', tlang || 'en', 'status=', res.status, 'len=', text?.length);
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
        dlog('[EH] tracks:', captionTracks.map(t => t.languageCode + (t.kind ? '(' + t.kind + ')' : '')));

        // 'en', 'en-US', 'en-GB' 등 모두 매칭 (asr 아닌 것 우선)
        const isEn = t => t.languageCode?.startsWith('en');
        const enTrack = captionTracks.find(t => isEn(t) && t.kind !== 'asr')
                     || captionTracks.find(t => isEn(t));
        dlog('[EH] enTrack:', enTrack?.languageCode, enTrack?.baseUrl?.slice(0, 60) || 'NONE');

        // YouTube 내부 XHR 유발 → pot 수집 (LR 방식)
        if (enTrack) triggerYouTubeCaptionLoad(player, enTrack);

        // videoId 추출
        const videoId = new URLSearchParams(location.search).get('v') || '';
        dlog('[EH] waiting for pot, videoId=', videoId);
        const pot = videoId ? await waitForPot(videoId) : null;
        dlog('[EH] pot=', pot ? pot.slice(0, 20) + '...' : null);

        // baseUrl 결정: enTrack과 같은 언어의 캡처된 URL 우선, 없으면 track.baseUrl.
        // 캡처된 값은 이미 _looksLikeRealTimedtextParams를 통과한 것만 캐싱되지만,
        // enTrack.baseUrl(getPlayerResponse() 직접 읽기)은 그 검증을 거치지 않았으므로
        // 여기서 별도로 검증한다 — LR 등 다른 확장이 player 응답 객체 자체를 패치해
        // 두면 이 경로도 오염된 값을 돌려줄 수 있다.
        const timedtextKey = videoId + ':' + (enTrack?.languageCode || '');
        const capturedBase = _timedtextBase[timedtextKey] || null;
        const fallbackBase = _baseUrlLooksReal(enTrack?.baseUrl) ? enTrack.baseUrl : null;
        const resolvedBase = capturedBase || fallbackBase || null;
        dlog('[EH] resolvedBase:', resolvedBase?.slice(0, 80) || 'NULL');

        // 트랙은 있는데(captionTracks.length > 0) 쓸 수 있는 URL이 하나도 없다면,
        // 자막이 정말 없는 게 아니라 다른 확장(예: Language Reactor)이 페이지의
        // 자막 데이터 경로를 오염시켰을 가능성이 높다 — 침묵하는 대신 명확히 알린다.
        const conflictSuspected = !resolvedBase && !!enTrack?.baseUrl;

        const [enXml, nativeXml] = resolvedBase
          ? await Promise.all([
              fetchCaptionXml(resolvedBase, pot, null),
              fetchCaptionXml(resolvedBase, pot, nativeLang)
            ])
          : [null, null];

        dlog('[EH] enXml len=', enXml?.length, 'nativeXml len=', nativeXml?.length);
        window.postMessage({
          type: 'EH_CAPTIONS_LOADED',
          videoId,
          enXml: enXml || '',
          nativeXml: nativeXml || '',
          nativeLang,
          conflictSuspected
        }, '*');
      } catch (err) { console.error('[EH] TRIGGER error', err); }
    }
  });
})();
