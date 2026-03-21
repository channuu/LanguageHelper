// ================================================================
// content/youtube.js
// ================================================================

(function () {
  "use strict";

  let overlayVisible = true;
  let lastEnglishText = "";
  let observer = null;
  let floatBtn = null; // 떠다니는 저장 버튼 (body에 단 하나)

  function createOverlay() {
    if (document.getElementById("eh-subtitle-overlay")) return;
    const overlay = document.createElement("div");
    overlay.id = "eh-subtitle-overlay";
    document.body.appendChild(overlay);

    const toast = document.createElement("div");
    toast.id = "eh-toast";
    document.body.appendChild(toast);

    // 저장 버튼을 body에 하나만 만들어 재사용
    floatBtn = document.createElement("button");
    floatBtn.textContent = "＋";
    floatBtn.title = "이 문장 저장";
    floatBtn.style.cssText = [
      "position:fixed",
      "width:30px","height:30px",
      "background:rgba(255,217,122,0.92)",
      "border:none","border-radius:50%",
      "cursor:pointer","font-size:17px","font-weight:700","color:#1a1500",
      "display:flex","align-items:center","justify-content:center",
      "opacity:0","pointer-events:none",
      "transition:opacity 0.15s,transform 0.15s,background 0.15s",
      "z-index:10000001",
      "transform:scale(0.85)",
      "line-height:1"
    ].join(";");
    document.body.appendChild(floatBtn);

    floatBtn.addEventListener("mouseenter", () => {
      floatBtn.style.background = "#ffc107";
      floatBtn.style.transform = "scale(1.12)";
    });
    floatBtn.addEventListener("mouseleave", () => {
      floatBtn.style.background = "rgba(255,217,122,0.92)";
      floatBtn.style.opacity = "0";
      floatBtn.style.pointerEvents = "none";
      floatBtn.style.transform = "scale(0.85)";
    });
  }

  function updateOverlay(englishText, koreanText = "") {
    const overlay = document.getElementById("eh-subtitle-overlay");
    if (!overlay || !overlayVisible) return;
    if (englishText === lastEnglishText) return;
    lastEnglishText = englishText;
    overlay.innerHTML = "";

    if (!englishText) return;

    const enLine = document.createElement("div");
    enLine.className = "eh-line-en";
    enLine.style.display = "inline-block";

    englishText.split(" ").forEach((word, i, arr) => {
      const span = document.createElement("span");
      span.className = "eh-word";
      span.textContent = word + (i < arr.length - 1 ? " " : "");
      enLine.appendChild(span);
    });
    overlay.appendChild(enLine);

    if (koreanText) {
      const koLine = document.createElement("div");
      koLine.className = "eh-line-ko";
      koLine.textContent = koreanText;
      overlay.appendChild(koLine);
    }

    // 자막 위에 마우스 올리면 버튼 위치 잡고 표시
    enLine.addEventListener("mouseenter", () => {
      if (!floatBtn) return;
      const r = enLine.getBoundingClientRect();
      floatBtn.style.left  = (r.right + 10) + "px";
      floatBtn.style.top   = (r.top + r.height / 2 - 15) + "px";
      floatBtn.style.opacity = "1";
      floatBtn.style.pointerEvents = "all";
      floatBtn.style.transform = "scale(1)";
      // 클릭 핸들러 교체
      floatBtn.onclick = (e) => {
        e.stopPropagation();
        saveSentence(englishText, koreanText);
      };
    });
    enLine.addEventListener("mouseleave", (e) => {
      if (!floatBtn) return;
      if (e.relatedTarget === floatBtn) return; // 버튼으로 이동 중이면 유지
      floatBtn.style.opacity = "0";
      floatBtn.style.pointerEvents = "none";
      floatBtn.style.transform = "scale(0.85)";
    });
  }

  const YT_CAPTION_SELECTORS = [
    ".ytp-caption-segment",
    ".captions-text .caption-visual-line span",
    "[class*='caption-window'] span"
  ];

  function getYouTubeCaptionText() {
    for (const selector of YT_CAPTION_SELECTORS) {
      const elements = document.querySelectorAll(selector);
      if (elements.length > 0) {
        return Array.from(elements).map(el => el.textContent.trim()).filter(Boolean).join(" ");
      }
    }
    return "";
  }

  function getVideoTitle() {
    return document.querySelector("h1.ytd-watch-metadata yt-formatted-string")?.textContent?.trim()
      || document.querySelector("#title h1")?.textContent?.trim()
      || document.title.replace(" - YouTube", "");
  }

  function startObserving() {
    if (observer) observer.disconnect();
    observer = new MutationObserver(() => {
      const text = getYouTubeCaptionText();
      updateOverlay(text);
    });
    const targetNode = document.querySelector(".html5-video-player") || document.body;
    observer.observe(targetNode, { childList: true, subtree: true, characterData: true });
  }

  async function saveSentence(english, korean) {
    const response = await chrome.runtime.sendMessage({
      type: "SAVE_SENTENCE",
      payload: { sentence: { english, korean, source: "youtube", sourceUrl: window.location.href, videoTitle: getVideoTitle() } }
    });
    showToast(response.success ? "✓ 문장이 저장되었습니다" : `저장 실패: ${response.error}`);
  }

  function showToast(message) {
    const toast = document.getElementById("eh-toast");
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add("show");
    setTimeout(() => toast.classList.remove("show"), 2500);
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "TOGGLE_OVERLAY") {
      overlayVisible = !overlayVisible;
      const overlay = document.getElementById("eh-subtitle-overlay");
      if (overlay) overlay.classList.toggle("hidden", !overlayVisible);
    }
  });

  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      lastEnglishText = "";
      setTimeout(() => { createOverlay(); startObserving(); }, 1500);
    }
  }).observe(document, { subtree: true, childList: true });

  function init() { createOverlay(); startObserving(); }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
