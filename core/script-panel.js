(function () {
  'use strict';

  let enCues = [];
  let nativeCues = [];
  let lastActiveIdx = -1;
  let searchQuery = '';
  let autoScrollEnabled = true;
  let savedSet = new Set();
  let saveFilter = 'all'; // 'all' | 'saved' | 'unsaved'

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  function findNativeText(enCue) {
    return nativeCues.find(c => Math.abs(c.start - enCue.start) < 1.0)?.text || '';
  }

  /**
   * Returns the Set of enCue texts that are already saved as sentences,
   * so renderList() can show a checkmark instead of "+"  for those lines.
   * Pure — takes the already-fetched sentence list, does no I/O itself.
   * Callers are expected to pre-filter the list to the current video's
   * contentId so this stays consistent with the footer's video-scoped count.
   * @param {{original: string}[]} savedSentences
   * @returns {Set<string>}
   */
  function savedTextSet(savedSentences) {
    return new Set((savedSentences || []).map(s => s.original));
  }

  /**
   * Case/whitespace-insensitive substring match used by the search box.
   * Pure — no DOM access.
   * @param {string} query
   * @param {{text: string}} enCue
   * @param {string} nativeText
   * @returns {boolean}
   */
  function matchesQuery(query, enCue, nativeText) {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return enCue.text.toLowerCase().includes(q) || (nativeText || '').toLowerCase().includes(q);
  }

  /**
   * Combines the search-query match with the saved/unsaved filter chip.
   * Pure — no DOM access.
   * @param {'all'|'saved'|'unsaved'} filter
   * @param {boolean} isSaved
   * @returns {boolean}
   */
  function matchesFilter(filter, isSaved) {
    if (filter === 'saved') return isSaved;
    if (filter === 'unsaved') return !isSaved;
    return true;
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

  // 패널이 현재 "밀어내기(fixed)" 상태인지, 아니면 #secondary에 임베드되어
  // 이미 확보된 공간을 쓰는 상태인지 — 플랫폼이 아니라 이 클래스로 판단해야
  // YouTube의 좁은 창/극장모드 폴백(fixed-mode)에서도 push가 적용된다.
  function _isPanelFixed() {
    const panel = document.getElementById('eh-panel');
    return !!(panel && panel.classList.contains('fixed-mode'));
  }

  // wrapper(임베드)와 panel(밀어내기) 중 현재 실제로 보여야 하는 대상을 기준으로
  // 숨김 여부를 판단한다 — toggle()의 detached 판정과 동일한 기준을 재사용.
  function _isPanelVisible() {
    const wrapper = document.getElementById('eh-panel-wrapper');
    const panel = document.getElementById('eh-panel');
    if (!panel) return false;
    const detached = !!(wrapper && panel.parentElement !== wrapper);
    const target = detached ? panel : (wrapper || panel);
    return !target.classList.contains('hidden');
  }

  function _setLayoutForPanel(visible) {
    const panel = document.getElementById('eh-panel');
    if (!_isPanelFixed()) {
      // 임베드 모드: #secondary 안에서 이미 확보된 사이드바 공간을 쓰므로
      // 본문을 별도로 밀어낼 필요가 없다 — wrapper만 보이기/숨기기.
      const wrapper = document.getElementById('eh-panel-wrapper');
      if (wrapper) wrapper.classList.toggle('hidden', !visible);
      const style = document.getElementById('eh-panel-push-style');
      if (style) style.textContent = '';
      return;
    }
    // 밀어내기(fixed) 모드 — YouTube의 사이드바 없는 폴백을 포함해 항상 본문을
    // 오른쪽으로 밀어 우측에 실제 여백을 만든다 (Language Reactor와 동일한 동작).
    let style = document.getElementById('eh-panel-push-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'eh-panel-push-style';
      document.head.appendChild(style);
    }
    if (!visible || !panel) { style.textContent = ''; return; }
    // getBoundingClientRect() reflects the panel's ACTUAL rendered width,
    // whether that width comes from an inline style (manual resize / saved
    // width) or from a CSS class like .expanded — parseInt(panel.style.width)
    // would silently fall back to 400 whenever the width is class-driven.
    const w = panel.getBoundingClientRect().width || 400;
    style.textContent = `
      html { overflow-x: hidden !important; }
      body { padding-right: ${w}px !important; box-sizing: border-box !important; }
    `;
  }

  function createDOM() {
    if (document.getElementById('eh-panel-wrapper') || document.getElementById('eh-panel')) return;

    const panel = document.createElement('div');
    panel.id = 'eh-panel';

    // Hoisted so applyMountStrategy() (defined below, and invoked from the
    // window 'resize' listener) can see the current expand state — it must
    // not re-embed the panel while expanded (see Bug 4 fix below).
    let expanded = false;
    // Holds the panel's inline width (from manual resize-drag or the saved
    // localStorage width) while expanded, so it can be restored afterwards.
    let savedInlineWidth = null;

    const resizeHandle = document.createElement('div');
    resizeHandle.id = 'eh-panel-resize';
    panel.appendChild(resizeHandle);

    const header = document.createElement('div');
    header.className = 'eh-panel-header';
    header.innerHTML =
      '<span class="eh-panel-title">Script</span>' +
      '<button class="eh-panel-btn" id="eh-panel-expand" title="실제 크기로 확장">⤢</button>' +
      '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
      '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
      '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
    panel.appendChild(header);

    const titleRow = document.createElement('div');
    titleRow.className = 'eh-panel-title-row';
    titleRow.id = 'eh-panel-title-row';
    panel.appendChild(titleRow);

    const searchRow = document.createElement('div');
    searchRow.className = 'eh-panel-search-row';
    searchRow.innerHTML =
      '<input type="text" id="eh-panel-search" class="eh-panel-search-input" placeholder="스크립트 검색">' +
      '<span class="eh-panel-search-count" id="eh-panel-search-count"></span>';
    panel.appendChild(searchRow);

    const filterRow = document.createElement('div');
    filterRow.className = 'eh-panel-filter-row';
    filterRow.innerHTML = `
      <div class="eh-panel-filter-chip active" data-filter="all">전체</div>
      <div class="eh-panel-filter-chip" data-filter="saved">저장한 줄</div>
      <div class="eh-panel-filter-chip" data-filter="unsaved">미저장</div>
    `;
    panel.appendChild(filterRow);
    filterRow.querySelectorAll('.eh-panel-filter-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        saveFilter = chip.dataset.filter;
        filterRow.querySelectorAll('.eh-panel-filter-chip').forEach(c => c.classList.toggle('active', c === chip));
        renderList();
      });
    });

    const list = document.createElement('div');
    list.className = 'eh-panel-list';
    list.id = 'eh-panel-list';
    list.innerHTML = '<div class="eh-panel-empty">자막 로딩 중...</div>';
    panel.appendChild(list);

    const footer = document.createElement('div');
    footer.className = 'eh-panel-footer';
    footer.innerHTML =
      '<span class="eh-panel-footer-count" id="eh-panel-footer-count"></span>' +
      `<div class="eh-panel-autoscroll-toggle" id="eh-panel-autoscroll">` +
      `<span class="eh-panel-autoscroll-switch${autoScrollEnabled ? ' on' : ''}"><span class="eh-panel-autoscroll-knob"></span></span>` +
      `<span class="eh-panel-autoscroll-label${autoScrollEnabled ? '' : ' dim'}">자동 스크롤</span>` +
      `</div>`;
    panel.appendChild(footer);

    searchRow.querySelector('#eh-panel-search').addEventListener('input', (e) => {
      searchQuery = e.target.value;
      renderList();
    });

    footer.querySelector('#eh-panel-autoscroll').addEventListener('click', () => {
      autoScrollEnabled = !autoScrollEnabled;
      const el = footer.querySelector('#eh-panel-autoscroll');
      el.querySelector('.eh-panel-autoscroll-switch').classList.toggle('on', autoScrollEnabled);
      el.querySelector('.eh-panel-autoscroll-label').classList.toggle('dim', !autoScrollEnabled);
    });

    if (_isYouTube()) {
      // ── LR과 동일한 구조: wrapper(relative block) + panel(absolute inset:0) ──
      // #secondary 사용 가능(넓은 창) → 임베드 / 0폭(좁은 창·극장) → 우측 고정 폴백
      const wrapper = document.createElement('div');
      wrapper.id = 'eh-panel-wrapper';
      wrapper.appendChild(panel);

      const applyMountStrategy = () => {
        // While expanded, the panel has been force-switched to a floating
        // fixed panel on document.body and the wrapper is intentionally
        // hidden/empty — re-running the mount strategy here (e.g. from the
        // resize listener) would silently re-embed it into #secondary,
        // leaving it invisible and desyncing the expand button's state.
        if (expanded) return;
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
          // 좁은 창/사이드바 없음: 우측 고정 밀어내기 폴백 (더 이상 오버레이가 아님)
          if (!panel.classList.contains('fixed-mode') || panel.parentElement !== document.body) {
            panel.classList.add('fixed-mode');
            wrapper.style.height = '';
            const savedW = localStorage.getItem('eh-panel-width');
            if (savedW) panel.style.width = savedW;
            document.body.appendChild(panel);
          }
        }
        // 임베드↔밀어내기 전환 때마다 push 스타일을 현재 모드/가시성에 맞춰 재적용.
        _setLayoutForPanel(_isPanelVisible());
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
    const expandBtn   = header.querySelector('#eh-panel-expand');

    exportBtn.addEventListener('click', exportScript);

    expandBtn.addEventListener('click', () => {
      expanded = !expanded;
      expandBtn.classList.toggle('active', expanded);
      if (_isYouTube()) {
        // YouTube: #secondary 임베드는 폭을 우리가 제어할 수 없으므로,
        // 확장 시엔 고정(fixed) 모드로 강제 전환해 더 넓은 폭을 확보한다.
        const wrapper = document.getElementById('eh-panel-wrapper');
        if (expanded) {
          // Same inline-width-shadows-CSS issue as the non-YouTube branch:
          // any pre-existing inline width (e.g. restored from localStorage
          // by the fixed-mode fallback, or set by a resize-drag before
          // expanding) would beat the .expanded class's 480px rule.
          savedInlineWidth = panel.style.width || null;
          panel.style.width = '';
          panel.classList.add('fixed-mode', 'expanded');
          if (wrapper) wrapper.classList.add('hidden');
          if (panel.parentElement !== document.body) document.body.appendChild(panel);
          _setLayoutForPanel(true);
        } else {
          // Returning to embedded mode must NOT carry any inline width —
          // the embedded CSS rule relies on left:0/right:0 with no explicit
          // width, and a leftover inline width would override that and
          // break the "fill the wrapper" layout. Unlike the non-YouTube
          // branch, we don't restore savedInlineWidth here; just clear it.
          panel.style.width = '';
          panel.classList.remove('fixed-mode', 'expanded');
          if (wrapper) wrapper.appendChild(panel);
          // 임베드 모드로 복귀 — _setLayoutForPanel이 fixed-mode 해제를 감지해
          // push 스타일을 지우고 wrapper의 hidden 상태를 다시 관리한다.
          _setLayoutForPanel(true);
        }
      } else {
        // An inline panel.style.width (set by manual resize-drag or restored
        // from localStorage on load) always beats the .expanded class's CSS
        // width, so it must be cleared while expanded and restored after.
        if (expanded) {
          savedInlineWidth = panel.style.width || null;
          panel.style.width = '';
        } else {
          panel.style.width = savedInlineWidth || '';
        }
        panel.classList.toggle('expanded', expanded);
        _setLayoutForPanel(true);
      }
    });

    collapseBtn.addEventListener('click', () => {
      const collapsed = panel.classList.toggle('collapsed');
      collapseBtn.textContent = collapsed ? '▶' : '✕';
    });

    hideBtn.addEventListener('click', () => {
      toggle(false);
      document.dispatchEvent(new CustomEvent('eh-panel-toggled', { detail: { visible: false } }));
      window.EH.showToast?.('패널 숨김 — 상단 바에서 다시 켤 수 있어요');
    });

    attachPanelResize(panel, resizeHandle, () => expanded, (w) => { savedInlineWidth = w; });
  }

  function attachPanelResize(panel, handle, isExpanded, setSavedWidth) {
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
      // 밀어내기 모드에서는 드래그 중에도 push 폭을 실시간으로 갱신해야
      // 우측 여백이 패널 크기와 어긋나지 않는다. (fixed는 이 지점에서 항상
      // true이지만, 위쪽 early-return 조건이 바뀌어도 안전하도록 명시적으로 체크.)
      if (fixed) _setLayoutForPanel(true);
      // If the user resizes WHILE expanded, the drag overwrites
      // panel.style.width directly — keep the saved pre-expand width in
      // sync so un-expanding restores the width just set here, not a
      // stale value from before expand was toggled on.
      if (isExpanded()) setSavedWidth(panel.style.width);
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
    const withMeta = enCues.map((cue, idx) => ({
      cue, idx, native: findNativeText(cue), isSaved: savedSet.has(cue.text)
    }));
    const visibleCues = withMeta.filter(({ cue, native, isSaved }) =>
      matchesQuery(searchQuery, cue, native) && matchesFilter(saveFilter, isSaved));

    const searchCountEl = document.getElementById('eh-panel-search-count');
    if (searchCountEl) {
      searchCountEl.textContent = searchQuery.trim() ? `${visibleCues.length}건` : `${enCues.length}줄`;
    }

    if (!visibleCues.length) {
      list.innerHTML = '<div class="eh-panel-empty">검색 결과가 없습니다</div>';
      return;
    }

    list.innerHTML = '';
    visibleCues.forEach(({ cue, idx, native, isSaved }) => {
      const isActive = idx === lastActiveIdx;

      const item = document.createElement('div');
      item.className = 'eh-panel-item';
      item.classList.toggle('active', isActive);
      item.dataset.idx = idx;

      const timeCol = document.createElement('div');
      timeCol.className = 'eh-panel-time-col';
      timeCol.innerHTML =
        `<span class="eh-panel-time">${formatTime(cue.start)}</span>` +
        (isActive ? '<span class="eh-panel-now">NOW</span>' : '');
      timeCol.addEventListener('click', (e) => {
        e.stopPropagation();
        window.EH.adapter.seekTo(cue.start + 0.1);
      });

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

      const actions = document.createElement('div');
      actions.className = 'eh-panel-item-actions';

      const copyBtn = document.createElement('button');
      copyBtn.className = 'eh-panel-item-copy';
      copyBtn.textContent = '⧉';
      copyBtn.title = '영어 문장 복사';
      copyBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (navigator.clipboard) navigator.clipboard.writeText(cue.text).catch(() => {});
        copyBtn.classList.add('copied');
        copyBtn.textContent = '✓';
        setTimeout(() => {
          copyBtn.classList.remove('copied');
          copyBtn.textContent = '⧉';
        }, 1400);
      });

      const saveBtn = document.createElement('button');
      saveBtn.className = 'eh-panel-item-save' + (isSaved ? ' saved' : '');
      saveBtn.textContent = isSaved ? '✓' : '＋';
      saveBtn.title = isSaved ? '이미 저장됨' : '문장 저장';
      saveBtn.disabled = isSaved;
      saveBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (isSaved) return;
        window.EH.Storage.saveSentence({
          original: cue.text,
          translation: native,
          timestamp: cue.start
        }).then(() => {
          savedSet.add(cue.text);
          window.EH.showToast?.('✓ 문장 저장됨');
          document.dispatchEvent(new CustomEvent('eh-item-saved'));
          renderList();
        });
      });

      actions.appendChild(copyBtn);
      actions.appendChild(saveBtn);

      item.appendChild(timeCol);
      item.appendChild(textWrap);
      item.appendChild(actions);
      list.appendChild(item);
    });

    const countEl = document.getElementById('eh-panel-footer-count');
    if (countEl) countEl.textContent = `저장 ${savedSet.size} / ${enCues.length}줄`;
  }

  function highlight(enText) {
    if (!enText) return;
    const idx = enCues.findIndex(c => c.text === enText);
    if (idx === -1 || idx === lastActiveIdx) return;
    lastActiveIdx = idx;
    // NOW 배지는 렌더링 시점(active/NOW 클래스)에 결정되므로, 활성 줄이 바뀔 때마다
    // 검색/필터로 새 활성 줄이 현재 DOM에 없더라도(=active가 null이어도) 무조건
    // 다시 그려서 이전 줄에 붙은 NOW 배지가 남지 않도록 한다.
    renderList();
    const active = document.querySelector(`.eh-panel-item[data-idx="${idx}"]`);
    if (active && autoScrollEnabled) active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function applySettings(s) {
    document.querySelectorAll('.eh-panel-native').forEach(el => {
      el.style.display = s.mode === 'en' ? 'none' : 'block';
    });
  }

  function toggle(forceVisible) {
    const wrapper = document.getElementById('eh-panel-wrapper');
    const panel = document.getElementById('eh-panel');
    // While expanded (or, on YouTube, whenever the panel has been detached
    // to the fixed-mode floating layout on document.body) the wrapper is
    // empty/hidden and no longer the visible element — toggling it would be
    // a no-op. Target the panel itself whenever it isn't currently mounted
    // inside the wrapper.
    const detached = !!(panel && wrapper && panel.parentElement !== wrapper);
    const target = detached ? panel : (wrapper || panel);
    if (!target) return undefined;
    let nowHidden;
    if (forceVisible !== undefined) {
      target.classList.toggle('hidden', !forceVisible);
      nowHidden = !forceVisible;
    } else {
      nowHidden = !target.classList.contains('hidden');
      target.classList.toggle('hidden');
    }
    _setLayoutForPanel(!nowHidden);
    return !nowHidden;
  }

  async function loadSavedSet() {
    try {
      const res = await chrome.runtime.sendMessage({ type: 'GET_ALL' });
      const sentences = (res && res.sentences) || [];
      // 저장 목록 전체(GET_ALL)에서 현재 영상(contentId)에 해당하는 것만 필터링.
      // 푸터의 "이 영상에서 저장" 라벨과 체크마크 둘 다 이 영상 범위로 통일해야
      // 개수와 체크마크 표시가 서로 어긋나지 않는다.
      const contentId = window.EH.adapter?.getPlatformMeta?.()?.contentId;
      const scoped = contentId
        ? sentences.filter(s => s.contentId === contentId)
        : sentences;
      savedSet = savedTextSet(scoped);
    } catch (_) {
      savedSet = new Set();
    }
  }

  function setup(adapter) {
    createDOM();
    const titleRow = document.getElementById('eh-panel-title-row');
    if (titleRow) titleRow.textContent = adapter.getPlatformMeta?.()?.title || '';
    const tracks = adapter.getSubtitleTracks();
    enCues = tracks.find(t => t.lang === 'en')?.cues || [];
    nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];

    loadSavedSet().then(renderList);

    if (typeof adapter.onTracksReady === 'function') {
      adapter.onTracksReady((tracks) => {
        enCues = tracks.find(t => t.lang === 'en')?.cues || [];
        nativeCues = tracks.find(t => t.lang !== 'en')?.cues || [];
        // SPA 네비게이션으로 영상이 바뀌면 제목도 새 영상 기준으로 갱신해야
        // 패널 상단에 이전 영상 제목이 그대로 남지 않는다.
        const titleRowEl = document.getElementById('eh-panel-title-row');
        if (titleRowEl) titleRowEl.textContent = adapter.getPlatformMeta?.()?.title || '';
        console.log('[EH:panel] onTracksReady — enCues:', enCues.length, 'nativeCues:', nativeCues.length, 'listEl:', !!document.getElementById('eh-panel-list'));
        renderList();
        // SPA 네비게이션(예: YouTube 영상 전환)으로 트랙이 교체될 때도
        // savedSet을 새 영상의 contentId 기준으로 다시 불러와야
        // 푸터 개수/체크마크가 이전 영상 데이터로 고정되지 않는다.
        loadSavedSet().then(renderList);
      });
    }

    renderList();
  }

  window.EH = window.EH || {};
  window.EH.ScriptPanel = { setup, highlight, toggle, applySettings, exportScript };
})();
