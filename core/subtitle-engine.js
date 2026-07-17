(function () {
  'use strict';

  let visible = true;
  let currentEnText = '';
  let currentNativeText = '';
  let rafId = null;

  function createDOM() {
    if (document.getElementById('eh-overlay')) return;

    const overlay = document.createElement('div');
    overlay.id = 'eh-overlay';

    const enLine = document.createElement('div');
    enLine.id = 'eh-en-line';
    overlay.appendChild(enLine);

    const nativeLine = document.createElement('div');
    nativeLine.id = 'eh-native-line';
    overlay.appendChild(nativeLine);

    const handle = document.createElement('div');
    handle.id = 'eh-resize-handle';
    overlay.appendChild(handle);

    document.body.appendChild(overlay);

    const toast = document.createElement('div');
    toast.id = 'eh-toast';
    document.body.appendChild(toast);

    restorePosition(overlay, enLine, nativeLine);
    attachDrag(overlay, enLine, nativeLine);
    attachResize(overlay, enLine, nativeLine, handle);
  }

  function restorePosition(overlay, enLine, nativeLine) {
    const saved = JSON.parse(localStorage.getItem('eh-overlay-pos') || 'null');
    if (saved?.left && saved?.top) {
      overlay.style.left = saved.left;
      overlay.style.top = saved.top;
      overlay.style.bottom = 'auto';
      overlay.style.transform = 'none';
    }
    if (saved?.enSize) enLine.style.fontSize = saved.enSize;
    if (saved?.nativeSize) nativeLine.style.fontSize = saved.nativeSize;
  }

  function attachDrag(overlay, enLine, nativeLine) {
    let dragging = false, sx, sy, ox, oy;
    overlay.addEventListener('mousedown', (e) => {
      if (e.target.id === 'eh-resize-handle' || e.target.classList.contains('eh-word')) return;
      dragging = true;
      overlay.classList.add('dragging');
      const r = overlay.getBoundingClientRect();
      sx = e.clientX; sy = e.clientY; ox = r.left; oy = r.top;
      e.preventDefault();
    });
    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      overlay.style.left = (ox + e.clientX - sx) + 'px';
      overlay.style.top  = (oy + e.clientY - sy) + 'px';
      overlay.style.bottom = 'auto';
      overlay.style.transform = 'none';
    });
    document.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false;
      overlay.classList.remove('dragging');
      savePosition(overlay, enLine, nativeLine);
    });
  }

  function attachResize(overlay, enLine, nativeLine, handle) {
    let resizing = false, startX, startSize;
    handle.addEventListener('mousedown', (e) => {
      e.stopPropagation(); e.preventDefault();
      resizing = true; startX = e.clientX;
      startSize = parseFloat(getComputedStyle(enLine).fontSize) || 22;
      document.body.style.cursor = 'ew-resize';
    });
    document.addEventListener('mousemove', (e) => {
      if (!resizing) return;
      const size = Math.min(52, Math.max(12, startSize + (e.clientX - startX) * 0.35));
      enLine.style.fontSize = size + 'px';
      nativeLine.style.fontSize = Math.round(size * 0.8) + 'px';
    });
    document.addEventListener('mouseup', () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = '';
      savePosition(overlay, enLine, nativeLine);
    });
  }

  function savePosition(overlay, enLine, nativeLine) {
    localStorage.setItem('eh-overlay-pos', JSON.stringify({
      left: overlay.style.left, top: overlay.style.top,
      enSize: enLine.style.fontSize, nativeSize: nativeLine.style.fontSize
    }));
  }

  function renderSubtitles(enText, nativeText) {
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (!enLine || !visible) return;

    if (enText === currentEnText && nativeText === currentNativeText) return;
    currentEnText = enText;
    currentNativeText = nativeText;

    // 영어 자막: 단어별 span으로 분리 (클릭 가능)
    enLine.innerHTML = '';
    if (enText) {
      const s = window.EH.settings;
      enLine.style.fontSize = s.enSize + 'px';
      enText.split(' ').forEach((word, i, arr) => {
        const span = document.createElement('span');
        span.className = 'eh-word';
        span.textContent = word + (i < arr.length - 1 ? ' ' : '');
        span.addEventListener('click', (e) => {
          e.stopPropagation();
          const clean = word.replace(/[^a-zA-Z']/g, '');
          if (clean && window.EH.WordPopup) {
            window.EH.WordPopup.show(clean, enText, nativeText,
              window.EH.adapter?.getCurrentTime() || 0, e.clientX, e.clientY);
          }
        });
        enLine.appendChild(span);
      });
    }

    // 모국어 자막
    const s = window.EH.settings;
    nativeLine.textContent = nativeText || '';
    nativeLine.style.fontSize = s.nativeSize + 'px';
    nativeLine.classList.toggle('hidden', s.mode === 'en' || !nativeText);

    // 스크립트 패널 하이라이트 업데이트
    if (window.EH.ScriptPanel) window.EH.ScriptPanel.highlight(enText);
  }

  function setup(adapter) {
    createDOM();
    adapter.onSubtitleChange((cues) => {
      const en = cues.find(c => c.lang === 'en')?.text || '';
      const native = cues.find(c => c.lang !== 'en')?.text || '';
      renderSubtitles(en, native);
    });
  }

  function applySettings(s) {
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (enLine) enLine.style.fontSize = s.enSize + 'px';
    if (nativeLine) {
      nativeLine.style.fontSize = s.nativeSize + 'px';
      nativeLine.classList.toggle('hidden', s.mode === 'en');
    }
    currentEnText = ''; // 다음 틱에서 강제 재렌더
  }

  function toggle() {
    visible = !visible;
    document.getElementById('eh-overlay')?.classList.toggle('hidden', !visible);
  }

  window.EH = window.EH || {};
  window.EH.SubtitleEngine = { setup, applySettings, toggle };
  window.EH.showToast = function(msg) {
    const t = document.getElementById('eh-toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2500);
  };
})();
