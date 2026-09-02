(function () {
  'use strict';

  let visible = true;
  let currentEnText = '';
  let currentMatches = [];
  let currentNativeText = '';
  let rafId = null;
  // 사용자가 오버레이를 직접 드래그해서 위치를 저장한 적이 있으면 그 이후로는
  // 자동 재중앙정렬을 하지 않는다 — 있는 그대로 존중.
  let userPositioned = false;

  // 오버레이는 body 기준 position:fixed라서 CSS left:50%는 항상 "뷰포트 전체"의
  // 중앙이다. 그런데 스크립트 패널이 열려 영상 영역이 좁아지면(밀어내기든
  // 임베드든) 실제 영상은 화면 왼쪽에 치우쳐 있으므로, 뷰포트 중앙에 고정된
  // 자막이 영상 중앙에서 벗어나 보인다 — 반드시 <video> 요소 자신의 실제
  // 렌더링 중심을 기준으로 잡아야 한다.
  function _getVideoCenterX() {
    const video = document.querySelector('video');
    const r = video?.getBoundingClientRect();
    if (r && r.width > 0) return r.left + r.width / 2;
    return window.innerWidth / 2;
  }

  // 넷플릭스 자체 하단 컨트롤바(재생바+버튼) 높이는 창 크기/배율/UI 버전에
  // 따라 달라진다 — 고정 px로 "이 정도면 충분하겠지"라고 잡으면 화면이
  // 작거나 배율이 다른 사용자에게는 여전히 겹치거나, 반대로 너무 위로
  // 떠버릴 수 있다. 실제 컨트롤바 요소의 렌더링 높이를 직접 읽어 그 위에
  // 자막을 놓는다 — data-uia는 넷플릭스가 자동화 테스트용으로 쓰는 값이라
  // 화면 크기와 무관하게 안정적이고, 클래스명(해시)보다 잘 안 바뀐다.
  function _getBottomClearance() {
    if (location.hostname.includes('netflix.com')) {
      const controls = document.querySelector('[data-uia="controls-standard"]')
        || document.querySelector('.watch-video--bottom-controls-container');
      const r = controls?.getBoundingClientRect();
      if (r && r.height > 0) return Math.round(window.innerHeight - r.top + 12);
    }
    return 80; // ui/overlay.css의 #eh-overlay 기본값과 동일
  }

  // §1h "한 줄에 표시할 분량" — 줄 수가 적을수록 박스를 좁혀 더 자주 줄바꿈되게
  // 한다. webkit-line-clamp로 넘치는 줄을 잘라버리면 오버레이만 스크립트
  // 패널과 다른(내용이 사라지는) 문장을 보여주게 되므로 쓰지 않는다 — 문장은
  // 절대 잘리지 않고, 박스 폭만 좁아져 줄바꿈이 더 잦아진다(길이가 짧아
  // 보이는 효과). 항상 스크립트 패널과 동일한 전체 텍스트를 보여준다.
  const CUE_MAX_WIDTH = { 1: '46vw', 2: '62vw', 3: '80vw' };

  function applyCueLines(overlay, enLine, nativeLine, cueLines) {
    overlay.style.maxWidth = CUE_MAX_WIDTH[cueLines] || CUE_MAX_WIDTH[2];
  }

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
    applyCueLines(overlay, enLine, nativeLine, window.EH.settings?.cueLines || 2);
    _watchVideoRecenter(overlay);
  }

  // 위치는 "중심 x(px) + 하단 거리(px)"로 저장한다.
  // left = 중심 x, transform: translateX(-50%) 유지 → 글자수와 무관하게 중앙 고정.
  function restorePosition(overlay, enLine, nativeLine) {
    const saved = JSON.parse(localStorage.getItem('eh-overlay-pos') || 'null');
    if (saved && typeof saved.cx === 'number' && typeof saved.bottom === 'number') {
      userPositioned = true;
      overlay.style.left = saved.cx + 'px';
      overlay.style.bottom = saved.bottom + 'px';
      overlay.style.top = 'auto';
      overlay.style.transform = 'translateX(-50%)';
    } else if (saved && typeof saved.left === 'string' && typeof saved.top === 'string') {
      // 구버전 포맷({left,top} 절대좌표) → 신버전(중심 x + 하단 거리)으로 1회 변환
      userPositioned = true;
      const left = parseFloat(saved.left) || 0;
      const top = parseFloat(saved.top) || 0;
      const cx = left + overlay.offsetWidth / 2;
      const bottom = window.innerHeight - top - overlay.offsetHeight;
      overlay.style.left = cx + 'px';
      overlay.style.bottom = bottom + 'px';
      overlay.style.top = 'auto';
      overlay.style.transform = 'translateX(-50%)';
    } else {
      // 저장된 위치가 없으면 뷰포트 중앙이 아니라 실제 영상 중앙에 맞춘다.
      overlay.style.left = _getVideoCenterX() + 'px';
      overlay.style.bottom = _getBottomClearance() + 'px';
      overlay.style.transform = 'translateX(-50%)';
    }
    if (saved?.enSize) enLine.style.fontSize = saved.enSize;
    if (saved?.nativeSize) nativeLine.style.fontSize = saved.nativeSize;
  }

  // 사용자가 직접 위치를 지정하지 않은 동안에는, 패널이 열리고 닫히거나 창
  // 크기/배율이 바뀌어 영상 영역이나 컨트롤바 높이가 달라질 때마다 자막을
  // 계속 그에 맞춰 재배치한다. <video>·컨트롤바 자신의 렌더링 크기를 직접
  // 관찰하므로 창 크기·배율·밀어내기/임베드 등 원인과 무관하게 항상 실제
  // 화면에 맞는 값을 쓴다 — px 하나를 고정으로 못박지 않는다.
  // createDOM() 시점엔 플랫폼이 아직 <video>/컨트롤바 엘리먼트를 만들지
  // 않은 경우가 많아 restorePosition()의 최초 계산이 폴백값으로 굳어버릴
  // 수 있다 — 실제로 나타날 때까지 재시도하고, 찾자마자 즉시 한 번
  // 재배치한 뒤 감시를 시작한다.
  function _watchVideoRecenter(overlay) {
    let observedVideo = null;
    let observedControls = null;
    let timer = null;
    const reposition = () => {
      if (userPositioned) return;
      overlay.style.left = _getVideoCenterX() + 'px';
      overlay.style.bottom = _getBottomClearance() + 'px';
    };
    const scheduleReposition = () => {
      clearTimeout(timer);
      timer = setTimeout(reposition, 150);
    };
    const tryObserve = () => {
      const video = document.querySelector('video');
      if (video && video !== observedVideo) {
        observedVideo = video;
        reposition();
        new ResizeObserver(scheduleReposition).observe(video);
      }
      const controls = document.querySelector('[data-uia="controls-standard"]')
        || document.querySelector('.watch-video--bottom-controls-container');
      if (controls && controls !== observedControls) {
        observedControls = controls;
        reposition();
        new ResizeObserver(scheduleReposition).observe(controls);
      }
    };
    tryObserve();
    new MutationObserver(tryObserve).observe(document.body, { subtree: true, childList: true });
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
    userPositioned = true;
    const r = overlay.getBoundingClientRect();
    localStorage.setItem('eh-overlay-pos', JSON.stringify({
      cx: r.left + r.width / 2,
      bottom: window.innerHeight - r.bottom,
      enSize: enLine.style.fontSize, nativeSize: nativeLine.style.fontSize
    }));
  }

  // enText: 지금 화면에 보여줄 텍스트(§1h 설정에 따라 문장 전체이거나 청크
  // 일부일 수 있다). fullText: 그 청크가 속한 원래 문장 전체 — 스크립트
  // 패널 하이라이트와 단어 팝업의 문맥은 항상 "원래 문장 전체" 기준이어야
  // 스크립트 패널이 보여주는 것과 어긋나지 않는다.
  function renderSubtitles(enText, nativeText, fullEnText, cueStart) {
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (!enLine || !visible) return;

    if (enText === currentEnText && nativeText === currentNativeText) return;
    currentEnText = enText;
    currentNativeText = nativeText;
    fullEnText = fullEnText || enText;

    // 영어 자막: 단어별 span으로 분리 (클릭 가능)
    enLine.innerHTML = '';
    currentMatches = [];
    if (enText) {
      const s = window.EH.settings;
      enLine.style.fontSize = s.enSize + 'px';
      const tokens = enText.split(' ');
      const spans = [];

      tokens.forEach((word, i, arr) => {
        const span = document.createElement('span');
        span.className = 'eh-word';
        span.textContent = word + (i < arr.length - 1 ? ' ' : '');
        span.addEventListener('click', (e) => {
          e.stopPropagation();
          const clean = word.replace(/[^a-zA-Z']/g, '');
          if (!clean || !window.EH.WordPopup) return;
          const hit = currentMatches.find(m => i >= m.start && i <= m.end);
          window.EH.WordPopup.show({
            word: clean,
            term: hit ? hit.term : null,
            sentence: fullEnText,
            translation: nativeText,
            timestamp: window.EH.adapter?.getCurrentTime() || 0,
            x: e.clientX, y: e.clientY
          });
        });
        spans.push(span);
        enLine.appendChild(span);
      });

      // 구동사 구간 표시. 비동기라 cue가 이미 바뀌었으면 버린다.
      const scannedFor = enText;
      chrome.runtime.sendMessage({ type: 'DICT_SCAN', payload: { text: enText } })
        .then((res) => {
          if (!res || !res.success || scannedFor !== currentEnText) return;
          currentMatches = res.matches;
          for (const m of res.matches) {
            for (let i = m.start; i <= m.end && i < spans.length; i++) {
              spans[i].classList.add('eh-mwe');
            }
          }
        })
        .catch(() => {});
    }

    // 모국어 자막
    const s = window.EH.settings;
    nativeLine.textContent = nativeText || '';
    nativeLine.style.fontSize = s.nativeSize + 'px';
    nativeLine.classList.toggle('hidden', s.mode === 'en' || !nativeText);

    // 스크립트 패널 하이라이트 업데이트 — 청크가 아니라 원래 문장 전체 기준.
    // cueStart를 같이 넘겨서, 같은 문장("Hi" 등)이 자막 여러 곳에 반복돼도
    // 패널이 실제 재생 중인 그 자리를 정확히 짚을 수 있게 한다(텍스트만으로
    // 찾으면 항상 첫 번째로 일치하는 곳이 선택돼버린다).
    if (window.EH.ScriptPanel) window.EH.ScriptPanel.highlight(fullEnText, enText, cueStart);
  }

  function setup(adapter) {
    createDOM();
    adapter.onSubtitleChange((cues) => {
      const enCue = cues.find(c => c.lang === 'en');
      const native = cues.find(c => c.lang !== 'en')?.text || '';
      renderSubtitles(enCue?.text || '', native, enCue?.fullText, enCue?.cueStart);
    });
  }

  function applySettings(s) {
    const overlay = document.getElementById('eh-overlay');
    const enLine = document.getElementById('eh-en-line');
    const nativeLine = document.getElementById('eh-native-line');
    if (enLine) enLine.style.fontSize = s.enSize + 'px';
    if (nativeLine) {
      nativeLine.style.fontSize = s.nativeSize + 'px';
      nativeLine.classList.toggle('hidden', s.mode === 'en' || !currentNativeText);
    }
    if (overlay && enLine && nativeLine) applyCueLines(overlay, enLine, nativeLine, s.cueLines);
    currentEnText = ''; // 다음 틱에서 강제 재렌더
  }

  function toggle() {
    visible = !visible;
    document.getElementById('eh-overlay')?.classList.toggle('hidden', !visible);
    return visible;
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

  /**
   * 저장류 메시지의 응답이 auth_required이면 안내를 띄우고 true를 돌려준다.
   * 로그인 폼 자체는 확장 페이지에서만 띄운다 — 콘텐츠 스크립트는 호스트
   * 페이지와 DOM을 공유하므로 여기서 비밀번호를 받으면 안 된다.
   */
  window.EH.handleAuthRequired = function (res) {
    if (!res || res.error !== 'auth_required') return false;
    window.EH.showToast?.('로그인이 필요해요 · 클릭해서 로그인');
    const toast = document.getElementById('eh-toast');
    if (toast) {
      toast.style.cursor = 'pointer';
      toast.onclick = () => {
        chrome.runtime.sendMessage({ type: 'EH_OPEN_LOGIN' });
        toast.onclick = null;
      };
    }
    return true;
  };
})();
