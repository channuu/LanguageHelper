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

  // 위치는 "중심 x(px) + 하단 거리(px)"로 저장한다.
  // left = 중심 x, transform: translateX(-50%) 유지 → 글자수와 무관하게 중앙 고정.
  function restorePosition(overlay, enLine, nativeLine) {
    const saved = JSON.parse(localStorage.getItem('eh-overlay-pos') || 'null');
    if (saved && typeof saved.cx === 'number' && typeof saved.bottom === 'number') {
      overlay.style.left = saved.cx + 'px';
      overlay.style.bottom = saved.bottom + 'px';
      overlay.style.top = 'auto';
      overlay.style.transform = 'translateX(-50%)';
    } else if (saved && typeof saved.left === 'string' && typeof saved.top === 'string') {
      // 구버전 포맷({left,top} 절대좌표) → 신버전(중심 x + 하단 거리)으로 1회 변환
      const left = parseFloat(saved.left) || 0;
      const top = parseFloat(saved.top) || 0;
      const cx = left + overlay.offsetWidth / 2;
      const bottom = window.innerHeight - top - overlay.offsetHeight;
      overlay.style.left = cx + 'px';
      overlay.style.bottom = bottom + 'px';
      overlay.style.top = 'auto';
      overlay.style.transform = 'translateX(-50%)';
    }
    if (saved?.enSize) enLine.style.fontSize = saved.enSize;
    if (saved?.nativeSize) nativeLine.style.fontSize = saved.nativeSize;
  }

  function attachDrag(overlay, enLine, nativeLine) {
    let dragging = false, sx, sy, startCx, startBottom;
    overlay.addEventListener('mousedown', (e) => {
      if (e.target.id === 'eh-resize-handle' || e.target.classList.contains('eh-word')) return;
      dragging = true;
      overlay.classList.add('dragging');
      const r = overlay.getBoundingClientRect();
      sx = e.clientX; sy = e.clientY;
      startCx = r.left + r.width / 2;                 // 현재 중심 x
      startBottom = window.innerHeight - r.bottom;    // 현재 하단 거리
      e.preventDefault();
    });
    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      const cx = startCx + (e.clientX - sx);
      const bottom = startBottom - (e.clientY - sy);  // 아래로 끌면 bottom 감소
      overlay.style.left = cx + 'px';
      overlay.style.bottom = bottom + 'px';
      overlay.style.top = 'auto';
      overlay.style.transform = 'translateX(-50%)';   // 항상 중앙 앵커 유지
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
    const r = overlay.getBoundingClientRect();
    localStorage.setItem('eh-overlay-pos', JSON.stringify({
      cx: r.left + r.width / 2,
      bottom: window.innerHeight - r.bottom,
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
      nativeLine.classList.toggle('hidden', s.mode === 'en' || !currentNativeText);
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
