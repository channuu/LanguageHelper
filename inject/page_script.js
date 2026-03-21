// ================================================================
// inject/page_script.js — 페이지 컨텍스트에서 실행 (document_start)
// XHR을 가로채서 timedtext 요청을 srv3(XML)으로 교체 후 캡처
// ================================================================
(function() {
  let capturedText = null;

  // ── XHR 인터셉터 — 페이지 로드 전에 설치 ───────────────────────
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this._ehUrl = url?.toString() || "";

    // timedtext 요청을 srv3(XML) 포맷으로 교체
    if (this._ehUrl.includes("timedtext")) {
      const newUrl = this._ehUrl.replace(/&fmt=[^&]*/g, "") + "&fmt=srv3";
      this._ehUrl = newUrl;
      return origOpen.call(this, method, newUrl, ...rest);
    }
    return origOpen.call(this, method, url, ...rest);
  };

  XMLHttpRequest.prototype.send = function(...args) {
    if (this._ehUrl.includes("timedtext")) {
      this.addEventListener("load", function() {
        const text = this.responseText;
        if (text && text.length > 10) {
          capturedText = text;
          window.postMessage({ type: "EH_CAPTIONS_CAPTURED", text }, "*");
        }
      });
    }
    return origSend.call(this, ...args);
  };

  // ── content script 메시지 수신 ───────────────────────────────────
  window.addEventListener("message", (e) => {
    if (e.source !== window) return;

    // 이미 캡처된 자막 요청
    if (e.data?.type === "EH_GET_CAPTURED_CAPTIONS") {
      window.postMessage({
        type: "EH_CAPTURED_CAPTIONS_RESULT",
        text: capturedText
      }, "*");
    }

    // 자막 강제 로드 트리거 (capturedText가 없을 때)
    if (e.data?.type === "EH_TRIGGER_CAPTION_LOAD") {
      try {
        const player = document.querySelector("#movie_player");
        const tracks = player?.getPlayerResponse()
          ?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
        if (!tracks?.length) return;

        const track =
          tracks.find(t => t.languageCode === "en" && t.kind !== "asr") ||
          tracks.find(t => t.languageCode === "en") ||
          tracks[0];

        if (track?.baseUrl) {
          // XHR 인터셉터가 자동으로 srv3으로 교체해서 캡처함
          const xhr = new XMLHttpRequest();
          xhr.open("GET", track.baseUrl);
          xhr.send();
        }
      } catch(e) {}
    }
  });
})();
