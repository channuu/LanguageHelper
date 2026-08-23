// ================================================================
// inject/page_script.js — MAIN world 콘텐츠 스크립트 (document_start)
// YouTube 플레이어 응답 인터셉트 + 자막 XML fetch
// ================================================================
(function() {

  const DEBUG = false;
  const dlog = DEBUG ? console.log.bind(console) : () => {};

  // videoId별 player 응답 트랙 캐시 + pot 캐시.
  // 예전엔 "가장 최근 응답 하나"만 저장했는데, 유튜브가 사이드바 추천/자동재생
  // 다음 영상의 썸네일을 미리 로드하면서 그 영상의 /youtubei/v1/player도 같이
  // fetch되는 경우가 있다 — 그러면 이 캐시가 현재 보고 있는 영상이 아니라
  // 엉뚱한(미리보기용) 영상의 캡션 트랙으로 덮어써져서, 존재하지도 않는 자막을
  // "충돌"로 오인하게 만드는 원인이 됐다. videoId로 스코프를 나눠 이 누수를 막는다.
  let _cachedTracksByVideo = {};
  let _potCache = {};         // {videoId: pot}
  let _timedtextBase = {};    // {"videoId:langCode": clean baseUrl (no pot/fmt/tlang)}
  // "충돌 의심" 문구는 실제로 변조된 URL을 목격했을 때만 띄워야 한다 — 단순히
  // pot을 제때 못 받았거나 baseUrl을 못 구한 경우(다른 확장 없이도 벌어짐)까지
  // 전부 "다른 확장과 충돌"로 오인 안내하면 사용자가 엉뚱한 곳(LR)을 의심하게 된다.
  let _sawMutatedTimedtextUrl = false;

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
    if (lang && !/^[a-zA-Z]{1,3}(\.[a-zA-Z]{1,3})?(-[A-Za-z0-9]+)?$/.test(lang)) {
      dlog('[EH] reject reason: lang format', JSON.stringify(lang));
      return false;
    }
    // signature가 ip와 완전히 같은 값이면 정상적인 서명이 아니다 — 다른
    // 확장이 익명화용으로 같은 자리표시자를 여러 필드에 채워 넣은 흔적.
    if (sig && ip && sig === ip) {
      dlog('[EH] reject reason: signature === ip', sig.length, ip.length);
      return false;
    }
    return true;
  }

  // ── timedtext URL에서 pot + base URL 추출 (XHR + fetch 공통 헬퍼) ──
  function _extractPotFromUrl(url) {
    if (typeof url !== 'string') return;
    if (!url.includes('timedtext')) return;
    try {
      const [path, qs] = url.split('?');
      const params = new URLSearchParams(qs || '');
      const videoId = params.get('v');
      if (!_looksLikeRealTimedtextParams(params)) {
        dlog('[EH] ignoring timedtext URL — looks mutated by another extension');
        // 사이드바 추천/미리보기 등 "지금 보고 있지 않은 다른 영상"에 대한
        // 요청이 이 휴리스틱에 우연히 걸리는 경우까지 현재 영상의 충돌 근거로
        // 채택하면 안 된다 — 반드시 현재 재생 중인 videoId와 일치할 때만 채택.
        const currentVideoId = new URLSearchParams(location.search).get('v') || '';
        if (videoId && videoId === currentVideoId) _sawMutatedTimedtextUrl = true;
        return;
      }
      const pot = params.get('pot');
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
        const respVideoId = data?.videoDetails?.videoId;
        if (tracks?.length && respVideoId) {
          _cachedTracksByVideo[respVideoId] = tracks;
          dlog('[EH] player response intercepted for', respVideoId, 'tracks:', tracks.length);
        }
      }).catch(() => {});
    }
    return res;
  };

  // ── pot 대기 (최대 5초 — 백그라운드 탭 타이머 스로틀링 등으로 3초로는
  //    간헐적으로 타임아웃되는 경우가 있어 LR의 3초보다 여유를 뒀다) ───
  async function waitForPot(videoId) {
    for (let i = 0; i < 10; i++) {
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

        // videoId를 먼저 구해서, 캐시된 트랙도 반드시 "현재 보고 있는 영상"
        // 것만 쓴다 — 사이드바 미리보기 등으로 캐시된 다른 영상의 트랙이
        // 섞여 들어오지 않게 한다.
        const videoId = new URLSearchParams(location.search).get('v') || '';

        // 캐시된 트랙(현재 영상 한정) 우선, 없으면 getPlayerResponse() fallback
        let captionTracks = _cachedTracksByVideo[videoId];
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
        const rawBaseLooksReal = _baseUrlLooksReal(enTrack?.baseUrl);
        if (enTrack?.baseUrl && !rawBaseLooksReal) _sawMutatedTimedtextUrl = true;
        const fallbackBase = rawBaseLooksReal ? enTrack.baseUrl : null;
        const resolvedBase = capturedBase || fallbackBase || null;
        dlog('[EH] resolvedBase:', resolvedBase?.slice(0, 80) || 'NULL');

        // 실제로 변조된(다른 확장이 손댄) URL을 목격한 경우에만 "충돌 의심"으로
        // 안내한다. 트랙은 있는데 pot 타임아웃 등 다른 이유로 URL을 못 구한
        // 경우는 별개의 "일시적 실패"로 구분해 엉뚱하게 LR을 의심하지 않게 한다.
        const conflictSuspected = !resolvedBase && _sawMutatedTimedtextUrl;
        const loadFailed = !resolvedBase && !conflictSuspected && !!enTrack;

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
          conflictSuspected,
          loadFailed: loadFailed || (!!enTrack && !enXml)
        }, '*');
      } catch (err) { console.error('[EH] TRIGGER error', err); }
    }
  });
})();
