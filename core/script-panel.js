(function () {
  'use strict';

  let enCues = [];
  let nativeCues = [];
  let lastActiveIdx = -1;
  let lastActiveChunkText = '';
  let searchQuery = '';
  let autoScrollEnabled = true;
  let savedSet = new Set();
  let saveFilter = 'all'; // 'all' | 'saved' | 'unsaved'
  let captionConflictSuspected = false;
  let captionLoadFailed = false;
  let pdfExportInFlight = false; // PDF 내보내기 중 중복 클릭 방지 — 탭/세션 키가 중복 생성되는 것을 막는다

  // §1h "한 줄에 표시할 분량" — 청크 분할 자체는 core/cue-utils.js가 담당한다.
  // 오버레이(adapters/*.js)도 같은 유틸을 써야 스크립트 패널과 자막 오버레이가
  // 항상 같은 문장을 보여준다 — 로직이 두 곳에 따로 있으면 반드시 갈라진다.
  function _buildChunkRows(cue, idx, native, isSaved, cueLines) {
    const chunks = window.EH.CueUtils.getChunksWithTiming(cue, cueLines);
    const nativeChunks = native ? window.EH.CueUtils.splitIntoNChunks(native, chunks.length) : [];
    return chunks.map((chunk, ci) => {
      return {
        cue, idx, native, isSaved, chunkText: chunk.text, chunkStart: chunk.start,
        isFirst: chunk.isFirst, chunkIndex: ci, nativeChunkText: nativeChunks[ci] || ''
      };
    });
  }

  function formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  // 오버레이(adapters/*.js)와 반드시 같은 매칭 로직을 써야 한다 — 각자
  // 다르게 구현돼 있으면 패널과 오버레이가 서로 다른 번역을 보여주는
  // 어긋남이 생긴다.
  function findNativeText(enCue) {
    return window.EH.CueUtils.findPairedCue(nativeCues, enCue)?.text || '';
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

  /* 인쇄(= PDF로 저장) 조판. 다운로드한 HTML을 사용자가 직접 인쇄할 때와
     확장의 PDF 내보내기가 같은 결과를 내야 하므로 두 경로 모두에 넣는다. */
  @page { margin: 18mm 14mm; }
  @media print {
    body { max-width: none; margin: 0; padding: 0; }
    /* 한 자막 줄이 페이지 경계에서 반으로 갈리지 않게 한다 */
    .row { break-inside: avoid; }
    /* 제목만 페이지 끝에 홀로 남는 것을 막는다 */
    header { break-after: avoid-page; }
    .no-print { display: none !important; }
  }
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

  /**
   * HTML/PDF 두 경로가 공유하는 준비 단계 — 빈 자막 가드, 플랫폼 메타 조회,
   * HTML 생성. 내보낼 자막이 없으면 토스트를 띄우고 null을 돌려준다.
   * @returns {{html: string, filename: string}|null}
   */
  function _prepareExport() {
    if (!enCues.length) {
      window.EH.showToast?.('내보낼 자막이 없어요');
      return null;
    }
    const meta = window.EH.adapter?.getPlatformMeta?.() || { platform: '', title: '' };
    const html = _buildExportHtml(enCues, nativeCues, meta);
    const filename = `${(meta.title || 'script').replace(/[\\/:*?"<>|]/g, '_')}`;
    return { html, filename };
  }

  function exportScriptHtml() {
    const prepared = _prepareExport();
    if (!prepared) return;
    const blob = new Blob([prepared.html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${prepared.filename}.html`;
    a.click();
    URL.revokeObjectURL(url);
  }

  /**
   * PDF는 라이브러리로 직접 만들지 않고 브라우저 인쇄 엔진에 맡긴다 —
   * 한글 폰트를 임베드할 필요가 없고 레이아웃 코드를 이중으로 두지 않아도 된다.
   * 인쇄는 확장 페이지에서 해야 한다: 콘텐츠 스크립트가 만든 blob: URL을 새 탭
   * 최상위로 여는 것은 호스트 페이지 CSP의 영향을 받아 Netflix/Disney+에서
   * 막힐 수 있다.
   */
  async function exportScriptPdf() {
    // HTML 생성 → 서비스워커 메시지 → 새 탭 열기까지 시간이 걸려서, 그 사이
    // 다시 클릭하면 탭과 세션 키가 두 배로 생긴다. 진행 중이면 조용히 무시한다.
    if (pdfExportInFlight) return;
    const prepared = _prepareExport();
    if (!prepared) return;
    pdfExportInFlight = true;
    try {
      const res = await chrome.runtime.sendMessage({
        type: 'EH_EXPORT_PRINT',
        payload: { html: prepared.html }
      });
      if (!res || !res.success) throw new Error(res?.error || 'no response');
    } catch (err) {
      // 확장이 방금 리로드되어 컨텍스트가 무효화된 경우에도 여기로 온다.
      console.error('[EH ScriptPanel] pdf export failed', err);
      window.EH.showToast?.('PDF 내보내기에 실패했어요');
    } finally {
      pdfExportInFlight = false;
    }
  }

  function _isYouTube() {
    return location.hostname.includes('youtube.com');
  }

  // 패널 높이를 실제 영상 플레이어(#movie_player) 높이에 맞춘다 — YouTube
  // 자체의 "패널 최대 높이" CSS 변수는 설명/댓글용으로 작게 잡혀 있어서
  // 스크립트를 읽기엔 짧다. 플레이어를 못 찾을 때만 그 변수로 폴백한다.
  function _getYouTubePanelHeight() {
    const player = document.querySelector('#movie_player');
    const playerHeight = player?.getBoundingClientRect().height;
    if (playerHeight && playerHeight > 100) return playerHeight;

    const flexy = document.querySelector('ytd-watch-flexy');
    if (!flexy) return 522;
    const raw = getComputedStyle(flexy).getPropertyValue('--ytd-watch-flexy-panel-max-height').trim();
    return parseFloat(raw) || 522;
  }

  // 검색결과 → 영상처럼 SPA로 페이지가 바뀔 때, 유튜브가 이전 페이지의
  // #primary/#secondary(0폭·hidden으로 남아있는 잔재)를 DOM에서 바로 지우지
  // 않는 경우가 있다 — 같은 id를 가진 진짜(현재 보이는) #secondary보다 이
  // 잔재가 document 순서상 먼저 나오면 document.querySelector('#secondary')가
  // 잘못된(0폭) 요소를 잡아서, 실제로는 사이드바 공간이 있는데도 "공간 없음"
  // 으로 오판해 밀어내기(fixed) 모드로 폴백해버린다. 현재 활성 watch flexy
  // 안에서만 찾아 이 잔재를 피한다.
  function _getSecondary() {
    const flexy = document.querySelector('ytd-watch-flexy');
    return flexy ? flexy.querySelector('#secondary') : document.querySelector('#secondary');
  }

  // 패널이 현재 "밀어내기(fixed)" 상태인지, 아니면 #secondary에 임베드되어
  // 이미 확보된 공간을 쓰는 상태인지 — 플랫폼이 아니라 이 클래스로 판단해야
  // YouTube의 좁은 창/극장모드 폴백(fixed-mode)에서도 push가 적용된다.
  function _isPanelFixed() {
    const panel = document.getElementById('eh-panel');
    return !!(panel && panel.classList.contains('fixed-mode'));
  }

  // 임베드↔밀어내기 모드는 SPA 네비게이션 중 비동기로 바뀔 수 있어서, toggle()
  // 호출 시점에 "지금 활성인 쪽"이라고 판단한 요소와 나중에 실제로 활성화되는
  // 요소가 달라지는 레이스가 있었다(예: 임베드로 판단해 wrapper에만 hidden을
  // 걸었는데, 직후 밀어내기로 전환되며 hidden 없는 panel이 body에 재장착되어
  // 다시 보여버림). wrapper/panel 둘 중 하나라도 hidden이면 숨김으로 본다 —
  // toggle()도 항상 둘 다에 같은 상태를 건다.
  function _isPanelVisible() {
    const wrapper = document.getElementById('eh-panel-wrapper');
    const panel = document.getElementById('eh-panel');
    if (!panel) return false;
    if (wrapper && wrapper.classList.contains('hidden')) return false;
    if (panel.classList.contains('hidden')) return false;
    return true;
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
    // YouTube의 ytd-app, Netflix의 .watch-video--player-view 둘 다
    // position:absolute라서 margin-right로는 안 밀린다 (Language Reactor의
    // 실제 적용 스타일을 두 플랫폼 모두 라이브로 확인해 검증됨 — 각 플랫폼의
    // 최상위 플레이어 컨테이너 width 자체를 직접 줄이는 방식을 쓰고 있었다).
    // 두 선택자 모두 다른 플랫폼에서는 매칭되는 요소가 없어 무해하다.
    style.textContent = `
      html { overflow-x: hidden !important; }
      body { margin-right: ${w}px !important; box-sizing: border-box !important; }
      ytd-app,
      .watch-video--player-view {
        width: calc(100% - ${w}px) !important;
        box-sizing: border-box !important;
      }
    `;
  }

  function createDOM() {
    if (document.getElementById('eh-panel-wrapper') || document.getElementById('eh-panel')) return;

    const panel = document.createElement('div');
    panel.id = 'eh-panel';

    // Hoisted so applyMountStrategy() (defined below, and invoked from the
    // window 'resize' listener) can see the current expand state — it must
    // not re-embed the panel while expanded.
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
      '<div class="eh-panel-export-menu hidden" id="eh-panel-export-menu">' +
        '<div class="eh-panel-export-item" data-format="html">HTML로 저장<span class="eh-panel-export-ext">.html</span></div>' +
        '<div class="eh-panel-export-item" data-format="pdf">PDF로 저장<span class="eh-panel-export-ext">.pdf</span></div>' +
      '</div>';
    // 메뉴를 헤더 기준으로 절대 배치하기 위한 컨테이닝 블록.
    header.style.position = 'relative';
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
        // 임베드↔밀어내기 모드 전환 시 열려 있는 export 메뉴를 닫는다.
        _closeExportMenu();
        const secondary = _getSecondary();
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
          // 좁은 창/사이드바 없음: 우측 고정 밀어내기 폴백
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
        // #secondary 임베드는 최대 6초까지 재시도하며 늦게 마운트될 수 있는데,
        // 그사이 자막이 먼저 로드되면 renderList()가 그때 #eh-panel-list를 못
        // 찾고 조용히 반환해 버려 목록이 "로딩 중"에 멈춘 채로 남는다 — 실제
        // 재생 중 자막이 하나라도 매칭되기 전까지(highlight() 호출 전까지)
        // 다시 그려지지 않는다. 마운트가 끝날 때마다 최신 데이터로 다시 그려
        // 이 경쟁 상태를 없앤다.
        renderList();
      };

      // #secondary 요소 자체는 존재해도, 유튜브가 그 안의 실제 레이아웃(사이드바
      // vs 가로 추천 선반)을 나중에 비동기로 계산해 폭이 0 → 실제 값으로 늦게
      // 바뀌는 경우가 있다 — 이때는 window 'resize' 이벤트가 안 뜨기 때문에
      // 처음 판단(고정 모드 폴백)에 갇혀서, 나중에 생긴 진짜 사이드바 영역과
      // 우리 고정 패널이 서로 겹쳐 보이는 버그가 있었다. ResizeObserver로
      // #secondary 자체의 크기 변화를 직접 감시해 그때그때 재평가한다.
      let observedSecondary = null;
      let secondaryResizeTimer = null;
      const secondaryResizeObserver = new ResizeObserver(() => {
        clearTimeout(secondaryResizeTimer);
        secondaryResizeTimer = setTimeout(applyMountStrategy, 200);
      });
      const watchSecondary = () => {
        const secondary = _getSecondary();
        if (secondary && secondary !== observedSecondary) {
          if (observedSecondary) secondaryResizeObserver.disconnect();
          observedSecondary = secondary;
          secondaryResizeObserver.observe(secondary);
        }
      };

      // 레이아웃이 준비될 때까지 재시도 후 전략 적용
      let tries = 0;
      const tryMount = () => {
        if (_getSecondary() || tries++ > 20) {
          applyMountStrategy();
          watchSecondary();
        } else {
          setTimeout(tryMount, 300);
        }
      };
      tryMount();

      // 창 크기 변경 시 임베드↔고정 재평가
      let resizeTimer = null;
      window.addEventListener('resize', () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(() => { applyMountStrategy(); watchSecondary(); }, 200);
      });
    } else {
      // 기타 플랫폼: body에 fixed 모드
      panel.classList.add('fixed-mode');
      const savedW = localStorage.getItem('eh-panel-width');
      if (savedW) panel.style.width = savedW;
      document.body.appendChild(panel);
      _setLayoutForPanel(true);
    }

    const exportBtn   = header.querySelector('#eh-panel-export');
    const expandBtn   = header.querySelector('#eh-panel-expand');
    const exportMenu  = header.querySelector('#eh-panel-export-menu');

    exportBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      // 자막이 없으면 메뉴를 열 이유가 없다 — 포맷을 고르게 한 뒤 실패
      // 토스트를 띄우는 것보다, 지금 바로 알려주는 편이 낫다.
      if (!enCues.length) {
        window.EH.showToast?.('내보낼 자막이 없어요');
        return;
      }
      exportMenu.classList.toggle('hidden');
      exportBtn.classList.toggle('active', !exportMenu.classList.contains('hidden'));
    });

    exportMenu.addEventListener('click', (e) => {
      const item = e.target.closest('.eh-panel-export-item');
      if (!item) return;
      _closeExportMenu();
      if (item.dataset.format === 'pdf') exportScriptPdf();
      else exportScriptHtml();
    });

    // 메뉴 바깥 클릭 / Esc로 닫는다. 패널이 body와 #secondary 사이를 오가므로
    // 리스너는 패널이 아니라 document에 건다.
    document.addEventListener('click', _closeExportMenu);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') _closeExportMenu();
    });

    expandBtn.addEventListener('click', () => {
      _closeExportMenu();
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

    attachPanelResize(panel, resizeHandle, () => expanded, (w) => { savedInlineWidth = w; });

    // 패널 안의 버튼(복사/저장/필터/자동스크롤 등)을 클릭하면 그 버튼이
    // 키보드 포커스를 가져가는데, 유튜브/넷플릭스 등은 포커스가 자기
    // 플레이어 영역을 벗어나 있으면 스페이스바 재생/일시정지 단축키를
    // 무시한다 — 검색창(타이핑이 필요)만 빼고, 패널 안 클릭이 포커스를
    // 가져가지 않게 해서 스페이스바가 계속 영상에 그대로 먹히게 한다.
    panel.addEventListener('mousedown', (e) => {
      if (e.target.closest('#eh-panel-search')) return;
      e.preventDefault();
    });
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
      // 우측 여백이 패널 크기와 어긋나지 않는다.
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
      if (captionConflictSuspected) {
        list.innerHTML = '<div class="eh-panel-empty eh-panel-empty-conflict">다른 자막 확장 프로그램(예: Language Reactor)과 충돌해<br>자막을 불러오지 못했어요.<br><br>해당 확장 프로그램을 잠시 꺼보시거나,<br>새로고침 후 다시 시도해 주세요.</div>';
      } else if (captionLoadFailed) {
        list.innerHTML = '<div class="eh-panel-empty eh-panel-empty-conflict">자막을 아직 불러오지 못했어요.<br>자동으로 다시 시도하고 있어요 — 계속되면<br>새로고침 후 다시 시도해 주세요.</div>';
      } else {
        list.innerHTML = '<div class="eh-panel-empty">자막 없음</div>';
      }
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
      const rows = _buildChunkRows(cue, idx, native, isSaved, s.cueLines);

      rows.forEach((row) => {
        // "짧게" 등으로 문장 하나가 여러 청크로 나뉘어도, 각 청크는 다른
        // 자막 줄과 똑같은 "독립된 스크립트 항목"으로 보여준다 — 자기만의
        // 실제 타임스탬프(chunkStart)를 갖고, 지금 재생 중인 청크에만 NOW가
        // 붙는다(문장 전체가 아니라 청크 단위로 활성 판정).
        const isRowActive = idx === lastActiveIdx && row.chunkText === lastActiveChunkText;
        const item = document.createElement('div');
        item.className = 'eh-panel-item';
        item.classList.toggle('active', isRowActive);
        item.dataset.idx = idx;
        item.dataset.chunk = row.chunkIndex;

        const timeCol = document.createElement('div');
        timeCol.className = 'eh-panel-time-col';
        timeCol.innerHTML =
          `<span class="eh-panel-time">${formatTime(row.chunkStart)}</span>` +
          (isRowActive ? '<span class="eh-panel-now">NOW</span>' : '');
        timeCol.addEventListener('click', (e) => {
          e.stopPropagation();
          window.EH.adapter.seekTo(row.chunkStart + 0.1);
        });

        const textWrap = document.createElement('div');
        textWrap.className = 'eh-panel-textwrap';

        const enSpan = document.createElement('span');
        enSpan.className = 'eh-panel-en';
        enSpan.textContent = row.chunkText;
        textWrap.appendChild(enSpan);

        // 각 청크가 이제 독립된 항목으로 보이므로(자기 타임스탬프 보유),
        // 번역도 전체를 반복하지 않고 그 청크에 해당하는 분량만 보여준다
        // (window.EH.CueUtils.splitIntoNChunks로 영어 청크 개수에 맞춰 나눔).
        // 복사/저장 버튼만 문장 전체를 대표하는 첫 청크에 남긴다.
        if (row.nativeChunkText) {
          const nativeSpan = document.createElement('span');
          nativeSpan.className = 'eh-panel-native';
          nativeSpan.textContent = row.nativeChunkText;
          if (s.mode === 'en') nativeSpan.style.display = 'none';
          textWrap.appendChild(nativeSpan);
        }

        const actions = document.createElement('div');
        actions.className = 'eh-panel-item-actions';

        if (row.isFirst) {
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
            }).then((res) => {
              if (window.EH.handleAuthRequired(res)) return;
              savedSet.add(cue.text);
              window.EH.showToast?.('✓ 문장 저장됨');
              document.dispatchEvent(new CustomEvent('eh-item-saved'));
              renderList();
            });
          });

          actions.appendChild(copyBtn);
          actions.appendChild(saveBtn);
        }

        item.appendChild(timeCol);
        item.appendChild(textWrap);
        item.appendChild(actions);
        // 시간 칼럼뿐 아니라 줄 전체(문장 본문 포함)를 클릭해도 그 지점으로
        // 이동한다 — 복사/저장 버튼은 각자 stopPropagation으로 이 핸들러를
        // 가로채지 않는다.
        item.addEventListener('click', () => {
          window.EH.adapter.seekTo(row.chunkStart + 0.1);
        });
        list.appendChild(item);
      });
    });

    const countEl = document.getElementById('eh-panel-footer-count');
    if (countEl) countEl.textContent = `저장 ${savedSet.size} / ${enCues.length}줄`;
  }

  // element.scrollIntoView()는 가장 가까운 스크롤 가능한 조상 하나가
  // 아니라, 필요하다고 판단되는 모든 조상(유튜브 임베드 모드에서는 패널을
  // 감싸는 유튜브 페이지 자체까지)을 스크롤해버릴 수 있다 — 그래서 패널
  // 안에서 줄을 클릭했을 뿐인데 유튜브 페이지 전체가 갑자기 아래로
  // 스크롤되는 원인이었다. #eh-panel-list의 scrollTop만 직접 계산해서
  // 조정하면 다른 조상(문서 전체)은 절대 건드리지 않는다.
  function _scrollActiveToTop(active) {
    const list = document.getElementById('eh-panel-list');
    if (!list || !active) return;
    const listRect = list.getBoundingClientRect();
    const activeRect = active.getBoundingClientRect();
    const target = list.scrollTop + (activeRect.top - listRect.top);
    list.scrollTo({ top: target, behavior: 'smooth' });
  }

  // 같은 대사("Hi" 등)가 자막 안에서 여러 번 반복되는 경우, 텍스트만으로
  // 찾으면 항상 처음 일치하는 위치가 선택돼버려서 실제 재생 위치와 다른
  // 곳이 NOW로 표시된다 — refTime(실제 재생 중인 cue의 시작 시각)이 있으면
  // 텍스트가 같은 후보들 중 시작 시각이 가장 가까운 것을 고른다.
  function _findActiveIdx(fullEnText, refTime) {
    if (refTime == null) return enCues.findIndex(c => c.text === fullEnText);
    let bestIdx = -1, bestDist = Infinity;
    for (let i = 0; i < enCues.length; i++) {
      if (enCues[i].text !== fullEnText) continue;
      const dist = Math.abs(enCues[i].start - refTime);
      if (dist < bestDist) { bestDist = dist; bestIdx = i; }
    }
    return bestIdx;
  }

  // fullEnText: 그 청크가 속한 원래 문장 전체(줄 번호를 찾는 데 씀).
  // chunkText: 지금 실제로 화면에 보이는 청크(오버레이와 동일) — 청크
  // 단위로 NOW 배지/스크롤 대상을 정확히 짚기 위해 별도로 받는다.
  // refTime: 실제 재생 중인 cue의 시작 시각 — 동일 텍스트 반복을 구분한다.
  function highlight(fullEnText, chunkText, refTime) {
    if (!fullEnText) return;
    const idx = _findActiveIdx(fullEnText, refTime);
    if (idx === -1) return;
    const resolvedChunk = chunkText || fullEnText;
    if (idx === lastActiveIdx && resolvedChunk === lastActiveChunkText) return;
    // idx가 한 번에 여러 칸 뛰면(순차 재생이 아니라) 사용자가 타임라인을
    // 직접 옮긴 것으로 본다 — 이 경우 새 위치를 패널 맨 위로 올려 그 뒤로
    // 이어지는 스크립트를 최대한 많이 보여준다.
    const seeked = lastActiveIdx !== -1 && Math.abs(idx - lastActiveIdx) > 1;
    lastActiveIdx = idx;
    lastActiveChunkText = resolvedChunk;
    // NOW 배지는 렌더링 시점(active 클래스)에 결정되므로, 활성 청크가 바뀔
    // 때마다 검색/필터로 새 활성 줄이 현재 DOM에 없더라도(=active가
    // null이어도) 무조건 다시 그려서 이전 청크에 붙은 NOW가 안 남게 한다.
    renderList();
    const active = document.querySelector('.eh-panel-item.active');
    if (!active || !autoScrollEnabled) return;

    if (seeked) {
      _scrollActiveToTop(active);
      return;
    }

    // 순차 재생 중에는 활성 줄이 이미 화면 안에 있으면 스크롤하지 않는다 —
    // 화면 아래로 벗어나려는 순간에만(=패널의 마지막으로 보이던 줄이 되는
    // 순간) 조금씩 끌려가는 대신 맨 위로 넘겨 다음 페이지 분량을 한 번에
    // 보여준다.
    const list = document.getElementById('eh-panel-list');
    const listRect = list?.getBoundingClientRect();
    const activeRect = active.getBoundingClientRect();
    const isVisible = listRect && activeRect.top >= listRect.top && activeRect.bottom <= listRect.bottom;
    if (!isVisible) _scrollActiveToTop(active);
  }

  function applySettings(s) {
    // cueLines가 바뀌면 청크 구성 자체(항목 개수)가 달라지므로 부분 패치 대신
    // 통째로 다시 그린다.
    renderList();
  }

  // 메뉴는 헤더에 절대 배치되므로, 패널이 숨겨지거나 임베드↔고정 모드가
  // 전환되는 동안 열린 채로 두면 엉뚱한 위치에 떠 있게 된다. 상태가 바뀌는
  // 모든 지점에서 닫는다.
  function _closeExportMenu() {
    const menu = document.getElementById('eh-panel-export-menu');
    const btn = document.getElementById('eh-panel-export');
    if (menu) menu.classList.add('hidden');
    if (btn) btn.classList.remove('active');
  }

  function toggle(forceVisible) {
    const wrapper = document.getElementById('eh-panel-wrapper');
    const panel = document.getElementById('eh-panel');
    if (!panel) return undefined;
    let nowHidden;
    if (forceVisible !== undefined) {
      nowHidden = !forceVisible;
    } else {
      nowHidden = _isPanelVisible();
    }
    // 임베드↔밀어내기 모드가 SPA 네비게이션 중 비동기로 바뀔 수 있어서
    // "지금 활성인 쪽" 하나만 판단해 거기에만 hidden을 걸면, 그 직후 모드가
    // 바뀌면서 hidden 없는 요소가 새로 화면에 나타나 다시 보여버리는
    // 레이스가 있었다 — wrapper/panel 둘 다에 항상 같은 상태를 건다.
    _closeExportMenu();
    if (wrapper) wrapper.classList.toggle('hidden', nowHidden);
    panel.classList.toggle('hidden', nowHidden);
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
        ? sentences.filter(s => s.content_id === contentId)
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

    // 다른 자막 확장 프로그램과의 충돌이 의심되면 "자막 없음" 대신 안내 문구를
    // 보여준다 — 성공적으로 자막을 받으면 다시 false로 돌아와 일반 상태로 복귀.
    document.addEventListener('eh-caption-conflict', (e) => {
      captionConflictSuspected = !!e.detail?.suspected;
      captionLoadFailed = !!e.detail?.loadFailed;
      renderList();
    });

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
  window.EH.ScriptPanel = {
    setup, highlight, toggle, applySettings,
    exportScriptHtml, exportScriptPdf
  };
})();
