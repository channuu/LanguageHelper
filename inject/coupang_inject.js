// ================================================================
// inject/coupang_inject.js — MAIN world 콘텐츠 스크립트 (document_start)
// 쿠팡플레이 /playback/play 응답에서 모든 언어의 WebVTT 자막 URL 캡처
// ================================================================
(function () {

  const DEBUG = false;
  const dlog = DEBUG ? console.log.bind(console) : () => {};

  const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

  // {videoId: [{code, description, url}]}
  let _tracksByVideoId = {};

  function _currentVideoId() {
    const m = location.href.match(UUID_RE);
    return m ? m[0] : null;
  }

  // ── fetch 인터셉터 — /playback/play 응답에서 자막 트랙 목록 추출 ──────
  // 쿠팡플레이는 이 응답 하나에 모든 언어의 WebVTT URL을 이미 포함해서
  // 내려준다 — YouTube의 pot 토큰이나 Netflix의 강제 언어 요청 트릭이 필요 없다.
  const _origFetch = window.fetch;
  window.fetch = async function (...args) {
    const res = await _origFetch.apply(this, args);
    const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
    if (!url.includes('/playback/play')) return res;

    try {
      const clone = res.clone();
      clone.json().then(data => {
        const textTracks = data?.data?.raw?.text_tracks;
        if (!textTracks?.length) return;

        const tracks = [];
        for (const t of textTracks) {
          if (t.kind !== 'subtitles' || t.mime_type !== 'text/webvtt') continue;
          const source = Object.values(t.sources || {}).find(s => s?.src?.includes('https'));
          if (!source) continue;
          tracks.push({ code: t.srclang, description: t.label, url: source.src });
        }
        if (!tracks.length) return;

        const videoId = _currentVideoId();
        if (!videoId) return;
        _tracksByVideoId[videoId] = tracks;
        dlog('[EH:cp] tracks captured for video', videoId, tracks.length);
      }).catch(() => {});
    } catch (e) {}

    return res;
  };

  function _pickTrackUrl(tracks, lang) {
    if (!lang) return null;
    const track = tracks.find(t => t.code === lang)
               || tracks.find(t => t.code?.startsWith(lang.split('-')[0]));
    return track?.url || null;
  }

  // ── content script 메시지 수신 ───────────────────────────────────
  window.addEventListener('message', async (e) => {
    if (e.source !== window) return;
    if (e.data?.type !== 'EH_CP_TRIGGER_LOAD') return;

    try {
      const { videoId, nativeLang } = e.data;
      const tracks = _tracksByVideoId[videoId];
      if (!tracks?.length) {
        dlog('[EH:cp] no tracks cached yet for video', videoId);
        return;
      }

      const enUrl = _pickTrackUrl(tracks, 'en');
      const nativeUrl = _pickTrackUrl(tracks, nativeLang);
      dlog('[EH:cp] enUrl:', !!enUrl, 'nativeUrl:', !!nativeUrl);

      const [enVtt, nativeVtt] = await Promise.all([
        enUrl ? fetch(enUrl).then(r => r.text()).catch(() => '') : Promise.resolve(''),
        nativeUrl ? fetch(nativeUrl).then(r => r.text()).catch(() => '') : Promise.resolve('')
      ]);

      dlog('[EH:cp] enVtt len=', enVtt.length, 'nativeVtt len=', nativeVtt.length);
      window.postMessage({
        type: 'EH_CP_CAPTIONS_LOADED',
        videoId,
        enVtt,
        nativeVtt,
        nativeLang
      }, '*');
    } catch (err) {
      console.error('[EH:cp] TRIGGER error', err);
    }
  });
})();
