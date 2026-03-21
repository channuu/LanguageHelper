// ================================================================
// content/netflix.js
// Netflix 자막 추출 + 오버레이 표시 + 문장 저장
// ================================================================

(function () {
  "use strict";

  let overlayVisible = true;
  let lastEnglishText = "";
  let observer = null;

  // ── DOM 생성 (youtube.js와 동일한 구조) ──────────────────────────
  function createOverlay() {
    if (document.getElementById("eh-subtitle-overlay")) return;

    const overlay = document.createElement("div");
    overlay.id = "eh-subtitle-overlay";
    // Netflix 플레이어 위치에 맞춰 조정
    overlay.style.bottom = "100px";
    document.body.appendChild(overlay);

    const toast = document.createElement("div");
    toast.id = "eh-toast";
    document.body.appendChild(toast);
  }

  function updateOverlay(englishText) {
    const overlay = document.getElementById("eh-subtitle-overlay");
    if (!overlay || !overlayVisible) return;
    if (englishText === lastEnglishText) return;
    lastEnglishText = englishText;
    overlay.innerHTML = "";
    if (!englishText) return;

    const enLine = document.createElement("div");
    enLine.className = "eh-line-en";
    enLine.style.position = "relative";
    enLine.style.display = "inline-block";

    englishText.split(" ").forEach((word, i, arr) => {
      const span = document.createElement("span");
      span.className = "eh-word";
      span.textContent = word + (i < arr.length - 1 ? " " : "");
      enLine.appendChild(span);
    });

    const saveBtn = document.createElement("button");
    saveBtn.className = "eh-save-btn";
    saveBtn.textContent = "＋";
    saveBtn.title = "이 문장 저장";
    saveBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      saveSentence(englishText);
    });
    enLine.appendChild(saveBtn);
    overlay.appendChild(enLine);
  }

  // ── Netflix 자막 선택자 ──────────────────────────────────────────
  // Netflix는 자막 구조를 자주 변경하므로 여러 선택자를 시도
  const NETFLIX_SELECTORS = [
    ".player-timedtext-text-container span",     // 기본
    ".NFPlayer .nf-subtitle-container span",     // 일부 버전
    "[data-uia='player-timedtext'] span",        // data-uia 기반
    ".subtitle-container span"                   // 폴백
  ];

  function getNetflixCaptionText() {
    for (const selector of NETFLIX_SELECTORS) {
      const elements = document.querySelectorAll(selector);
      if (elements.length > 0) {
        return Array.from(elements)
          .map(el => el.textContent.trim())
          .filter(Boolean)
          .join(" ");
      }
    }
    return "";
  }

  function getShowTitle() {
    return document.querySelector(".video-title")?.textContent?.trim()
      || document.querySelector("[data-uia='video-title']")?.textContent?.trim()
      || document.title.replace(" | Netflix", "");
  }

  // ── Observer ─────────────────────────────────────────────────────
  function startObserving() {
    if (observer) observer.disconnect();

    observer = new MutationObserver(() => {
      const text = getNetflixCaptionText();
      updateOverlay(text);
    });

    // Netflix 플레이어 컨테이너 감시
    const playerRoot = document.querySelector(".NFPlayer") || document.body;
    observer.observe(playerRoot, {
      childList: true,
      subtree: true,
      characterData: true
    });
  }

  async function saveSentence(english) {
    const response = await chrome.runtime.sendMessage({
      type: "SAVE_SENTENCE",
      payload: {
        sentence: {
          english,
          korean: "",
          source: "netflix",
          sourceUrl: window.location.href,
          videoTitle: getShowTitle()
        }
      }
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

  // Netflix는 SPA이므로 URL 변화 감지
  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      lastEnglishText = "";
      setTimeout(() => {
        createOverlay();
        startObserving();
      }, 2000);
    }
  }).observe(document, { subtree: true, childList: true });

  function init() {
    createOverlay();
    startObserving();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
