// ================================================================
// content/youtube_inject.js — document_start에 실행
// page_script.js를 페이지 컨텍스트에 최대한 빨리 주입
// XHR 인터셉터가 YouTube 플레이어보다 먼저 설치돼야 함
// ================================================================
(function() {
  const s = document.createElement("script");
  s.id  = "eh-page-script";
  s.src = chrome.runtime.getURL("inject/page_script.js");
  (document.head || document.documentElement).appendChild(s);
})();
