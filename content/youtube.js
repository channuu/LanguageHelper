// ================================================================
// content/youtube.js
// ================================================================
(function () {
  "use strict";

  let overlayVisible = true;
  let captions = [];
  let translations = []; // 한글 번역 캐시 (captions와 동일 인덱스)
  let rafId = null;
  let lastShownText = "";
  let currentVideoId = "";
  let lastHighlightIdx = -1;

  // overlay 구조:
  //   #eh-subtitle-overlay
  //     ├── #eh-text-line   ← 자막 텍스트만 교체 (innerHTML)
  //     └── #eh-resize-handle ← 항상 유지

  // ── page_script로부터 자막 수신 ─────────────────────────────────
  window.addEventListener("message", (e) => {
    if (e.source !== window) return;
    if (e.data?.type === "EH_CAPTIONS_CAPTURED" ||
        e.data?.type === "EH_CAPTURED_CAPTIONS_RESULT") {
      if (!e.data.text) return;
      const parsed = parseXml(e.data.text);
      if (parsed.length > 0) {
        captions = mergeCaptions(parsed);
        translations = new Array(captions.length).fill("");
        console.log("[EnglishHelper] ✓ " + captions.length + "개 문장 로드 완료");
        renderTimeline();
        translateAll();
      }
    }
  });

  // ── XML 파서 ─────────────────────────────────────────────────────
  function parseXml(xmlText) {
    try {
      const doc = new DOMParser().parseFromString(xmlText, "text/xml");
      const items = [];
      for (const el of doc.querySelectorAll("p")) {
        const start = parseFloat(el.getAttribute("t") || "0") / 1000;
        const dur   = parseFloat(el.getAttribute("d") || "3000") / 1000;
        const text  = decodeEntities(el.textContent || "").replace(/\n/g, " ").trim();
        if (text) items.push({ start, dur, text });
      }
      if (!items.length) {
        for (const el of doc.querySelectorAll("text")) {
          const start = parseFloat(el.getAttribute("start") || "0");
          const dur   = parseFloat(el.getAttribute("dur") || "3");
          const text  = decodeEntities(el.textContent || "").replace(/\n/g, " ").trim();
          if (text) items.push({ start, dur, text });
        }
      }
      return items;
    } catch(e) { return []; }
  }

  function decodeEntities(str) {
    const el = document.createElement("textarea");
    el.innerHTML = str;
    return el.value;
  }

  function mergeCaptions(items) {
    if (!items.length) return [];
    const merged = [{ ...items[0] }];
    for (let i = 1; i < items.length; i++) {
      const prev = merged[merged.length - 1];
      const cur  = items[i];
      const gap  = cur.start - (prev.start + prev.dur);
      if (gap < 1.2 && (prev.text + cur.text).length < 130) {
        prev.text += " " + cur.text;
        prev.dur   = (cur.start + cur.dur) - prev.start;
      } else {
        merged.push({ ...cur });
      }
    }
    return merged;
  }

  function getCaptionAtTime(t) {
    let lo = 0, hi = captions.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const c = captions[mid];
      if (t < c.start)              hi = mid - 1;
      else if (t > c.start + c.dur) lo = mid + 1;
      else return c;
    }
    return null;
  }

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ":" + s.toString().padStart(2, "0");
  }

  // ── 전체 자막 배치 번역 ──────────────────────────────────────────
  async function translateAll() {
    if (!captions.length) return;
    const texts = captions.map(c => c.text);
    console.log("[EnglishHelper] 번역 시작... " + texts.length + "개 문장");

    const res = await chrome.runtime.sendMessage({
      type: "TRANSLATE_BATCH",
      payload: { texts }
    });

    if (res.success) {
      translations = res.results;
      console.log("[EnglishHelper] ✓ 번역 완료");
      // 현재 표시 중인 자막 즉시 업데이트
      lastShownText = "";
      renderTimeline();
    }
  }

  // ── DOM 생성 ─────────────────────────────────────────────────────
  function createOverlay() {
    if (document.getElementById("eh-subtitle-overlay")) return;

    const overlay = document.createElement("div");
    overlay.id = "eh-subtitle-overlay";

    // 텍스트 줄 — 이것만 갱신됨
    const textLine = document.createElement("div");
    textLine.id = "eh-text-line";
    textLine.className = "eh-line-en";
    overlay.appendChild(textLine);

    // 리사이즈 핸들 — overlay 안에 고정
    const handle = document.createElement("div");
    handle.id = "eh-resize-handle";
    overlay.appendChild(handle);

    document.body.appendChild(overlay);

    const toast = document.createElement("div");
    toast.id = "eh-toast";
    document.body.appendChild(toast);

    // 저장된 상태 복원
    const saved = JSON.parse(localStorage.getItem("eh-overlay-pos") || "null");
    if (saved?.left && saved?.top) {
      overlay.style.left      = saved.left;
      overlay.style.top       = saved.top;
      overlay.style.bottom    = "auto";
      overlay.style.transform = "none";
    }
    if (saved?.fontSize) textLine.style.fontSize = saved.fontSize;

    attachDrag(overlay, textLine);
    attachResize(overlay, textLine, handle);
  }

  // ── 드래그 ───────────────────────────────────────────────────────
  function attachDrag(overlay, textLine) {
    let dragging = false, sx, sy, ox, oy;

    overlay.addEventListener("mousedown", (e) => {
      if (e.target.id === "eh-resize-handle") return;
      if (e.target.classList.contains("eh-word")) return;
      dragging = true;
      overlay.classList.add("dragging");
      const r = overlay.getBoundingClientRect();
      sx = e.clientX; sy = e.clientY;
      ox = r.left;    oy = r.top;
      e.preventDefault();
    });

    document.addEventListener("mousemove", (e) => {
      if (!dragging) return;
      overlay.style.left      = (ox + e.clientX - sx) + "px";
      overlay.style.top       = (oy + e.clientY - sy) + "px";
      overlay.style.bottom    = "auto";
      overlay.style.transform = "none";
    });

    document.addEventListener("mouseup", () => {
      if (!dragging) return;
      dragging = false;
      overlay.classList.remove("dragging");
      saveState(overlay, textLine);
    });
  }

  // ── 리사이즈 ─────────────────────────────────────────────────────
  function attachResize(overlay, textLine, handle) {
    let resizing = false, startX, startSize;
    const MIN = 12, MAX = 52;

    handle.addEventListener("mousedown", (e) => {
      e.stopPropagation();
      e.preventDefault();
      resizing  = true;
      startX    = e.clientX;
      startSize = parseFloat(textLine.style.fontSize) ||
                  parseFloat(getComputedStyle(textLine).fontSize) || 22;
      document.body.style.cursor = "ew-resize";
    });

    document.addEventListener("mousemove", (e) => {
      if (!resizing) return;
      const newSize = Math.min(MAX, Math.max(MIN, startSize + (e.clientX - startX) * 0.35));
      textLine.style.fontSize = newSize + "px";
    });

    document.addEventListener("mouseup", () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = "";
      saveState(overlay, textLine);
    });
  }

  function saveState(overlay, textLine) {
    localStorage.setItem("eh-overlay-pos", JSON.stringify({
      left:     overlay.style.left,
      top:      overlay.style.top,
      fontSize: textLine.style.fontSize
    }));
  }

  // ── 오버레이 업데이트 — textLine.innerHTML만 교체 ───────────────
  function updateOverlay(text) {
    const overlay  = document.getElementById("eh-subtitle-overlay");
    const textLine = document.getElementById("eh-text-line");
    if (!textLine || !overlayVisible) return;
    if (text === lastShownText) return;
    lastShownText = text;
    textLine.innerHTML = "";

    // 한글 줄 제거
    document.getElementById("eh-ko-line")?.remove();
    if (!text) return;

    text.split(" ").forEach((word, i, arr) => {
      const span = document.createElement("span");
      span.className = "eh-word";
      span.textContent = word + (i < arr.length - 1 ? " " : "");
      span.addEventListener("click", (e) => {
        e.stopPropagation();
        const clean = word.replace(/[^a-zA-Z']/g, "");
        if (clean) saveItem(clean, text);
      });
      textLine.appendChild(span);
    });

    textLine.addEventListener("mouseup", () => {
      const sel = window.getSelection()?.toString().trim();
      if (sel && sel.length > 2) saveItem(sel, text);
    }, { once: true });

    // 폰트 크기 적용
    textLine.style.fontSize = currentSettings.enSize + "px";

    // 한글 번역 줄 표시 (모드에 따라)
    if (currentSettings.mode !== "en") {
      const capIdx = captions.findIndex(c => c.text === text);
      const koText = capIdx >= 0 ? translations[capIdx] : "";
      if (koText) {
        const koLine = document.createElement("div");
        koLine.id = "eh-ko-line";
        koLine.className = "eh-line-ko";
        koLine.textContent = koText;
        koLine.style.fontSize = currentSettings.koSize + "px";
        const handle = document.getElementById("eh-resize-handle");
        overlay.insertBefore(koLine, handle);
      }
    }

    highlightTimeline();
  }

  // ── 타임라인 패널 ────────────────────────────────────────────────
  function createTimelinePanel() {
    if (document.getElementById("eh-timeline")) return;

    const panel = document.createElement("div");
    panel.id = "eh-timeline";

    // 좌측 리사이즈 핸들
    const resizeHandle = document.createElement("div");
    resizeHandle.id = "eh-tl-resize";
    panel.appendChild(resizeHandle);

    // 헤더
    const header = document.createElement("div");
    header.className = "eh-tl-header";
    header.innerHTML =
      '<span class="eh-tl-title">📋 자막 타임라인</span>' +
      '<button class="eh-tl-btn" id="eh-tl-hide" title="숨기기">−</button>' +
      '<button class="eh-tl-btn" id="eh-tl-toggle" title="접기/펼치기">✕</button>';
    panel.appendChild(header);

    // 목록
    const list = document.createElement("div");
    list.className = "eh-tl-list";
    list.id = "eh-tl-list";
    list.innerHTML = '<div class="eh-tl-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    document.body.appendChild(panel);

    // 저장된 너비 복원
    const savedW = localStorage.getItem("eh-tl-width");
    if (savedW) panel.style.width = savedW;

    // 접기/펼치기 토글
    document.getElementById("eh-tl-toggle").addEventListener("click", () => {
      const collapsed = panel.classList.toggle("collapsed");
      document.getElementById("eh-tl-toggle").textContent = collapsed ? "▶" : "✕";
      document.getElementById("eh-tl-hide").style.display = collapsed ? "none" : "flex";
    });

    // 숨기기 버튼 — 팝업 토글로 다시 표시 가능
    document.getElementById("eh-tl-hide").addEventListener("click", () => {
      panel.classList.add("hidden");
      showToast("타임라인 숨김 — 팝업에서 다시 켤 수 있어요");
    });

    // 좌측 드래그로 너비 조절
    attachTimelineResize(panel, resizeHandle);
  }

  function attachTimelineResize(panel, handle) {
    let resizing = false, startX, startW;

    handle.addEventListener("mousedown", (e) => {
      e.preventDefault();
      resizing = true;
      startX = e.clientX;
      startW = panel.getBoundingClientRect().width;
      document.body.style.cursor = "ew-resize";
    });

    document.addEventListener("mousemove", (e) => {
      if (!resizing) return;
      const newW = Math.min(520, Math.max(180, startW - (e.clientX - startX)));
      panel.style.width = newW + "px";
    });

    document.addEventListener("mouseup", () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = "";
      localStorage.setItem("eh-tl-width", panel.style.width);
    });
  }

  function renderTimeline() {
    const list = document.getElementById("eh-tl-list");
    if (!list) return;
    list.innerHTML = "";
    captions.forEach((cap, idx) => {
      const item = document.createElement("div");
      item.className = "eh-tl-item";
      item.dataset.idx = idx;
      const time = document.createElement("span");
      time.className = "eh-tl-time";
      time.textContent = formatTime(cap.start);
      const txtWrap = document.createElement("div");
      txtWrap.className = "eh-tl-textwrap";
      const enSpan = document.createElement("span");
      enSpan.className = "eh-tl-text";
      enSpan.textContent = cap.text;
      txtWrap.appendChild(enSpan);
      if (translations[idx]) {
        const koSpan = document.createElement("span");
        koSpan.className = "eh-tl-ko";
        koSpan.textContent = translations[idx];
        koSpan.style.display = currentSettings.mode === "en" ? "none" : "block";
        txtWrap.appendChild(koSpan);
      }
      item.appendChild(time);
      item.appendChild(txtWrap);
      item.addEventListener("click", () => {
        const video = document.querySelector("video");
        if (video) video.currentTime = cap.start + 0.1;
      });
      list.appendChild(item);
    });
  }

  function highlightTimeline() {
    const video = document.querySelector("video");
    if (!video || !captions.length) return;
    const cap = getCaptionAtTime(video.currentTime + 0.1);
    if (!cap) return;
    const idx = captions.indexOf(cap);
    if (idx === lastHighlightIdx) return;
    lastHighlightIdx = idx;
    document.querySelectorAll(".eh-tl-item").forEach(el => el.classList.remove("active"));
    const active = document.querySelector(".eh-tl-item[data-idx='" + idx + "']");
    if (active) {
      active.classList.add("active");
      active.scrollIntoView({ block: "nearest", behavior: "smooth" });
    }
  }

  // ── RAF 루프 ─────────────────────────────────────────────────────
  function startTimeTracking() {
    if (rafId) cancelAnimationFrame(rafId);
    function tick() {
      const video = document.querySelector("video");
      if (video && !video.paused && captions.length > 0) {
        const cap = getCaptionAtTime(video.currentTime + 0.1);
        updateOverlay(cap ? cap.text : "");
      }
      rafId = requestAnimationFrame(tick);
    }
    rafId = requestAnimationFrame(tick);
  }

  // ── 자막 초기화 ──────────────────────────────────────────────────
  async function initCaptions() {
    const videoId = new URLSearchParams(location.search).get("v") || "";
    if (!videoId || videoId === currentVideoId) return;
    currentVideoId = videoId;
    captions = [];
    lastShownText = "";
    lastHighlightIdx = -1;
    const list = document.getElementById("eh-tl-list");
    if (list) list.innerHTML = '<div class="eh-tl-empty">자막 로딩 중...</div>';

    await new Promise(r => setTimeout(r, 500));
    window.postMessage({ type: "EH_GET_CAPTURED_CAPTIONS" }, "*");
    await new Promise(r => setTimeout(r, 800));
    if (!captions.length) window.postMessage({ type: "EH_TRIGGER_CAPTION_LOAD" }, "*");
  }

  // ── 저장 ─────────────────────────────────────────────────────────
  async function saveItem(english, context) {
    const videoTitle =
      document.querySelector("h1.ytd-watch-metadata yt-formatted-string")?.textContent?.trim()
      || document.title.replace(" - YouTube", "");
    const res = await chrome.runtime.sendMessage({
      type: "SAVE_SENTENCE",
      payload: { sentence: { english, context, source: "youtube", sourceUrl: location.href, videoTitle } }
    });
    showToast(res.success ? ("✓ \"" + english.slice(0, 20) + "\" 저장됨") : ("저장 실패: " + res.error));
  }

  function showToast(msg) {
    const t = document.getElementById("eh-toast");
    if (!t) return;
    t.textContent = msg;
    t.classList.add("show");
    setTimeout(() => t.classList.remove("show"), 2500);
  }

  // ── 설정 ────────────────────────────────────────────────────────
  let currentSettings = { enSize: 22, koSize: 18, mode: "both" };

  async function loadAndApplySettings() {
    const res = await chrome.storage.local.get("eh-settings");
    if (res["eh-settings"]) {
      currentSettings = { ...currentSettings, ...res["eh-settings"] };
    }
    applySettings(currentSettings);
  }

  function applySettings(s) {
    currentSettings = { ...currentSettings, ...s };
    const textLine = document.getElementById("eh-text-line");
    const koLine   = document.getElementById("eh-ko-line");
    const enOnly   = currentSettings.mode === "en";

    if (textLine) textLine.style.fontSize = currentSettings.enSize + "px";
    if (koLine) {
      koLine.style.fontSize = currentSettings.koSize + "px";
      koLine.style.display  = enOnly ? "none" : "block";
    }

    // 타임라인 한글 줄 동기화
    document.querySelectorAll(".eh-tl-ko").forEach(el => {
      el.style.display = enOnly ? "none" : "block";
    });

    lastShownText = "";
  }

  // ── 토글 / 설정 메시지 수신 ─────────────────────────────────────
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "TOGGLE_OVERLAY") {
      overlayVisible = !overlayVisible;
      document.getElementById("eh-subtitle-overlay")?.classList.toggle("hidden", !overlayVisible);
      document.getElementById("eh-timeline")?.classList.toggle("hidden", !overlayVisible);
    }
    if (msg.type === "TOGGLE_TIMELINE") {
      const panel = document.getElementById("eh-timeline");
      if (!panel) return;
      if (msg.visible) {
        panel.classList.remove("hidden");
        panel.classList.remove("collapsed");
        document.getElementById("eh-tl-toggle").textContent = "✕";
        document.getElementById("eh-tl-hide").style.display = "flex";
      } else {
        panel.classList.add("hidden");
      }
    }
    if (msg.type === "APPLY_SETTINGS") {
      applySettings(msg.settings);
    }
  });

  // ── SPA 라우팅 ───────────────────────────────────────────────────
  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) { lastUrl = location.href; initCaptions(); }
  }).observe(document, { subtree: true, childList: true });

  // ── 초기화 ───────────────────────────────────────────────────────
  async function init() {
    createOverlay();
    createTimelinePanel();
    await loadAndApplySettings();
    startTimeTracking();
    await initCaptions();
  }

  document.readyState === "loading"
    ? document.addEventListener("DOMContentLoaded", init)
    : init();
})();
