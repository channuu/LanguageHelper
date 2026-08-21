(function () {
  'use strict';

  let enCues = [];
  let nativeCues = [];
  let lastActiveIdx = -1;

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  function findNativeText(enCue) {
    return nativeCues.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';
  }

  function _escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function _buildExportHtml(cues, nativeCuesArr, meta) {
    const title = _escapeHtml(meta?.title || '제목 없음');
    const platform = _escapeHtml(meta?.platform || '');
    const exportedAt = new Date().toLocaleDateString();

    const findNative = (enCue) =>
      nativeCuesArr.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';

    const rows = cues.map(cue => {
      const time = _escapeHtml(formatTime(cue.start));
      const en = _escapeHtml(cue.text);
      const native = _escapeHtml(findNative(cue));
      return `
        <div class="row">
          <span class="time">${time}</span>
          <div class="text">
            <div class="en">${en}</div>
            ${native ? `<div class="native">${native}</div>` : ''}
          </div>
        </div>`;
    }).join('\n');

    return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>${title}</title>
<style>
  body { font-family: -apple-system, 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif; max-width: 720px; margin: 40px auto; padding: 0 20px; color: #1a1a1a; }
  header { border-bottom: 2px solid #ddd; padding-bottom: 16px; margin-bottom: 24px; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  .meta { color: #666; font-size: 13px; }
  .row { display: flex; gap: 16px; padding: 10px 0; border-bottom: 1px solid #eee; }
  .time { color: #999; font-size: 12px; font-variant-numeric: tabular-nums; flex-shrink: 0; width: 48px; }
  .text { flex: 1; }
  .en { font-size: 15px; }
  .native { font-size: 13px; color: #666; margin-top: 2px; }
</style>
</head>
<body>
<header>
  <h1>${title}</h1>
  <div class="meta">${platform} · ${exportedAt} 내보냄</div>
</header>
<main>
${rows}
</main>
</body>
</html>`;
  }

  function exportScript() {
    if (!enCues.length) {
      window.EH.showToast?.('내보낼 자막이 없어요');
      return;
    }
    const meta = window.EH.adapter?.getPlatformMeta?.() || { platform: '', title: '' };
    const html = _buildExportHtml(enCues, nativeCues, meta);
    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${(meta.title || 'script').replace(/[\\/:*?"<>|]/g, '_')}.html`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function _isYouTube() {
    return location.hostname.includes('youtube.com');
  }

  // YouTube CSS 변수에서 패널 높이 읽기 (LR .lln-vertical-view height와 동일 기준)
  function _getYouTubePanelHeight() {
    const flexy = document.querySelector('ytd-watch-flexy');
    if (!flexy) return 522;
    const raw = getComputedStyle(flexy).getPropertyValue('--ytd-watch-flexy-panel-max-height').trim();
    return parseFloat(raw) || 522;
  }

  function _setLayoutForPanel(visible) {
    if (_isYouTube()) {
      const wrapper = document.getElementById('eh-panel-wrapper');
      if (wrapper) wrapper.classList.toggle('hidden', !visible);
    } else {
      let style = document.getElementById('eh-panel-push-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'eh-panel-push-style';
        document.head.appendChild(style);
      }
      if (!visible) { style.textContent = ''; return; }
      const panel = document.getElementById('eh-panel');
      const w = panel ? (parseInt(panel.style.width) || 400) : 400;
      style.textContent = `
        html { overflow-x: hidden !important; }
        body { padding-right: ${w}px !important; box-sizing: border-box !important; }
      `;
    }
  }

  function createDOM() {
    if (document.getElementById('eh-panel-wrapper') || document.getElementById('eh-panel')) return;

    const panel = document.createElement('div');
    panel.id = 'eh-panel';

    const resizeHandle = document.createElement('div');
    resizeHandle.id = 'eh-panel-resize';
    panel.appendChild(resizeHandle);

    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    if (_isYouTube()) {
      // ── LR과 동일한 구조: wrapper(relative block) + panel(absolute inset:0) ──
      // #secondary 사용 가능(넓은 창) → 임베드 / 0폭(좁은 창·극장) → 우측 고정 폴백
      const wrapper = document.createElement('div');
      wrapper.id = 'eh-panel-wrapper';
      wrapper.appendChild(panel);

      const applyMountStrategy = () => {
        const secondary = document.querySelector('#secondary');
        const secWidth = secondary ? secondary.offsetWidth : 0;
        if (secondary && secWidth > 0) {
          // 넓은 창: #secondary에 임베드 (LR 방식)
          panel.classList.remove('fixed-mode');
          if (panel.parentElement !== wrapper) wrapper.appendChild(panel);
          wrapper.style.height = _getYouTubePanelHeight() + 'px';
          if (wrapper.parentElement !== secondary) {
            secondary.insertBefore(wrapper, secondary.firstChild);
          }
        } else {
          // 좁은 창/사이드바 없음: 우측 고정 오버레이 폴백
          if (!panel.classList.contains('fixed-mode') || panel.parentElement !== document.body) {
            panel.classList.add('fixed-mode');
            wrapper.style.height = '';
            const savedW = localStorage.getItem('eh-panel-width');
            if (savedW) panel.style.width = savedW;
            document.body.appendChild(panel);
          }
        }
      };

      // 레이아웃이 준비될 때까지 재시도 후 전략 적용
      let tries = 0;
      const tryMount = () => {
        if (document.querySelector('#secondary') || tries++ > 20) {
          applyMountStrategy();
        } else {
          setTimeout(tryMount, 300);
        }
      };
      tryMount();

      // 창 크기 변경 시 임베드↔고정 재평가
      let resizeTimer = null;
      window.addEventListener('resize', () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(applyMountStrategy, 200);
      });
    } else {
      // 기타 플랫폼: body에 fixed 모드
      panel.classList.add('fixed-mode');
      const savedW = localStorage.getItem('eh-panel-width');
      if (savedW) panel.style.width = savedW;
      document.body.appendChild(panel);
      _setLayoutForPanel(true);
    }

    const collapseBtn = header.querySelector('#eh-panel-collapse');
    const hideBtn     = header.querySelector('#eh-panel-hide');
    const exportBtn   = header.querySelector('#eh-panel-export');

    exportBtn.addEventListener('click', exportScript);

    collapseBtn.addEventListener('click', () => {
      const collapsed = panel.classList.toggle('collapsed');
      collapseBtn.textContent = collapsed ? '▶' : '✕';
    });

    hideBtn.addEventListener('click', () => {
      toggle(false);
      document.dispatchEvent(new CustomEvent('eh-panel-toggled', { detail: { visible: false } }));
      window.EH.showToast?.('패널 숨김 — 팝업에서 다시 켤 수 있어요');
    });

    attachPanelResize(panel, resizeHandle);
  }

  function attachPanelResize(panel, handle) {
    let resizing = false, startX, startW;
    handle.addEventListener('mousedown', (e) => {
      e.preventDefault();
      resizing = true; startX = e.clientX;
      startW = panel.getBoundingClientRect().width;
      document.body.style.cursor = 'ew-resize';
    });
    document.addEventListener('mousemove', (e) => {
      if (!resizing) return;
      // 임베드 모드(#secondary)에서는 리사이즈 불가, 고정 모드에서는 허용
      const fixed = panel.classList.contains('fixed-mode');
      if (_isYouTube() && !fixed) return;
      const w = Math.min(560, Math.max(200, startW - (e.clientX - startX)));
      panel.style.width = w + 'px';
      if (!fixed) _setLayoutForPanel(true);
    });
    document.addEventListener('mouseup', () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = '';
      const fixed = panel.classList.contains('fixed-mode');
      if (!_isYouTube() || fixed) localStorage.setItem('eh-panel-width', panel.style.width);
    });
  }

  function renderList() {
    const list = document.getElementById('eh-panel-list');
    if (!list) return;
    if (!enCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">자막 없음</div>';
      return;
    }
    const s = window.EH.settings;
    list.innerHTML = '';
    enCues.forEach((cue, idx) => {
      const native = findNativeText(cue);
      const item = document.createElement('div');
      item.className = 'eh-panel-item';
      item.dataset.idx = idx;

      const time = document.createElement('span');
      time.className = 'eh-panel-time';
      time.textContent = formatTime(cue.start);

      const textWrap = document.createElement('div');
      textWrap.className = 'eh-panel-textwrap';

      const enSpan = document.createElement('span');
      enSpan.className = 'eh-panel-en';
      enSpan.textContent = cue.text;
      textWrap.appendChild(enSpan);

      if (native) {
        const nativeSpan = document.createElement('span');
        nativeSpan.className = 'eh-panel-native';
        nativeSpan.textContent = native;
        nativeSpan.style.display = s.mode === 'en' ? 'none' : 'block';
        textWrap.appendChild(nativeSpan);
      }

      const saveBtn = document.createElement('button');
      saveBtn.className = 'eh-panel-item-save';
      saveBtn.textContent = '＋';
      saveBtn.title = '문장 저장';
      saveBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        window.EH.Storage.saveSentence({
          original: cue.text,
          translation: native,
          timestamp: cue.start
        }).then(() => window.EH.showToast?.('✓ 문장 저장됨'));
      });

      item.appendChild(time);
      item.appendChild(textWrap);
      item.appendChild(saveBtn);
      item.addEventListener('click', () => window.EH.adapter.seekTo(cue.start + 0.1));
      list.appendChild(item);
    });
  }

  function highlight(enText) {
    if (!enText) return;
    const idx = enCues.findIndex(c => c.text === enText);
    if (idx === -1 || idx === lastActiveIdx) return;
    lastActiveIdx = idx;
    document.querySelectorAll('.eh-panel-item').forEach(el => el.classList.remove('active'));
    const active = document.querySelector(`.eh-panel-item[data-idx="${idx}"]`);
    if (active) {
      active.classList.add('active');
      active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  function applySettings(s) {
    document.querySelectorAll('.eh-panel-native').forEach(el => {
      el.style.display = s.mode === 'en' ? 'none' : 'block';
    });
  }

  function toggle(forceVisible) {
    const wrapper = document.getElementById('eh-panel-wrapper');
    const panel = document.getElementById('eh-panel');
    const target = wrapper || panel;
    if (!target) return undefined;
    let nowHidden;
    if (forceVisible !== undefined) {
      target.classList.toggle('hidden', !forceVisible);
      nowHidden = !forceVisible;
    } else {
      nowHidden = !target.classList.contains('hidden');
      target.classList.toggle('hidden');
    }
    if (!_isYouTube()) _setLayoutForPanel(!nowHidden);
    return !nowHidden;
  }

  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        console.log('[EH:panel] onTracksReady — enCues:', enCues.length, 'nativeCues:', nativeCues.length, 'listEl:', !!document.getElementById('eh-panel-list'));
        renderList();
      });
    }

    renderList();
  }

  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings, exportScript };
})();
