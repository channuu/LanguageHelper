const $ = id => document.getElementById(id);

// ── 탭 전환 ──────────────────────────────────────────────────────
document.querySelectorAll(".tab-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab-panel").forEach(p => p.classList.remove("active"));
    btn.classList.add("active");
    $(btn.dataset.tab).classList.add("active");
  });
});

// ── 설정 로드 ────────────────────────────────────────────────────
const DEFAULT_SETTINGS = { enSize: 22, koSize: 18, mode: "both" };

async function loadSettings() {
  const res = await chrome.storage.local.get("eh-settings");
  return { ...DEFAULT_SETTINGS, ...(res["eh-settings"] || {}) };
}

async function saveSettings(patch) {
  const cur = await loadSettings();
  const next = { ...cur, ...patch };
  await chrome.storage.local.set({ "eh-settings": next });
  return next;
}

// ── 설정 UI 적용 ─────────────────────────────────────────────────
function applySettingsUI(s) {
  $("en-size").value     = s.enSize;
  $("ko-size").value     = s.koSize;
  $("en-size-val").textContent = s.enSize + "px";
  $("ko-size-val").textContent = s.koSize + "px";
  $("preview-en").style.fontSize = s.enSize + "px";
  $("preview-ko").style.fontSize = s.koSize + "px";
  $("preview-ko").style.display = s.mode === "en" ? "none" : "block";
  document.querySelectorAll(".mode-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.mode === s.mode);
  });
}

// 설정을 content script에 전달
async function sendSettingsToTab(settings) {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tabs[0]) {
    chrome.tabs.sendMessage(tabs[0].id, {
      type: "APPLY_SETTINGS",
      settings
    }).catch(() => {});
  }
}

// ── 설정 이벤트 ──────────────────────────────────────────────────
$("en-size").addEventListener("input", async (e) => {
  const v = parseInt(e.target.value);
  $("en-size-val").textContent = v + "px";
  $("preview-en").style.fontSize = v + "px";
  const s = await saveSettings({ enSize: v });
  sendSettingsToTab(s);
});

$("ko-size").addEventListener("input", async (e) => {
  const v = parseInt(e.target.value);
  $("ko-size-val").textContent = v + "px";
  $("preview-ko").style.fontSize = v + "px";
  const s = await saveSettings({ koSize: v });
  sendSettingsToTab(s);
});

document.querySelectorAll(".mode-btn").forEach(btn => {
  btn.addEventListener("click", async () => {
    const s = await saveSettings({ mode: btn.dataset.mode });
    applySettingsUI(s);
    sendSettingsToTab(s);
  });
});

// ── 오버레이 / 타임라인 토글 ─────────────────────────────────────
$("toggle-overlay").addEventListener("change", () => {
  chrome.runtime.sendMessage({ type: "TOGGLE_EXTENSION" });
});

$("toggle-timeline").addEventListener("change", async (e) => {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tabs[0]) {
    chrome.tabs.sendMessage(tabs[0].id, {
      type: "TOGGLE_TIMELINE",
      visible: e.target.checked
    }).catch(() => {});
  }
});

// ── 저장 문장 로드 ────────────────────────────────────────────────
async function loadSentences() {
  const res = await chrome.runtime.sendMessage({ type: "GET_SENTENCES" });
  const list = $("sentence-list");
  const sentences = res.sentences || [];

  const badge = $("count-badge");
  if (sentences.length > 0) {
    badge.textContent = sentences.length + "개";
    badge.style.display = "inline";
  } else {
    badge.style.display = "none";
  }

  if (!sentences.length) {
    list.innerHTML = '<div class="empty">아직 저장된 문장이 없어요.<br>자막의 단어를 클릭해보세요.</div>';
    return;
  }

  list.innerHTML = sentences.slice(0, 50).map(s => `
    <div class="sentence-item">
      <div class="sentence-en">${esc(s.english)}</div>
      <div class="sentence-meta">
        <span class="src-badge">${s.source === "youtube" ? "▶ YouTube" : "▶ Netflix"}</span>
        ${esc(s.videoTitle || "제목 없음")}
      </div>
      <button class="btn-del" data-id="${s.id}">✕</button>
    </div>`).join("");
}

$("sentence-list").addEventListener("click", async e => {
  const btn = e.target.closest(".btn-del");
  if (!btn) return;
  btn.closest(".sentence-item").style.opacity = "0.3";
  await chrome.runtime.sendMessage({ type: "DELETE_SENTENCE", payload: { id: btn.dataset.id } });
  loadSentences();
});

function esc(s) {
  return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

// ── 초기화 ───────────────────────────────────────────────────────
async function init() {
  const s = await loadSettings();
  applySettingsUI(s);
  loadSentences();
}

init();
