(function () {
  'use strict';

  let overlayOn = true;
  let panelOn = true;

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
    bar.appendChild(overlayToggle.el);

    const panelToggle = buildToggle('스크립트 패널', panelOn, () => {
      panelOn = !panelOn;
      window.EH.ScriptPanel?.toggle(panelOn);
      updateToggleState(panelToggle, panelOn);
    });
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
