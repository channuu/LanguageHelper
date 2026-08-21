(function () {
  'use strict';

  let overlayOn = true;
  let panelOn = true;
  let overlayToggleRef = null;
  let panelToggleRef = null;

  function createDOM(adapter) {
    if (document.getElementById('eh-topbar')) return;

    const bar = document.createElement('div');
    bar.id = 'eh-topbar';

    const brand = document.createElement('div');
    brand.className = 'eh-topbar-brand';
    const meta = adapter.getPlatformMeta?.() || { platform: '' };
    brand.innerHTML =
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

    const count = document.createElement('span');
    count.id = 'eh-topbar-count';
    count.className = 'eh-topbar-count';
    bar.appendChild(count);
    refreshCount(count);

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
    // 단어/문장 저장 시마다 카운트 재조회 (팝업/패널에서 dispatch)
    document.addEventListener('eh-item-saved', () => {
      refreshCount(count);
    });
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
      countEl.textContent = '저장 ' + total;
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
  window.EH.TopBar = { setup };
})();
