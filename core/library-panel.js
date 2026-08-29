(function () {
  'use strict';

  let panelEl = null;
  let open = false;
  let tab = 'w'; // 'w' | 's'
  let words = [];
  let sentences = [];

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  async function loadData() {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      words = (res && res.words) || [];
      sentences = (res && res.sentences) || [];
    } catch (_) {
      words = [];
      sentences = [];
    }
  }

  function currentVideoCount() {
    const contentId = window.EH.adapter?.getPlatformMeta?.()?.contentId;
    if (!contentId) return 0;
    return words.filter(w => w.content_id === contentId).length +
           sentences.filter(s => s.content_id === contentId).length;
  }

  function render() {
    const items = tab === 'w' ? words : sentences;
    panelEl.innerHTML = `
      <div class="eh-library-header">
        <span class="eh-library-title">SAVED LIBRARY</span>
        <span class="eh-library-close" id="eh-library-close">✕</span>
      </div>
      <div class="eh-library-tabs">
        <div class="eh-library-tab${tab === 'w' ? ' active' : ''}" data-tab="w">단어 ${words.length}</div>
        <div class="eh-library-tab${tab === 's' ? ' active' : ''}" data-tab="s">문장 ${sentences.length}</div>
        <span style="flex:1"></span>
        <span class="eh-library-video-count">이 영상 ${currentVideoCount()}</span>
      </div>
      <div class="eh-library-list">
        ${items.length === 0
          ? '<div class="eh-library-empty">저장한 항목이 없습니다</div>'
          : items.map(it => tab === 'w' ? wordCard(it) : sentenceCard(it)).join('')}
      </div>
      <div class="eh-library-footer">
        <div class="eh-library-export-btn" id="eh-library-export">SQLite 내보내기<span class="eh-library-export-ext">.sqlite</span></div>
        <div class="eh-library-hint">내보낸 파일은 앱의 가져오기 화면에서 불러옵니다.</div>
      </div>
    `;

    panelEl.querySelector('#eh-library-close').addEventListener('click', hide);

    panelEl.querySelectorAll('.eh-library-tab').forEach(t => {
      t.addEventListener('click', () => { tab = t.dataset.tab; render(); });
    });

    panelEl.querySelectorAll('.eh-library-jump').forEach(el => {
      el.addEventListener('click', () => {
        const t = Number(el.dataset.timestamp);
        window.EH.adapter?.seekTo?.(t);
      });
    });

    panelEl.querySelector('#eh-library-export').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      const original = btn.innerHTML;
      btn.textContent = '내보내는 중...';
      try {
        await window.EH.SqliteExport.exportAll(words, sentences);
        btn.innerHTML = original;
      } catch (err) {
        console.error('[EH LibraryPanel] sqlite export failed', err);
        btn.textContent = '내보내기 실패';
        setTimeout(() => { btn.innerHTML = original; }, 2000);
      }
    });
  }

  function wordCard(w) {
    return `
      <div class="eh-library-card">
        <div class="eh-library-card-head">
          <span class="eh-library-card-word">${esc(w.word)}</span>
          <span class="eh-library-card-plat">${esc(w.platform || '')}</span>
        </div>
        <div class="eh-library-card-ko">${esc(w.translation || '')}</div>
        <div class="eh-library-jump" data-timestamp="${w.timestamp || 0}">▸ ${formatTime(w.timestamp || 0)}</div>
      </div>`;
  }

  function sentenceCard(s) {
    return `
      <div class="eh-library-card">
        <div class="eh-library-card-en">${esc(s.original)}</div>
        <div class="eh-library-card-ko">${esc(s.translation || '')}</div>
        <div class="eh-library-jump" data-timestamp="${s.timestamp || 0}">▸ ${formatTime(s.timestamp || 0)}</div>
      </div>`;
  }

  function createDOM() {
    if (document.getElementById('eh-library-panel')) {
      panelEl = document.getElementById('eh-library-panel');
      return;
    }
    panelEl = document.createElement('div');
    panelEl.id = 'eh-library-panel';
    panelEl.classList.add('hidden');
    document.body.appendChild(panelEl);
  }

  async function show() {
    open = true;
    await loadData();
    render();
    panelEl.classList.remove('hidden');
    document.dispatchEvent(new CustomEvent('eh-library-opened'));
  }

  function hide() {
    open = false;
    panelEl.classList.add('hidden');
    document.dispatchEvent(new CustomEvent('eh-library-closed'));
  }

  function toggle() {
    if (open) hide(); else show();
  }

  function setup() {
    createDOM();
    document.addEventListener('eh-library-toggle', toggle);
    // 설정 패널이 열리면 라이브러리 패널은 닫혀 상호 배타적으로 유지한다.
    document.addEventListener('eh-settings-opened', () => { if (open) hide(); });
  }

  window.EH = window.EH || {};
  window.EH.LibraryPanel = { setup };
})();
