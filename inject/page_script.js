// ================================================================
// inject/page_script.js — 페이지 컨텍스트에서 실행
// YouTube 플레이어 응답 인터셉트 + 자막 XML을 page context에서 직접 fetch
// ================================================================
(function() {

  // ── fetch 인터셉터 — /youtubei/v1/player 응답에서 트랙 목록 추출 ──
  const _origFetch = window.fetch;
  window.fetch = async function(...args) {
    const res = await _origFetch.apply(this, args);
    const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
    if (url.includes('/youtubei/v1/player')) {
      const clone = res.clone();
      clone.json().then(extractTracks).catch(() => {});
    }
    return res;
  };

  function extractTracks(playerResponse) {
    try {
      const captions = playerResponse?.captions?.playerCaptionsTracklistRenderer;
      if (!captions?.captionTracks) return;
      const tracks = captions.captionTracks.map(t => ({
        langCode: t.languageCode,
        baseUrl: t.baseUrl
      }));
      window.postMessage({ type: 'EH_TRACKS_AVAILABLE', tracks }, '*');
    } catch (e) {}
  }

  // ── 자막 XML을 page context에서 직접 fetch ───────────────────────
  async function fetchCaptionXml(baseUrl) {
    if (!baseUrl) return null;
    try {
      const url = baseUrl.replace(/&fmt=[^&]*/g, '') + '&fmt=srv3';
      const res = await _origFetch(url);
      const text = await res.text();
      return text && text.length > 10 ? text : null;
    } catch (e) {
      return null;
    }
  }

  // ── content script 메시지 수신 ───────────────────────────────────
  window.addEventListener("message", async (e) => {
    if (e.source !== window) return;

    // EH_TRIGGER_CAPTION_LOAD: 영어+모국어 자막을 page context에서 fetch
    if (e.data?.type === "EH_TRIGGER_CAPTION_LOAD") {
      try {
        const nativeLang = e.data.nativeLang || 'ko';
        const player = document.querySelector("#movie_player");
        const captionTracks = player?.getPlayerResponse()
          ?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
        if (!captionTracks?.length) return;

        const enTrack = captionTracks.find(t => t.languageCode === 'en' && t.kind !== 'asr')
                     || captionTracks.find(t => t.languageCode === 'en');
        const nativeTrack = captionTracks.find(t => t.languageCode === nativeLang);

        const [enXml, nativeXml] = await Promise.all([
          fetchCaptionXml(enTrack?.baseUrl),
          fetchCaptionXml(nativeTrack?.baseUrl)
        ]);

        window.postMessage({
          type: 'EH_CAPTIONS_LOADED',
          enXml,
          nativeXml,
          nativeLang
        }, '*');
      } catch (e) {}
    }
  });
})();
