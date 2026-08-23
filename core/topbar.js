(function () {
  'use strict';

  let overlayOn = true;
  let panelOn = true;
  let overlayToggleRef = null;
  let panelToggleRef = null;

  const TOPBAR_HEIGHT = 46; // #eh-topbar의 height와 반드시 일치해야 함

  // 상단 바가 position:fixed로 페이지 맨 위에 얹히는데, 유튜브/넷플릭스도
  // 자기 헤더(유튜브 마스트헤드, 넷플릭스 상단 네비게이션)를 fixed/sticky로
  // top:0에 고정해 두고 있어서, 우리 바가 그 위를 그대로 덮어버려 로고·검색·
  // 메뉴 버튼이 안 보이고 클릭도 안 되는 문제가 있었다. 해당 플랫폼 헤더를
  // 우리 바 높이만큼 아래로 밀고, 그 헤더 뒤를 따르는 본문 콘텐츠도 같은
  // 만큼 추가로 밀어서 자리를 맞춘다. 높이는 실제 렌더링된 값을 그때그때
  // 읽어서 계산한다 — 플랫폼이 헤더 높이를 바꿔도 깨지지 않도록.
  function _pushPageBelowTopbar() {
    let style = document.getElementById('eh-topbar-push-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'eh-topbar-push-style';
      document.head.appendChild(style);
    }

    if (location.hostname.includes('youtube.com')) {
      const masthead = document.querySelector('#masthead-container');
      const pageManager = document.querySelector('#page-manager');
      if (!masthead || !pageManager) { setTimeout(_pushPageBelowTopbar, 300); return; }
      const mastheadHeight = masthead.getBoundingClientRect().height || 56;
      style.textContent = `
        #masthead-container { top: ${TOPBAR_HEIGHT}px !important; }
        #page-manager { margin-top: ${mastheadHeight + TOPBAR_HEIGHT}px !important; }
      `;
    } else if (location.hostname.includes('netflix.com')) {
      // 넷플릭스 상단 네비게이션(홈/찾아보기/검색 등)은 position:sticky라
      // 스크롤을 내리면 결국 top:0에서 우리 바 밑으로 다시 붙어야 한다.
      // 영상 재생 페이지의 플레이어(.watch-video--player-view)는 body
      // padding과 무관한 position:absolute라, 뒤로가기 버튼 등 플레이어
      // 자체 컨트롤(플레이어 기준 top:0 근처에 배치됨)이 우리 바 바로
      // 아래에 눌려 붙어 겹쳐 보인다 — 플레이어 자체를 우리 바 높이만큼
      // 아래로 밀고 그만큼 높이도 줄여서 화면 하단을 벗어나지 않게 한다.
      style.textContent = `
        body { padding-top: ${TOPBAR_HEIGHT}px !important; }
        nav[data-uia="navigation"] { top: ${TOPBAR_HEIGHT}px !important; }
        .watch-video--player-view {
          top: ${TOPBAR_HEIGHT}px !important;
          height: calc(100% - ${TOPBAR_HEIGHT}px) !important;
        }
      `;
    } else {
      style.textContent = `body { padding-top: ${TOPBAR_HEIGHT}px !important; }`;
    }
  }

  function createDOM(adapter) {
    if (document.getElementById('eh-topbar')) return;

    const bar = document.createElement('div');
    bar.id = 'eh-topbar';

    const brand = document.createElement('div');
    brand.className = 'eh-topbar-brand';
    const meta = adapter.getPlatformMeta?.() || { platform: '' };
    brand.innerHTML =
      `<img class="eh-topbar-icon" src="${chrome.runtime.getURL('icons/icon48.png')}" alt="">` +
      '<span class="eh-topbar-name">English Helper</span>' +
      `<span class="eh-topbar-badge">${esc((meta.platform || '').toUpperCase())}</span>`;
    bar.appendChild(brand);

    const divider = document.createElement('div');
    divider.className = 'eh-topbar-divider';
    bar.appendChild(divider);

    const overlayToggle = buildToggle('자막 오버레이', overlayOn, () => {
      overlayOn = !overlayOn;
      window.EH.SubtitleEngine?.toggle();
      updateToggleState(overlayToggle, overlayOn);
    });
    overlayToggleRef = overlayToggle;
    bar.appendChild(overlayToggle.el);

    const panelToggle = buildToggle('스크립트 패널', panelOn, () => {
      panelOn = !panelOn;
      window.EH.ScriptPanel?.toggle(panelOn);
      updateToggleState(panelToggle, panelOn);
    });
    panelToggleRef = panelToggle;
    bar.appendChild(panelToggle.el);

    const spacer = document.createElement('div');
    spacer.style.flex = '1';
    bar.appendChild(spacer);

    const libBtn = document.createElement('div');
    libBtn.id = 'eh-topbar-library';
    libBtn.className = 'eh-topbar-lib-btn';
    libBtn.innerHTML =
      '<svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round">' +
      '<path d="M3.2 1.9h6.6a1 1 0 0 1 1 1v8.2l-4.3-2.4-4.3 2.4V2.9a1 1 0 0 1 1-1z"></path></svg>' +
      '<span>저장 목록</span>' +
      '<span class="eh-topbar-lib-count" id="eh-topbar-lib-count"></span>';
    libBtn.addEventListener('click', () => {
      document.dispatchEvent(new CustomEvent('eh-library-toggle'));
    });
    bar.appendChild(libBtn);
    refreshCount(libBtn.querySelector('#eh-topbar-lib-count'));

    const settingsBtn = document.createElement('div');
    settingsBtn.id = 'eh-topbar-settings';
    settingsBtn.className = 'eh-topbar-settings-btn';
    settingsBtn.innerHTML =
      '<svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round">' +
      '<path d="M1.6 3.6h9.8M1.6 9.4h9.8"></path>' +
      '<circle cx="4.6" cy="3.6" r="1.7"></circle><circle cx="8.4" cy="9.4" r="1.7"></circle></svg>' +
      '<span>설정</span>';
    settingsBtn.addEventListener('click', () => {
      document.dispatchEvent(new CustomEvent('eh-settings-toggle'));
    });
    bar.appendChild(settingsBtn);

    document.body.appendChild(bar);
    _pushPageBelowTopbar();

    // 팝업 등 다른 UI에서 SubtitleEngine/ScriptPanel을 직접 토글한 경우에도
    // 스위치 표시가 어긋나지 않도록 동기화 (여기서는 다시 toggle()을 호출하지 않는다).
    document.addEventListener('eh-overlay-toggled', (e) => {
      if (!overlayToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      overlayOn = e.detail.visible;
      updateToggleState(overlayToggleRef, overlayOn);
    });
    document.addEventListener('eh-panel-toggled', (e) => {
      if (!panelToggleRef || !e.detail || typeof e.detail.visible !== 'boolean') return;
      panelOn = e.detail.visible;
      updateToggleState(panelToggleRef, panelOn);
    });
    // 단어/문장 저장 시마다 라이브러리 버튼의 개수 배지 재조회
    document.addEventListener('eh-item-saved', () => {
      refreshCount(libBtn.querySelector('#eh-topbar-lib-count'));
    });

    // 설정/라이브러리 패널의 열림·닫힘에 맞춰 해당 버튼에 active 스타일 적용
    document.addEventListener('eh-settings-opened', () => settingsBtn.classList.add('active'));
    document.addEventListener('eh-settings-closed', () => settingsBtn.classList.remove('active'));
    document.addEventListener('eh-library-opened', () => libBtn.classList.add('active'));
    document.addEventListener('eh-library-closed', () => libBtn.classList.remove('active'));
  }

  function buildToggle(label, initialOn, onClick) {
    const el = document.createElement('div');
    el.className = 'eh-topbar-toggle';
    el.innerHTML =
      '<span class="eh-topbar-switch"><span class="eh-topbar-knob"></span></span>' +
      `<span class="eh-topbar-toggle-label">${esc(label)}</span>`;
    el.addEventListener('click', onClick);
    const wrapper = { el };
    updateToggleState(wrapper, initialOn);
    return wrapper;
  }

  function updateToggleState(toggle, on) {
    toggle.el.querySelector('.eh-topbar-switch').classList.toggle('on', on);
    toggle.el.querySelector('.eh-topbar-toggle-label').classList.toggle('dim', !on);
  }

  async function refreshCount(countEl) {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      const total = ((res && res.words) || []).length + ((res && res.sentences) || []).length;
      countEl.textContent = String(total);
    } catch (_) {
      countEl.textContent = '';
    }
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function setup(adapter) {
    createDOM(adapter);
  }

  window.EH = window.EH || {};
  window.EH.TopBar = { setup, refreshLayout: _pushPageBelowTopbar };
})();
