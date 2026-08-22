(function () {
  'use strict';

  const LANGS = { ko: '한국어', ja: '日本語', zh: '中文', es: 'Español', fr: 'Français', de: 'Deutsch' };
  // 9 ticks spanning the existing 12–52px enSize range and 10–48px nativeSize range.
  const EN_TICKS = [12, 17, 22, 27, 32, 37, 42, 47, 52];
  const KO_TICKS = [10, 14, 18, 22, 26, 30, 34, 41, 48];

  let panelEl = null;
  let open = false;

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function render() {
    const s = window.EH.settings;
    panelEl.innerHTML = `
      <div class="eh-settings-header">
        <span class="eh-settings-title">SETTINGS</span>
        <span class="eh-settings-close" id="eh-settings-close">✕</span>
      </div>
      <div class="eh-settings-body">
        <div class="eh-settings-label">모국어 (NATIVE LANGUAGE)</div>
        <div class="eh-settings-langs" id="eh-settings-langs">
          ${Object.entries(LANGS).map(([code, label]) => `
            <div class="eh-settings-chip${s.nativeLang === code ? ' active' : ''}" data-lang="${code}">${esc(label)}</div>
          `).join('')}
        </div>

        <div class="eh-settings-label" style="margin-top:18px">자막 표시 모드</div>
        <div class="eh-settings-mode-row">
          <div class="eh-settings-mode-btn${s.mode === 'en' ? ' active' : ''}" data-mode="en">영어만</div>
          <div class="eh-settings-mode-btn${s.mode === 'both' ? ' active' : ''}" data-mode="both">영어 + 모국어</div>
        </div>

        ${sliderBlock('영어 자막 크기', 'en', s.enSize, EN_TICKS)}
        ${sliderBlock('모국어 자막 크기', 'ko', s.nativeSize, KO_TICKS)}

        <div class="eh-settings-label" style="margin-top:18px">미리보기</div>
        <div class="eh-settings-preview">
          <div style="font-size:${s.enSize}px">I don't even care anymore.</div>
          ${s.mode !== 'en' ? `<div class="eh-settings-preview-ko" style="font-size:${s.nativeSize}px">나는 이제 신경도 안 써.</div>` : ''}
        </div>

        <div class="eh-settings-divider"></div>
        <div class="eh-settings-label">내보내기</div>
        <div class="eh-settings-export-row">
          <div class="eh-settings-export-btn primary" id="eh-export-script">스크립트 내보내기</div>
          <div class="eh-settings-export-btn" id="eh-export-sqlite">저장 항목 내보내기<span class="eh-settings-export-ext">.sqlite</span></div>
        </div>
      </div>
    `;

    panelEl.querySelector('#eh-settings-close').addEventListener('click', hide);

    panelEl.querySelectorAll('.eh-settings-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        window.EH.applySettings({ nativeLang: chip.dataset.lang });
        render();
      });
    });

    panelEl.querySelectorAll('.eh-settings-mode-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        window.EH.applySettings({ mode: btn.dataset.mode });
        render();
      });
    });

    attachSlider('en', EN_TICKS);
    attachSlider('ko', KO_TICKS);

    panelEl.querySelector('#eh-export-script').addEventListener('click', () => {
      window.EH.ScriptPanel?.exportScript();
    });

    panelEl.querySelector('#eh-export-sqlite').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      const original = btn.innerHTML;
      btn.textContent = '내보내는 중...';
      try {
        const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
        await window.EH.SqliteExport.exportAll((res && res.words) || [], (res && res.sentences) || []);
        btn.innerHTML = original;
      } catch (err) {
        console.error('[EH SettingsPanel] sqlite export failed', err);
        btn.textContent = '내보내기 실패';
        setTimeout(() => { btn.innerHTML = original; }, 2000);
      }
    });
  }

  function sliderBlock(label, key, value, ticks) {
    const sizeKey = key === 'en' ? 'enSize' : 'nativeSize';
    return `
      <div class="eh-settings-slider-header" style="margin-top:18px">
        <span class="eh-settings-label" style="margin:0">${esc(label)}</span>
        <span class="eh-settings-slider-value" data-size-label="${key}">${value}px</span>
      </div>
      <div class="eh-settings-slider-row" data-slider="${key}" data-size-key="${sizeKey}">
        ${ticks.map(t => `<div class="eh-settings-tick${t <= value ? ' active' : ''}" data-tick="${t}"></div>`).join('')}
      </div>
    `;
  }

  function attachSlider(key, ticks) {
    const row = panelEl.querySelector(`.eh-settings-slider-row[data-slider="${key}"]`);
    if (!row) return;
    row.querySelectorAll('.eh-settings-tick').forEach(tickEl => {
      tickEl.addEventListener('click', () => {
        const value = Number(tickEl.dataset.tick);
        const sizeKey = row.dataset.sizeKey;
        window.EH.applySettings({ [sizeKey]: value });
        render();
      });
    });
  }

  function createDOM() {
    if (document.getElementById('eh-settings-panel')) {
      panelEl = document.getElementById('eh-settings-panel');
      return;
    }
    panelEl = document.createElement('div');
    panelEl.id = 'eh-settings-panel';
    panelEl.classList.add('hidden');
    document.body.appendChild(panelEl);
  }

  function show() {
    open = true;
    render();
    panelEl.classList.remove('hidden');
    document.dispatchEvent(new CustomEvent('eh-settings-opened'));
  }

  function hide() {
    open = false;
    panelEl.classList.add('hidden');
    document.dispatchEvent(new CustomEvent('eh-settings-closed'));
  }

  function toggle() {
    if (open) hide(); else show();
  }

  function setup() {
    createDOM();
    document.addEventListener('eh-settings-toggle', toggle);
    // 라이브러리 패널이 열리면 설정 패널은 닫혀 상호 배타적으로 유지한다.
    document.addEventListener('eh-library-opened', () => { if (open) hide(); });
  }

  window.EH = window.EH || {};
  window.EH.SettingsPanel = { setup };
})();
