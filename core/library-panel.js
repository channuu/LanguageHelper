(function () {
  'use strict';

  let panelEl = null;
  let open = false;
  let tab = 'w'; // 'w' | 's'
  let words = [];
  let sentences = [];
  let signedIn = false;
  let email = null;
  let syncStatus = { lastSyncAt: null, pending: 0 };

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  function formatSyncTime(iso) {
    if (!iso) return '아직 동기화 안 됨';
    const d = new Date(iso);
    return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')} 동기화됨`;
  }

  async function loadData() {
    try {
      const auth = await chrome.runtime.sendMessage({ type: 'EH_AUTH_STATE' });
      signedIn = !!(auth && auth.signedIn);
      email = auth ? auth.email : null;

      if (!signedIn) {
        words = [];
        sentences = [];
        return;
      }

      // 패널을 열 때 한 번 당겨온다 (설계 §7.2) — 그러지 않으면 폰에서 지운
      // 항목이 다음 알람(15분)이나 다음 저장 전까지 계속 보인다. 실패는
      // 무시한다: 캐시된 로컬 데이터로 그리면 된다.
      try {
        await chrome.runtime.sendMessage({ type: 'EH_SYNC_NOW' });
      } catch (_) { /* 오프라인 — 로컬 데이터로 그린다 */ }

      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      words = (res && res.words) || [];
      sentences = (res && res.sentences) || [];
      const status = await chrome.runtime.sendMessage({ type: 'EH_SYNC_STATUS' });
      syncStatus = status || { lastSyncAt: null, pending: 0 };
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
    if (!signedIn) {
      panelEl.innerHTML = `
        <div class="eh-library-header">
          <span class="eh-library-title">SAVED LIBRARY</span>
          <span class="eh-library-close" id="eh-library-close">✕</span>
        </div>
        <div class="eh-library-signin">
          <div class="eh-library-signin-msg">저장한 단어를 보려면 로그인하세요.</div>
          <div class="eh-library-signin-btn" id="eh-library-signin">로그인</div>
        </div>
      `;
      panelEl.querySelector('#eh-library-close').addEventListener('click', hide);
      panelEl.querySelector('#eh-library-signin').addEventListener('click', () => {
        chrome.runtime.sendMessage({ type: 'EH_OPEN_LOGIN' });
      });
      return;
    }

    const items = tab === 'w' ? words : sentences;
    panelEl.innerHTML = `
      <div class="eh-library-header">
        <span class="eh-library-title">SAVED LIBRARY</span>
        <span class="eh-library-close" id="eh-library-close">✕</span>
      </div>
      <div class="eh-library-sync">
        <span class="eh-library-sync-time">${esc(formatSyncTime(syncStatus.lastSyncAt))}</span>
        ${syncStatus.pending > 0
          ? `<span class="eh-library-sync-pending">${syncStatus.pending}개 대기 중</span>`
          : ''}
        <span style="flex:1"></span>
        <span class="eh-library-signout" id="eh-library-signout">${esc(email || '')} · 로그아웃</span>
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
    `;

    panelEl.querySelector('#eh-library-close').addEventListener('click', hide);

    panelEl.querySelector('#eh-library-signout').addEventListener('click', async () => {
      let res = await chrome.runtime.sendMessage({ type: 'EH_SIGN_OUT' });
      if (res && !res.success && res.error === 'pending') {
        const ok = confirm(
          `${res.pending}개 항목이 아직 저장되지 않았어요. 로그아웃하면 사라집니다. 계속할까요?`
        );
        if (!ok) return;
        res = await chrome.runtime.sendMessage({
          type: 'EH_SIGN_OUT', payload: { force: true }
        });
      }
      await loadData();
      render();
    });

    panelEl.querySelectorAll('.eh-library-tab').forEach(t => {
      t.addEventListener('click', () => { tab = t.dataset.tab; render(); });
    });

    panelEl.querySelectorAll('.eh-library-jump').forEach(el => {
      el.addEventListener('click', () => {
        const t = Number(el.dataset.timestamp);
        window.EH.adapter?.seekTo?.(t);
      });
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

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type !== 'EH_AUTH_CHANGED') return;
    if (!panelEl || !open) return;
    loadData().then(render);
  });
})();
