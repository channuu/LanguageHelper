(function () {
  'use strict';

  const LANGS = { ko: '한국어', ja: '日本語', zh: '中文', es: 'Español', fr: 'Français', de: 'Deutsch' };
  // 2026-08-22 목업 재확인 값 그대로 사용 (§1h/1i DCLogic enTicks/koTicks).
  const EN_TICKS = [12, 17, 22, 26, 31, 36, 41, 46, 52];
  const KO_TICKS = [10, 14, 18, 22, 26, 32, 38, 44, 48];
  // §1h DCLogic lineOpts/lineNote 값 그대로 사용.
  const LINE_OPTS = [
    { n: 1, label: '짧게', bars: ['26px'] },
    { n: 2, label: '보통', bars: ['34px', '22px'] },
    { n: 3, label: '길게', bars: ['38px', '38px', '20px'] }
  ];
  const LINE_NOTES = {
    1: '한 번에 아주 짧은 분량만 보여줍니다. 긴 문장은 여러 항목으로 나뉘어요.',
    2: '적당한 분량을 한 번에 보여줍니다. 대부분의 문장이 한 항목에 들어옵니다.',
    3: '보통보다 1.5~2배 더 긴 분량을 한 번에 보여줍니다. 아주 긴 문장만 나뉘어요.'
  };
  // 스크립트 패널/오버레이와 똑같이 core/cue-utils.js로 실제 청크를 만들어
  // 미리보기에 쓴다 — 미리보기가 실제 동작과 어긋나면 설정의 의미가 없다.
  // 옵션별 차이가 실제로 보이도록 일부러 긴 문장 하나를 그대로 사용한다.
  const PREVIEW_EN_FULL = "She said it like it was obvious, and I kept turning it over all night — I don't even care anymore, everything leaves a mark somewhere, and nothing in life is ever truly ephemeral.";
  const PREVIEW_KO_FULL = '그녀는 당연한 일처럼 말했고, 나는 밤새 그 말을 되짚었다 — 나는 이제 신경도 안 써, 모든 것은 어딘가에 흔적을 남기고, 인생에서 진짜로 덧없는 것은 없다.';

  let panelEl = null;
  let open = false;

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function render() {
    const s = window.EH.settings;
    const previewEn = window.EH.CueUtils.splitIntoChunks(PREVIEW_EN_FULL, s.cueLines)[0];
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

        <div class="eh-settings-label" style="margin-top:18px">한 줄에 표시할 분량</div>
        <div class="eh-settings-line-row" id="eh-settings-line-row">
          ${LINE_OPTS.map(opt => `
            <div class="eh-settings-line-btn${s.cueLines === opt.n ? ' active' : ''}" data-lines="${opt.n}">
              <div class="eh-settings-line-bars">
                ${opt.bars.map(w => `<span class="eh-settings-line-bar" style="width:${w}"></span>`).join('')}
              </div>
              <span class="eh-settings-line-label">${opt.label}</span>
            </div>
          `).join('')}
        </div>
        <div class="eh-settings-line-note">${LINE_NOTES[s.cueLines]}</div>

        ${sliderBlock('영어 자막 크기', 'en', s.enSize, EN_TICKS)}
        ${sliderBlock('모국어 자막 크기', 'ko', s.nativeSize, KO_TICKS)}

        <div class="eh-settings-label" style="margin-top:18px">미리보기</div>
        <div class="eh-settings-preview">
          <div class="eh-settings-preview-en" style="font-size:${s.enSize}px">${esc(previewEn)}</div>
          ${s.mode !== 'en' ? `<div class="eh-settings-preview-ko" style="font-size:${s.nativeSize}px">${esc(PREVIEW_KO_FULL)}</div>` : ''}
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

    panelEl.querySelectorAll('.eh-settings-line-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        window.EH.applySettings({ cueLines: Number(btn.dataset.lines) });
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
    const glyph = key === 'en' ? 'A' : '가';
    return `
      <div class="eh-settings-slider-header" style="margin-top:18px">
        <span class="eh-settings-label" style="margin:0">${esc(label)}</span>
        <span class="eh-settings-slider-value" data-size-label="${key}">${value}px</span>
      </div>
      <div class="eh-settings-slider-track" style="margin-top:11px">
        <span class="eh-settings-glyph small">${glyph}</span>
        <div class="eh-settings-slider-row" data-slider="${key}" data-size-key="${sizeKey}">
          ${ticks.map((t, i) => `
            <div class="eh-settings-tick-col" data-tick="${t}">
              <div class="eh-settings-tick${t <= value ? ' active' : ''}" style="height:${36 + i * 8}%"></div>
            </div>
          `).join('')}
        </div>
        <span class="eh-settings-glyph large">${glyph}</span>
      </div>
    `;
  }

  function attachSlider(key, ticks) {
    const row = panelEl.querySelector(`.eh-settings-slider-row[data-slider="${key}"]`);
    if (!row) return;
    row.querySelectorAll('.eh-settings-tick-col').forEach(colEl => {
      colEl.addEventListener('click', () => {
        const value = Number(colEl.dataset.tick);
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
