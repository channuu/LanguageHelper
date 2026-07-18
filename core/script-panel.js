(function () {
  'use strict';

  let enCues = [];    // [{ start, end, text }]
  let nativeCues = []; // [{ start, end, text }]
  let lastActiveIdx = -1;

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  function findNativeText(enCue) {
    return nativeCues.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';
  }

  function createDOM() {
    if (document.getElementById('eh-panel')) return;

    const panel = document.createElement('div');
    panel.id = 'eh-panel';

    const resizeHandle = document.createElement('div');
    resizeHandle.id = 'eh-panel-resize';
    panel.appendChild(resizeHandle);

    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    document.body.appendChild(panel);

    // 너비 복원
    const savedW = localStorage.getItem('eh-panel-width');
    if (savedW) panel.style.width = savedW;

    document.getElementById('eh-panel-collapse').addEventListener('click', () => {
      const collapsed = panel.classList.toggle('collapsed');
      document.getElementById('eh-panel-collapse').textContent = collapsed ? '▶' : '✕';
    });

    document.getElementById('eh-panel-hide').addEventListener('click', () => {
      panel.classList.add('hidden');
      _applyBodyPadding(0);
      window.EH.showToast?.('패널 숨김 — 팝업에서 다시 켤 수 있어요');
    });

    attachPanelResize(panel, resizeHandle);
    // 초기 표시 시 패딩 적용
    _applyBodyPadding(parseInt(panel.style.width) || 300);
  }

  function _applyBodyPadding(w) {
    document.documentElement.style.setProperty('padding-right', w ? w + 'px' : '', 'important');
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
      const w = Math.min(520, Math.max(180, startW - (e.clientX - startX)));
      panel.style.width = w + 'px';
      _applyBodyPadding(w);
    });
    document.addEventListener('mouseup', () => {
      if (!resizing) return;
      resizing = false;
      document.body.style.cursor = '';
      localStorage.setItem('eh-panel-width', panel.style.width);
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
    const panel = document.getElementById('eh-panel');
    if (!panel) return;
    let nowHidden;
    if (forceVisible !== undefined) {
      panel.classList.toggle('hidden', !forceVisible);
      nowHidden = !forceVisible;
    } else {
      nowHidden = !panel.classList.contains('hidden');
      panel.classList.toggle('hidden');
    }
    _applyBodyPadding(nowHidden ? 0 : (parseInt(panel.style.width) || 300));
  }

  function setup(adapter) {
    createDOM();
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    // 어댑터가 비동기로 트랙을 로드하는 경우를 위한 이벤트 리스너
    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        renderList();
      });
    }

    renderList();
  }

  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings };
})();
