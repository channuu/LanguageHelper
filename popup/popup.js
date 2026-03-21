const $ = id => document.getElementById(id);

async function load() {
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

  if (sentences.length === 0) {
    list.innerHTML = `<div class="empty">아직 저장된 문장이 없어요.<br>YouTube나 Netflix에서<br>자막의 <strong style="color:var(--gold)">＋</strong> 버튼을 눌러보세요.</div>`;
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

function esc(s) {
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

$("sentence-list").addEventListener("click", async e => {
  const btn = e.target.closest(".btn-del");
  if (!btn) return;
  btn.closest(".sentence-item").style.opacity = "0.3";
  await chrome.runtime.sendMessage({ type: "DELETE_SENTENCE", payload: { id: btn.dataset.id } });
  load();
});

$("toggle-overlay").addEventListener("change", () => {
  chrome.runtime.sendMessage({ type: "TOGGLE_EXTENSION" });
});

load();
