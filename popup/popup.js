// ================================================================
// popup/popup.js — 툴바 아이콘 팝업 (Claude Design §1k)
// 영상 위 상단 바를 없앤 뒤로 이 팝업이 유일한 상시 진입점이다.
// 전체 기능 마스터 스위치, 오버레이·패널 토글, 저장 목록을 담당한다.
// 자막 설정(모국어·표시 모드·한 줄 분량·크기·내보내기)은 자막이 보이는
// 곳에서만 조작하도록 스크립트 패널 헤더의 설정 버튼이 맡는다.
// ================================================================
(function () {
  'use strict';

  const PLATFORMS = [
    { host: 'youtube.com', label: 'YOUTUBE', name: 'YouTube' },
    { host: 'netflix.com', label: 'NETFLIX', name: 'Netflix' },
    { host: 'disneyplus.com', label: 'DISNEY+', name: 'Disney+' },
    { host: 'coupangplay.com', label: 'COUPANG', name: '쿠팡플레이' }
  ];

  const $ = (id) => document.getElementById(id);

  let tabId = null;
  let platform = null;
  let state = { enabled: true, overlay: false, panel: false };

  // 콘텐츠 스크립트가 없는 탭(비지원 사이트, 주입 전)에서는 sendMessage가
  // 거부된 프로미스를 준다. 팝업이 죽지 않게 항상 삼킨다.
  function send(msg) {
    return new Promise((resolve) => {
      try {
        chrome.tabs.sendMessage(tabId, msg, (res) => {
          void chrome.runtime.lastError;
          resolve(res || null);
        });
      } catch (e) { resolve(null); }
    });
  }

  // ── 렌더 ─────────────────────────────────────────────────────────

  function renderChrome() {
    $('ver').textContent = 'v' + chrome.runtime.getManifest().version;

    if (!platform) {
      document.body.classList.add('unsupported');
      $('site-badge').textContent = '미지원';
      $('site-badge').classList.add('off');
      $('site-line').textContent =
        'YouTube · Netflix · Disney+ · 쿠팡플레이의 영상 페이지에서 동작합니다.';
      return;
    }
    $('site-badge').textContent = platform.label;
    $('site-line').textContent = state.enabled
      ? platform.name + ' 영상 페이지에서 동작 중입니다. 자막 설정은 스크립트 패널 헤더의 설정 버튼에 있습니다.'
      : platform.name + '에서 꺼져 있습니다. 켜면 페이지를 새로고침합니다.';
  }

  function renderToggles() {
    $('master-sw').classList.toggle('on', state.enabled);
    $('master').classList.toggle('off', !state.enabled);
    $('master-sub').textContent = state.enabled
      ? '자막 오버레이와 스크립트 패널을 사용합니다'
      : '이 페이지에서 확장 UI를 모두 끕니다';
    $('subs').classList.toggle('disabled', !state.enabled);
    $('sw-overlay').classList.toggle('on', state.overlay);
    $('sw-panel').classList.toggle('on', state.panel);
  }

  async function renderLibraryCount() {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      const n = (res?.words?.length || 0) + (res?.sentences?.length || 0);
      $('lib-count').textContent = String(n);
    } catch (e) {
      $('lib-count').textContent = '–';
    }
  }

  async function renderAccount() {
    try {
      const { 'eh-auth': auth } = await chrome.storage.local.get('eh-auth');
      if (auth && auth.email) {
        $('acct').textContent = auth.email + ' · 동기화됨';
        $('acct-dot').classList.add('on');
        return;
      }
    } catch (e) {}
    $('acct').textContent = '로그인하지 않음';
  }

  // ── 동작 ─────────────────────────────────────────────────────────

  async function setMaster(enabled) {
    if (enabled) {
      // destroy()한 어댑터는 되살릴 수 없어서 새로고침으로 깨끗하게 다시 세운다.
      await chrome.storage.local.set({ 'eh-enabled': true });
      await send({ type: 'EH_SET_ENABLED', enabled: true });
      chrome.tabs.reload(tabId);
      window.close();
      return;
    }
    state.enabled = false;
    state.overlay = false;
    state.panel = false;
    renderToggles();
    renderChrome();
    await chrome.storage.local.set({ 'eh-enabled': false });
    await send({ type: 'EH_SET_ENABLED', enabled: false });
  }

  function wire() {
    const onActivate = (el, fn) => {
      el.addEventListener('click', fn);
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fn(); }
      });
    };

    onActivate($('master'), () => setMaster(!state.enabled));

    onActivate($('row-overlay'), async () => {
      state.overlay = !state.overlay;
      renderToggles();
      // TOGGLE_OVERLAY는 인자 없는 토글이다 — 위에서 이미 뒤집은 값과
      // 콘텐츠 스크립트의 실제 상태가 같아지도록 한 번만 보낸다.
      await send({ type: 'TOGGLE_OVERLAY' });
    });

    onActivate($('row-panel'), async () => {
      state.panel = !state.panel;
      renderToggles();
      await send({ type: 'TOGGLE_PANEL', visible: state.panel });
    });

    onActivate($('row-library'), async () => {
      await send({ type: 'EH_OPEN_LIBRARY' });
      window.close();
    });

  }

  // ── 시작 ─────────────────────────────────────────────────────────

  async function main() {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    tabId = tab?.id ?? null;
    const url = tab?.url || '';
    platform = PLATFORMS.find((p) => url.includes(p.host)) || null;

    const stored = await chrome.storage.local.get('eh-enabled');
    state.enabled = stored['eh-enabled'] !== false;

    if (platform && tabId != null) {
      const live = await send({ type: 'EH_GET_STATE' });
      if (live?.ok) {
        state.enabled = live.enabled;
        state.overlay = live.overlay;
        state.panel = live.panel;
      }
    }

    renderChrome();
    renderToggles();
    wire();
    renderLibraryCount();
    renderAccount();
  }

  main();
})();
