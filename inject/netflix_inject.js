// ================================================================
// inject/netflix_inject.js — MAIN world 콘텐츠 스크립트 (document_start)
// Netflix 자막 매니페스트 요청/응답 가로채기 — 모든 언어 트랙의 WebVTT URL 확보
// ================================================================
(function () {

  const DEBUG = false;
  const dlog = DEBUG ? console.log.bind(console) : () => {};

  const WEBVTT = 'webvtt-lssdh-ios8';
  const MANIFEST_PATTERN = /manifest|licensedManifest/;

  // {movieId: [{language, rawTrackType, isNoneTrack, isForcedNarrative, ttDownloadables}]}
  let _tracksByMovieId = {};

  // ── 매니페스트 요청 바디에 강제 옵션 주입 — 선택된 언어뿐 아니라
  //    모든 언어의 자막 다운로드 URL을 서버가 내려주도록 요청한다 ──────
  const _origStringify = JSON.stringify;
  JSON.stringify = function (data, replacer, space) {
    if (data && typeof data.url === 'string' && MANIFEST_PATTERN.test(data.url)) {
      try {
        for (const v of Object.values(data)) {
          if (v && typeof v === 'object') {
            if (Array.isArray(v.profiles) && !v.profiles.includes(WEBVTT)) {
              v.profiles.unshift(WEBVTT);
            }
            if (v.showAllSubDubTracks != null) v.showAllSubDubTracks = true;
          }
        }
      } catch (e) {}
    }
    return _origStringify(data, replacer, space);
  };

  // ── 매니페스트 응답에서 트랙 목록 캡처 ────────────────────────────
  const _origParse = JSON.parse;
  JSON.parse = function (text, reviver) {
    const data = _origParse(text, reviver);
    try {
      const result = data?.result;
      const tracks = result?.timedtexttracks || result?.textTracks;
      if (tracks?.length && result?.movieId != null) {
        _tracksByMovieId[result.movieId] = tracks;
        dlog('[EH:nf] tracks captured for movie', result.movieId, tracks.length);
      }
    } catch (e) {}
    return data;
  };

  function _pickTrackUrl(tracks, lang) {
    const isMatch = t => !t.isNoneTrack && !t.isForcedNarrative && t.language === lang;
    const track = tracks.find(t => isMatch(t) && t.rawTrackType === 'subtitles')
               || tracks.find(t => isMatch(t));
    const downloadables = track?.ttDownloadables?.[WEBVTT] || track?.downloadables?.[WEBVTT];
    if (!downloadables) return null;
    const urls = downloadables.downloadUrls
      ? Object.values(downloadables.downloadUrls)
      : downloadables.urls?.map(u => u.url);
    return urls?.[0] || null;
  }

  // ── 시크(EH_NF_SEEK) — Netflix 자체 플레이어 API로 이동 ────────────
  // video.currentTime을 직접 바꾸면 Netflix의 DRM/스트리밍 상태 관리자가
  // 이를 인지하지 못해 재생을 멈춰버린다(재동기화 목적). 공식(비공개지만
  // 널리 쓰이는) 플레이어 API를 통해 이동해야 재생이 끊기지 않는다.
  function _netflixSeek(seconds) {
    try {
      const videoPlayer = window.netflix?.appContext?.state?.playerApp?.getAPI?.()?.videoPlayer;
      const sessionId = videoPlayer?.getAllPlayerSessionIds?.()[0];
      const player = sessionId ? videoPlayer.getVideoPlayerBySessionId(sessionId) : null;
      if (player && typeof player.seek === 'function') {
        player.seek(Math.round(seconds * 1000)); // Netflix API는 밀리초 단위
        return true;
      }
    } catch (e) {
      dlog('[EH:nf] seek via player API failed', e);
    }
    return false;
  }

  // ── content script 메시지 수신 ───────────────────────────────────
  window.addEventListener('message', async (e) => {
    if (e.source !== window) return;

    if (e.data?.type === 'EH_NF_SEEK') {
      const ok = _netflixSeek(e.data.seconds);
      if (!ok) {
        // 플레이어 API를 못 찾은 경우에만 폴백 — 일시정지 위험은 있지만
        // 아예 이동 못 하는 것보다는 낫다.
        const video = document.querySelector('video');
        if (video) video.currentTime = e.data.seconds;
      }
      return;
    }

    if (e.data?.type !== 'EH_NF_TRIGGER_LOAD') return;

    try {
      const { movieId, nativeLang } = e.data;
      const tracks = _tracksByMovieId[movieId];
      if (!tracks?.length) {
        dlog('[EH:nf] no tracks cached yet for movie', movieId);
        return;
      }

      const enUrl = _pickTrackUrl(tracks, 'en');
      const nativeUrl = _pickTrackUrl(tracks, nativeLang);
      dlog('[EH:nf] enUrl:', !!enUrl, 'nativeUrl:', !!nativeUrl);

      const [enVtt, nativeVtt] = await Promise.all([
        enUrl ? fetch(enUrl).then(r => r.text()).catch(() => '') : Promise.resolve(''),
        nativeUrl ? fetch(nativeUrl).then(r => r.text()).catch(() => '') : Promise.resolve('')
      ]);

      dlog('[EH:nf] enVtt len=', enVtt.length, 'nativeVtt len=', nativeVtt.length);
      window.postMessage({
        type: 'EH_NF_CAPTIONS_LOADED',
        movieId,
        enVtt,
        nativeVtt,
        nativeLang
      }, '*');
    } catch (err) {
      console.error('[EH:nf] TRIGGER error', err);
    }
  });
})();
